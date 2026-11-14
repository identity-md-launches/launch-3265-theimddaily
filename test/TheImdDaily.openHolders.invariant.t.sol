// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TheImdDaily} from "../src/TheImdDaily.sol";

/// @dev Drives the token with an open set of holders: any non-zero address the fuzzer picks can
/// receive, and from then on hold, spend and approve. Rejected operations are driven too and must
/// leave every balance and allowance as it was.
contract OpenHolderHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    TheImdDaily public immutable token;

    address[] public holders;
    mapping(address => bool) public tracked;
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public ghostMovedOut;
    uint256 public rejectedCalls;

    constructor() {
        token = new TheImdDaily();
        _track(address(this));
        ghostBalance[address(this)] = SUPPLY;
    }

    function holderCount() external view returns (uint256) {
        return holders.length;
    }

    function _track(address a) internal {
        if (!tracked[a]) {
            tracked[a] = true;
            holders.push(a);
        }
    }

    function _holder(uint256 seed) internal view returns (address) {
        return holders[seed % holders.length];
    }

    function _recipient(uint256 seed, address fresh) internal returns (address to) {
        // Half the time an existing holder, half the time whatever the fuzzer supplied.
        if (seed % 2 == 0 || fresh == address(0) || fresh == VM_ADDRESS || fresh == CONSOLE) {
            to = _holder(seed / 2);
        } else {
            to = fresh;
            _track(to);
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, address fresh, uint256 amountSeed)
        external
    {
        address from = _holder(fromSeed);
        address to = _recipient(toSeed, fresh);
        uint256 amount = bound(amountSeed, 0, ghostBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        if (from != to) ghostMovedOut += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, address fresh, uint256 amountSeed)
        external
    {
        address owner = _holder(ownerSeed);
        address spender = _recipient(spenderSeed, fresh);
        uint256 amount = amountSeed % 5 == 0 ? type(uint256).max : bound(amountSeed, 0, SUPPLY * 2);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        ghostAllowance[owner][spender] = amount;
    }

    function transferFrom(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        address fresh,
        uint256 amountSeed
    ) external {
        address owner = _holder(ownerSeed);
        address spender = _holder(spenderSeed);
        address to = _recipient(toSeed, fresh);
        uint256 allowed = ghostAllowance[owner][spender];
        uint256 cap = allowed < ghostBalance[owner] ? allowed : ghostBalance[owner];
        uint256 amount = bound(amountSeed, 0, cap);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        if (allowed != type(uint256).max) ghostAllowance[owner][spender] = allowed - amount;
        ghostBalance[owner] -= amount;
        ghostBalance[to] += amount;
        if (owner != to) ghostMovedOut += amount;
    }

    function overdraft(uint256 fromSeed, uint256 toSeed, uint256 extraSeed) external {
        address from = _holder(fromSeed);
        address to = _holder(toSeed);
        uint256 balance = ghostBalance[from];
        uint256 amount = balance + bound(extraSeed, 1, type(uint256).max - balance);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount
            )
        );
        vm.prank(from);
        token.transfer(to, amount);
        ++rejectedCalls;
    }

    function overspendAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = _holder(ownerSeed);
        address spender = _holder(spenderSeed);
        address to = _holder(toSeed);
        uint256 allowed = ghostAllowance[owner][spender];
        if (allowed == type(uint256).max) return;
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(owner, to, allowed + 1);
        ++rejectedCalls;
    }

    function sendToZero(uint256 fromSeed, uint256 amountSeed) external {
        address from = _holder(fromSeed);
        uint256 amount = bound(amountSeed, 0, ghostBalance[from]);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(from);
        token.transfer(address(0), amount);
        ++rejectedCalls;
    }

    function approveZero(uint256 ownerSeed, uint256 amountSeed) external {
        address owner = _holder(ownerSeed);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
        vm.prank(owner);
        token.approve(address(0), amountSeed);
        ++rejectedCalls;
    }

    function privilegedAttempt(uint256 callerSeed, uint256 which) external {
        address caller = _holder(callerSeed);
        address victim = _holder(callerSeed / 7);
        bytes memory data;
        uint256 w = which % 5;
        if (w == 0) data = abi.encodeWithSignature("mint(address,uint256)", caller, SUPPLY);
        else if (w == 1) data = abi.encodeWithSignature("burn(uint256)", 1);
        else if (w == 2) data = abi.encodeWithSignature("burnFrom(address,uint256)", victim, 1);
        else if (w == 3) data = abi.encodeWithSignature("pause()");
        else data = abi.encodeWithSignature("seize(address)", victim);
        vm.prank(caller);
        (bool ok,) = address(token).call(data);
        assertFalse(ok, "a privileged entry point exists");
        ++rejectedCalls;
    }
}

contract TheImdDailyOpenHolderInvariantTest is StdInvariant, Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    OpenHolderHandler private handler;
    TheImdDaily private token;

    function setUp() public {
        handler = new OpenHolderHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = OpenHolderHandler.transfer.selector;
        selectors[1] = OpenHolderHandler.approve.selector;
        selectors[2] = OpenHolderHandler.transferFrom.selector;
        selectors[3] = OpenHolderHandler.overdraft.selector;
        selectors[4] = OpenHolderHandler.overspendAllowance.selector;
        selectors[5] = OpenHolderHandler.sendToZero.selector;
        selectors[6] = OpenHolderHandler.approveZero.selector;
        selectors[7] = OpenHolderHandler.privilegedAttempt.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    function invariant_SupplyIsFixed() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), token.INITIAL_SUPPLY());
    }

    /// forge-config: default.invariant.runs = 256
    function invariant_EveryHolderMatchesModelAndHoldingsSumToSupply() public view {
        uint256 n = handler.holderCount();
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            address h = handler.holders(i);
            uint256 b = token.balanceOf(h);
            assertEq(b, handler.ghostBalance(h));
            sum += b;
        }
        assertEq(sum, SUPPLY, "tokens exist outside the tracked holders");
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    function invariant_AllowancesMatchModel() public view {
        uint256 n = handler.holderCount();
        for (uint256 i; i < n; ++i) {
            address owner = handler.holders(i);
            for (uint256 j; j < n; ++j) {
                address spender = handler.holders(j);
                assertEq(token.allowance(owner, spender), handler.ghostAllowance(owner, spender));
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    function invariant_TokenHoldsNoEtherAndMetadataIsStable() public view {
        assertEq(address(token).balance, 0);
        assertEq(token.decimals(), 18);
        assertEq(token.name(), "TheImdDaily");
        assertEq(token.symbol(), "TID");
    }
}
