// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.31;

import {OUSDVault} from "@origin-dollar/vault/OUSDVault.sol";

// Test
import {TargetFunctions} from "test/TargetFunctions.t.sol";

import {Math} from "src/Math.sol";
import {Getter} from "src/Getter.sol";

/// @title Properties
/// @notice Abstract contract defining invariant properties for formal verification and fuzzing.
/// @dev    This contract contains pure property functions that express system invariants:
///         - Properties must be implemented as view/pure functions returning bool
///         - Each property should represent a mathematical invariant of the system
///         - Properties should be stateless and deterministic
///         - Property names should clearly indicate what invariant they check
///         Usage: Properties are called by fuzzing contracts to validate system state
abstract contract Properties is TargetFunctions {
    // ╔══════════════════════════════════════════════════════════════════════╗
    // ║                          ✦✦✦ PROPERTIES ✦✦✦                          ║
    // ╚══════════════════════════════════════════════════════════════════════╝
    //
    // Invariant: ousd.totalSupply() <= vault.totalValue()
    // Invariant: withdrawalQueueMetadata.claimed <= withdrawalQueueMetadata.claimable
    // Invariant: withdrawalQueueMetadata.claimable <= withdrawalQueueMetadata.queued
    // Invariant: ∀ withdrawalRequests, withdrawalRequests[i].queued <= withdrawalQueueMetadata.queued
    // Invariant: ∑shares > 0 due to initial deposit
    // Invariant: totalShares == ∑userShares + deadShares

    using Getter for OUSDVault;

    function propertyTotalSupplyLessThanOrEqualToVaultValue() public view returns (bool) {
        return ousd.totalSupply() <= vault.totalValue();
    }

    function propertyClaimedLessThanOrEqualToClaimableAndLessThanOrEqualToQueued() public view returns (bool) {
        (uint128 queued, uint128 claimable, uint128 claimed,) = vault.withdrawalQueueMetadata();
        return claimed <= claimable && claimable <= queued;
    }

    function propertyWithdrawalRequestsQueuedLessThanOrEqualToMetadataQueued() public view returns (bool) {
        (uint128 queued,,, uint128 lastIndex) = vault.withdrawalQueueMetadata();
        if (lastIndex == 0) return true;

        for (uint256 i; i <= lastIndex; i++) {
            (,,,, uint128 requestQueued) = vault.withdrawalRequests(i);
            if (requestQueued > queued) {
                return false;
            }
        }
        return true;
    }

    function propertyTotalSharesEqualsUserSharesPlusDeadShares() public view returns (bool) {
        uint256 sumOfOUSD;
        for (uint256 i; i < users.length; i++) {
            sumOfOUSD += ousd.balanceOf(users[i]);
        }
        sumOfOUSD += ousd.balanceOf(dead);
        sumOfOUSD += ousd.balanceOf(treasury);
        sumOfOUSD += ousd.balanceOf(address(strategyAMO));
        return Math.approxEqAbs(ousd.totalSupply(), sumOfOUSD, 10);
    }
}
