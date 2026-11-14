// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {WalletGas} from "./properties/WalletGas.sol";
import {TheImdDaily} from "../src/TheImdDaily.sol";

/// @notice TheImdDaily neither reads `gasleft()`, forwards a fixed amount of gas nor catches a failed
/// call, so every state-changing entry point a person or bot sends must behave identically at the
/// gas `eth_estimateGas` returns (no margin) and with gas to spare. These pin that down for each
/// such entry point, from the states a wallet actually meets: fresh recipients, existing
/// recipients, emptying a balance, finite and infinite allowances.
contract TheImdDailyWalletGasTest is WalletGas {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    TheImdDaily private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        token = new TheImdDaily();
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        assertTrue(token.transfer(alice, 1_000e18));
    }

    function test_TransferToFreshRecipientAtWalletGas() public {
        assertSameAtWalletGas(alice, address(token), abi.encodeCall(token.transfer, (bob, 1e18)));
    }

    function test_TransferToExistingHolderAtWalletGas() public {
        assertTrue(token.transfer(bob, 1));
        assertSameAtWalletGas(alice, address(token), abi.encodeCall(token.transfer, (bob, 1e18)));
    }

    function test_TransferWholeBalanceAtWalletGas() public {
        assertSameAtWalletGas(
            alice, address(token), abi.encodeCall(token.transfer, (bob, 1_000e18))
        );
    }

    function test_TransferEntireSupplyFromDeployerAtWalletGas() public {
        uint256 held = token.balanceOf(address(this));
        assertSameAtWalletGas(
            address(this), address(token), abi.encodeCall(token.transfer, (bob, held))
        );
    }

    function test_ZeroTransferAtWalletGas() public {
        assertSameAtWalletGas(bob, address(token), abi.encodeCall(token.transfer, (alice, 0)));
    }

    function test_ApproveAtWalletGas() public {
        assertSameAtWalletGas(alice, address(token), abi.encodeCall(token.approve, (spender, 5e18)));
    }

    function test_ApproveInfiniteAtWalletGas() public {
        assertSameAtWalletGas(
            alice, address(token), abi.encodeCall(token.approve, (spender, type(uint256).max))
        );
    }

    function test_RevokeApprovalAtWalletGas() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 5e18));
        // Clearing a slot earns a refund, so the estimate exceeds what the call finally uses.
        assertSameAtWalletGas(alice, address(token), abi.encodeCall(token.approve, (spender, 0)));
    }

    function test_TransferFromFiniteAllowanceAtWalletGas() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 10e18));
        assertSameAtWalletGas(
            spender, address(token), abi.encodeCall(token.transferFrom, (alice, bob, 4e18))
        );
    }

    function test_TransferFromExhaustingAllowanceAtWalletGas() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 10e18));
        assertSameAtWalletGas(
            spender, address(token), abi.encodeCall(token.transferFrom, (alice, bob, 10e18))
        );
    }

    function test_TransferFromInfiniteAllowanceAtWalletGas() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        assertSameAtWalletGas(
            spender, address(token), abi.encodeCall(token.transferFrom, (alice, bob, 1_000e18))
        );
    }

    /// @dev The check leaves nothing changed, so the real call afterwards still does its work.
    function test_CheckLeavesStateUnchanged() public {
        assertSameAtWalletGas(alice, address(token), abi.encodeCall(token.transfer, (bob, 1e18)));
        assertEq(token.balanceOf(alice), 1_000e18);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
