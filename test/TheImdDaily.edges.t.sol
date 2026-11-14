// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TheImdDaily} from "../src/TheImdDaily.sol";

/// @notice Boundary and property tests at the edges the main suite does not pin: exact limits,
/// arbitrary parties, event shape of delegated transfers, and repeated calls.
contract TheImdDailyEdgesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    bytes32 private constant TRANSFER_SIG = keccak256("Transfer(address,address,uint256)");
    bytes32 private constant APPROVAL_SIG = keccak256("Approval(address,address,uint256)");

    TheImdDaily private token;
    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");
    address private spender = makeAddr("spender");

    function setUp() public {
        token = new TheImdDaily();
    }

    function test_SupplyConstantIsExactlyOneBillionWholeTokens() public view {
        assertEq(token.INITIAL_SUPPLY(), 1e27);
        assertEq(token.totalSupply() / 10 ** token.decimals(), 1_000_000_000);
        assertEq(token.totalSupply() % 10 ** token.decimals(), 0);
    }

    function test_EachDeploymentMintsOnlyToItsOwnDeployer() public {
        vm.prank(alice);
        TheImdDaily a = new TheImdDaily();
        vm.prank(bob);
        TheImdDaily b = new TheImdDaily();
        assertEq(a.balanceOf(alice), SUPPLY);
        assertEq(b.balanceOf(bob), SUPPLY);
        assertEq(a.balanceOf(bob), 0);
        assertEq(b.balanceOf(alice), 0);
        // A second deployment does not touch the first token.
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferExactBalanceSucceedsAndOneMoreFails() public {
        assertTrue(token.transfer(alice, 500));
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 500, 501)
        );
        token.transfer(bob, 501);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 500));
        assertEq(token.balanceOf(alice), 0);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1)
        );
        token.transfer(bob, 1);
    }

    function test_TransferFromExactAllowanceThenOneWeiMoreFails() public {
        assertTrue(token.approve(spender, 77));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 77));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 77);
    }

    /// @dev Allowance is checked before balance: a spender over both limits sees the allowance error.
    function test_AllowanceCheckedBeforeBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 10));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, 10, 11
            )
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, 11);
    }

    function test_TransferFromZeroOwnerRevertsAsInsufficientAllowance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(0), bob, 1);
    }

    /// @dev OpenZeppelin 5 does not emit Approval when an allowance is spent: exactly one Transfer.
    function test_TransferFromEmitsOnlyTransfer() public {
        assertTrue(token.approve(spender, 100));
        vm.recordLogs();
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 30));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], TRANSFER_SIG);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(address(this)))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[0].data, (uint256)), 30);
    }

    function test_ApproveEmitsExactlyOneApprovalAndIsIdempotent() public {
        for (uint256 i; i < 3; ++i) {
            vm.recordLogs();
            assertTrue(token.approve(spender, 42));
            Vm.Log[] memory logs = vm.getRecordedLogs();
            assertEq(logs.length, 1);
            assertEq(logs[0].topics[0], APPROVAL_SIG);
            assertEq(abi.decode(logs[0].data, (uint256)), 42);
            assertEq(token.allowance(address(this), spender), 42);
        }
    }

    /// @dev Approving does not add to an earlier allowance; it replaces it, upward or downward.
    function testFuzz_ApproveReplacesNotAccumulates(uint256 first, uint256 second) public {
        assertTrue(token.approve(spender, first));
        assertTrue(token.approve(spender, second));
        assertEq(token.allowance(address(this), spender), second);
    }

    /// @dev Tokens sent to the token contract itself are accepted and not recoverable by anyone,
    /// since there is no rescue function; the supply is unchanged.
    function test_TransferToTokenContractIsAcceptedAndSupplyUnchanged() public {
        assertTrue(token.transfer(address(token), 5));
        assertEq(token.balanceOf(address(token)), 5);
        assertEq(token.totalSupply(), SUPPLY);
        (bool ok,) =
            address(token).call(abi.encodeWithSignature("rescue(address,uint256)", alice, 5));
        assertFalse(ok);
        assertEq(token.balanceOf(address(token)), 5);
    }

    function testFuzz_TransferBetweenArbitraryParties(
        address from,
        address to,
        uint256 seedAmount,
        uint256 sendAmount
    ) public {
        from = address(uint160(bound(uint160(from), 1, type(uint160).max)));
        to = address(uint160(bound(uint160(to), 1, type(uint160).max)));
        vm.assume(from != address(this) && to != address(this));
        uint256 funded = bound(seedAmount, 0, SUPPLY);
        assertTrue(token.transfer(from, funded));
        uint256 amount = bound(sendAmount, 0, funded);
        uint256 toBefore = token.balanceOf(to);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        if (from == to) {
            assertEq(token.balanceOf(from), funded);
        } else {
            assertEq(token.balanceOf(from), funded - amount);
            assertEq(token.balanceOf(to), toBefore + amount);
        }
        assertEq(token.balanceOf(address(this)), SUPPLY - funded);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromArbitraryParties(
        address owner,
        address delegate,
        address to,
        uint256 rawFund,
        uint256 rawAllow,
        uint256 rawAmount
    ) public {
        owner = address(uint160(bound(uint160(owner), 1, type(uint160).max)));
        delegate = address(uint160(bound(uint160(delegate), 1, type(uint160).max)));
        to = address(uint160(bound(uint160(to), 1, type(uint160).max)));
        vm.assume(owner != address(this) && to != address(this));
        uint256 funded = bound(rawFund, 0, SUPPLY);
        assertTrue(token.transfer(owner, funded));
        uint256 allowed = bound(rawAllow, 0, SUPPLY);
        vm.prank(owner);
        assertTrue(token.approve(delegate, allowed));
        uint256 amount = bound(rawAmount, 0, funded < allowed ? funded : allowed);
        uint256 toBefore = token.balanceOf(to);
        vm.prank(delegate);
        assertTrue(token.transferFrom(owner, to, amount));
        assertEq(token.allowance(owner, delegate), allowed - amount);
        if (owner == to) {
            assertEq(token.balanceOf(owner), funded);
        } else {
            assertEq(token.balanceOf(owner), funded - amount);
            assertEq(token.balanceOf(to), toBefore + amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Over either limit, transferFrom reverts and changes nothing at all.
    function testFuzz_TransferFromOverLimitIsAtomic(
        uint256 rawFund,
        uint256 rawAllow,
        uint256 rawAmount
    ) public {
        uint256 funded = bound(rawFund, 0, SUPPLY - 1);
        uint256 allowed = bound(rawAllow, 0, SUPPLY);
        assertTrue(token.transfer(alice, funded));
        vm.prank(alice);
        assertTrue(token.approve(spender, allowed));
        uint256 limit = funded < allowed ? funded : allowed;
        uint256 amount = bound(rawAmount, limit + 1, type(uint256).max);
        if (amount > allowed) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount
                )
            );
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector, alice, funded, amount
                )
            );
        }
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.balanceOf(alice), funded);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), allowed);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev An infinite allowance is never reduced, however many times it is spent.
    function testFuzz_InfiniteAllowanceSurvivesRepeatedSpends(uint8 rawCount, uint256 rawAmount)
        public
    {
        uint256 count = bound(rawCount, 1, 20);
        uint256 amount = bound(rawAmount, 0, SUPPLY / 20);
        assertTrue(token.approve(spender, type(uint256).max));
        for (uint256 i; i < count; ++i) {
            vm.prank(spender);
            assertTrue(token.transferFrom(address(this), alice, amount));
        }
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), amount * count);
    }

    /// @dev type(uint256).max - 1 is an ordinary finite allowance and is decremented.
    function test_AllowanceJustBelowMaxIsDecremented() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
    }

    function test_SpenderCannotUseApprovalToApproveOthers() public {
        assertTrue(token.approve(spender, 100));
        vm.prank(spender);
        assertTrue(token.approve(bob, 100));
        assertEq(token.allowance(spender, bob), 100);
        assertEq(token.allowance(address(this), bob), 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1)
        );
        vm.prank(bob);
        token.transferFrom(address(this), bob, 1);
    }

    function test_RejectsUnknownCalldataAndEther() public {
        (bool ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (ok,) = address(token).call{value: 1}(abi.encodeCall(token.transfer, (bob, 0)));
        assertFalse(ok, "non-payable transfer accepted ether");
        assertEq(address(token).balance, 0);
    }
}
