// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TheImdDaily} from "../src/TheImdDaily.sol";

/// @dev Test-only CREATE2 deployer; not part of the delivered application.
contract TokenFactoryHarness {
    function deploy(bytes32 salt) external returns (TheImdDaily) {
        return new TheImdDaily{salt: salt}();
    }
}

/// @dev A transfer must not call recipient hooks, even when they would revert.
contract RejectsCallbacks {
    fallback() external {
        revert("unexpected callback");
    }
}

contract TheImdDailyTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    TheImdDaily private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new TheImdDaily();
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "TheImdDaily");
        assertEq(token.symbol(), "TID");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        TheImdDaily fresh = new TheImdDaily();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_Create2MintsToFactoryInsteadOfCallerOrOrigin() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        vm.prank(alice, bob);
        TheImdDaily deployed = factory.deploy(keccak256("launch test"));
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(alice), 0);
        assertEq(deployed.balanceOf(bob), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
    }

    function test_TransferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 17e18);
        assertTrue(token.transfer(alice, 17e18));
        assertEq(token.balanceOf(address(this)), SUPPLY - 17e18);
        assertEq(token.balanceOf(alice), 17e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferEntireSupply() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_SelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferDoesNotCallRecipient() public {
        RejectsCallbacks recipient = new RejectsCallbacks();
        assertTrue(token.transfer(address(recipient), 1));
        assertEq(token.balanceOf(address(recipient)), 1);
    }

    function test_TransferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        token.transfer(address(0), 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferWithInsufficientBalanceReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1)
        );
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_MaximumTransferRevertsWithoutOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(this),
                SUPPLY,
                type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ApproveEmitsEventAndCanReplaceAndRevoke() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 100);
        assertTrue(token.approve(spender, 100));
        assertEq(token.allowance(address(this), spender), 100);
        assertTrue(token.approve(spender, 40));
        assertEq(token.allowance(address(this), spender), 40);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ApproveFromEmptyAccountIsAllowed() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_TransferFromConsumesAllowanceAndEmitsTransfer() public {
        assertTrue(token.approve(spender, 100));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 40);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 40));
        assertEq(token.allowance(address(this), spender), 60);
        assertEq(token.balanceOf(alice), 40);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 60));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 60);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100);
    }

    function test_TransferFromInfiniteAllowanceIsNotReduced() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_TransferFromToSelfConsumesAllowanceWithoutChangingBalance() public {
        assertTrue(token.approve(spender, 100));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 40));
        assertEq(token.allowance(address(this), spender), 60);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroTransferFromRequiresNoAllowance() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), 0);
    }

    function test_AllowanceCannotBeUsedByAnotherSpender() public {
        assertTrue(token.approve(spender, 100));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1)
        );
        vm.prank(bob);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_AllowanceCannotBeUsedForAnotherOwner() public {
        assertTrue(token.transfer(alice, 100));
        assertTrue(token.approve(spender, 100));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.allowance(address(this), spender), 100);
    }

    function test_RevokedAllowanceCannotBeSpent() public {
        assertTrue(token.approve(spender, 100));
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_DeployerCannotSpendHolderBalanceWithoutApproval() public {
        assertTrue(token.transfer(alice, 100));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1
            )
        );
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 100);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function test_OwnerUsingTransferFromAlsoNeedsAllowance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1
            )
        );
        token.transferFrom(address(this), alice, 1);
        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
    }

    function test_TransferFromBalanceFailureRollsBackAllowance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 100));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 100)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, 100);
        assertEq(token.allowance(alice, spender), 100);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromZeroReceiverRollsBackAllowance() public {
        assertTrue(token.approve(spender, 100));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 100);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_NoMintBurnOrAdministrativeEntryPoints() public {
        assertTrue(token.transfer(alice, 100));
        bytes[] memory attempts = new bytes[](19);
        attempts[0] = abi.encodeWithSignature("mint(address,uint256)", bob, SUPPLY);
        attempts[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        attempts[2] = abi.encodeWithSignature("mint()");
        attempts[3] = abi.encodeWithSignature("issue(uint256)", SUPPLY);
        attempts[4] = abi.encodeWithSignature("burn(uint256)", 1);
        attempts[5] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        attempts[6] = abi.encodeWithSignature("pause()");
        attempts[7] = abi.encodeWithSignature("unpause()");
        attempts[8] = abi.encodeWithSignature("blacklist(address)", alice);
        attempts[9] = abi.encodeWithSignature("freeze(address)", alice);
        attempts[10] = abi.encodeWithSignature("seize(address)", alice);
        attempts[11] = abi.encodeWithSignature("transferOwnership(address)", bob);
        attempts[12] = abi.encodeWithSignature("setOwner(address)", bob);
        attempts[13] = abi.encodeWithSignature("setMinter(address)", bob);
        attempts[14] = abi.encodeWithSignature("initialize(address)", bob);
        attempts[15] = abi.encodeWithSignature("upgradeTo(address)", bob);
        attempts[16] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        attempts[17] = abi.encodeWithSignature("owner()");
        attempts[18] = abi.encodeWithSignature("_mint(address,uint256)", bob, SUPPLY);
        address[3] memory callers = [address(this), alice, bob];
        for (uint256 i; i < callers.length; ++i) {
            for (uint256 j; j < attempts.length; ++j) {
                vm.prank(callers[i]);
                (bool ok,) = address(token).call(attempts[j]);
                assertFalse(ok, "unexpected privileged entry point");
                assertEq(token.totalSupply(), SUPPLY);
                assertEq(token.balanceOf(alice), 100);
                assertEq(token.balanceOf(bob), 0);
            }
        }
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function test_LaunchDistributionAndCustodyTransfersArriveWhole() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        TheImdDaily launched = factory.deploy(bytes32(uint256(1)));
        address distributor = makeAddr("distributor fixture");
        address poolCustodian = makeAddr("pool custodian fixture");
        address remainder = makeAddr("remainder fixture");
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * 85 / 100;
        vm.startPrank(address(factory));
        assertTrue(launched.transfer(distributor, swarm));
        assertTrue(launched.transfer(poolCustodian, pool));
        assertTrue(launched.transfer(remainder, SUPPLY - swarm - pool));
        vm.stopPrank();
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), swarm);
        assertEq(launched.balanceOf(poolCustodian), pool);
        assertEq(launched.balanceOf(remainder), SUPPLY / 20);
        vm.prank(distributor);
        assertTrue(launched.transfer(alice, swarm));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(alice), swarm);
        vm.prank(poolCustodian);
        assertTrue(launched.transfer(bob, 10e18));
        assertEq(launched.balanceOf(bob), 10e18);
        vm.prank(bob);
        assertTrue(launched.transfer(poolCustodian, 10e18));
        assertEq(launched.balanceOf(bob), 0);
        assertEq(launched.balanceOf(poolCustodian), pool);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_RejectsNativeCurrency() public {
        vm.deal(alice, 1);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferConservesSupply(uint256 rawAmount, address recipient) public {
        vm.assume(recipient != address(0));
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        if (recipient == address(this)) {
            assertEq(token.balanceOf(address(this)), SUPPLY);
        } else {
            assertEq(token.balanceOf(recipient), amount);
            assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedTransferAccounting(uint256 rawApproval, uint256 rawAmount) public {
        uint256 approval = bound(rawApproval, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, approval);
        assertTrue(token.approve(spender, approval));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), approval - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverdraftRevertsAtomically(uint256 rawBalance, uint256 rawAmount) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        assertTrue(token.transfer(alice, balance));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount
            )
        );
        vm.prank(alice);
        token.transfer(bob, amount);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_AllowanceOverspendRevertsAtomically(uint256 rawApproval, uint256 rawAmount)
        public
    {
        uint256 approval = bound(rawApproval, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, approval + 1, SUPPLY);
        assertTrue(token.approve(spender, approval));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, approval, amount
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), approval);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
