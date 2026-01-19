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
    using Getter for OUSDVault;

    // ╔══════════════════════════════════════════════════════════════════════════════════════════╗
    // ║                                  ✦✦✦ PROPERTIES ✦✦✦                                      ║
    // ╠══════════════════════════════════════════════════════════════════════════════════════════╣
    // ║                                                                                          ║
    // ║  CORE INVARIANTS                                                                         ║
    // ║  ├─ ousd.totalSupply() <= vault.totalValue()                                             ║
    // ║  └─ totalSupply == ∑userBalances + deadBalances                                          ║
    // ║                                                                                          ║
    // ║  WITHDRAWAL QUEUE INVARIANTS                                                             ║
    // ║  ├─ claimed <= claimable <= queued                                                       ║
    // ║  ├─ ∀ requests[i].queued <= metadata.queued                                              ║
    // ║  ├─ ∀ i < nextIndex, requests[i].withdrawer != address(0)                                ║
    // ║  ├─ requests[i].queued >= requests[i-1].queued (monotonic)                               ║
    // ║  └─ vault.assetBalance >= claimable - claimed                                            ║
    // ║                                                                                          ║
    // ║  REBASE INVARIANTS                                                                       ║
    // ║  └─ lastRebase <= block.timestamp                                                        ║
    // ║                                                                                          ║
    // ║  CONFIGURATION BOUNDS INVARIANTS                                                         ║
    // ║  ├─ vaultBuffer <= 1e18 (100%)                                                           ║
    // ║  ├─ maxSupplyDiff <= 1e18 (100%)                                                         ║
    // ║  └─ trusteeFeeBps <= 5000 (50%)                                                          ║
    // ║                                                                                          ║
    // ║  SOLVENCY INVARIANTS                                                                     ║
    // ║  ├─ totalAssets * 1e12 >= totalSupply (vault is solvent)                                 ║
    // ║  └─ totalValue == (vaultBalance + strategyBalances - withdrawals) * 1e12                 ║
    // ║                                                                                          ║
    // ╚══════════════════════════════════════════════════════════════════════════════════════════╝

    // ╔══════════════════════════════════════════════════════════════════════════════════════════╗
    // ║                                   CORE INVARIANTS                                        ║
    // ╚══════════════════════════════════════════════════════════════════════════════════════════╝

    /// @notice Ensures OUSD total supply never exceeds the vault's total value
    /// @dev This is the fundamental solvency check - users should always be able to redeem
    function propertyTotalSupplyLessThanOrEqualToVaultValue() public view returns (bool) {
        return ousd.totalSupply() <= vault.totalValue();
    }

    /// @notice Ensures all OUSD is accounted for across known addresses
    /// @dev Sum of all user balances + dead + treasury + strategy should equal total supply
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

    // ╔══════════════════════════════════════════════════════════════════════════════════════════╗
    // ║                              WITHDRAWAL QUEUE INVARIANTS                                 ║
    // ╚══════════════════════════════════════════════════════════════════════════════════════════╝

    /// @notice Ensures withdrawal queue metadata maintains proper ordering
    /// @dev claimed <= claimable <= queued must always hold
    function propertyClaimedLessThanOrEqualToClaimableAndLessThanOrEqualToQueued() public view returns (bool) {
        (uint128 queued, uint128 claimable, uint128 claimed,) = vault.withdrawalQueueMetadata();
        return claimed <= claimable && claimable <= queued;
    }

    /// @notice Ensures individual request queued amounts don't exceed total queued
    /// @dev Each request's cumulative queued value should be <= metadata's total queued
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

    /// @notice Ensures all withdrawal request indices have valid withdrawers
    /// @dev No gaps should exist in the withdrawal request mapping
    function propertyNextWithdrawalIndexConsistent() public view returns (bool) {
        (,,, uint128 nextIndex) = vault.withdrawalQueueMetadata();
        for (uint256 i; i < nextIndex; i++) {
            (address withdrawer,,,,) = vault.withdrawalRequests(i);
            if (withdrawer == address(0)) return false;
        }
        return true;
    }

    /// @notice Ensures withdrawal requests are monotonically increasing
    /// @dev Each request's queued amount should be >= the previous request's queued amount
    function propertyWithdrawalRequestsQueuedMonotonicallyIncreasing() public view returns (bool) {
        (,,, uint128 lastIndex) = vault.withdrawalQueueMetadata();
        if (lastIndex <= 1) return true;

        uint128 prevQueued;
        for (uint256 i; i < lastIndex; i++) {
            (,,,, uint128 requestQueued) = vault.withdrawalRequests(i);
            if (i > 0 && requestQueued < prevQueued) return false;
            prevQueued = requestQueued;
        }
        return true;
    }

    /// @notice Ensures vault has enough assets to cover claimable withdrawals
    /// @dev Vault's asset balance must be >= outstanding claimable amount
    function propertyVaultHasEnoughAssetForClaimableWithdrawals() public view returns (bool) {
        (uint128 queued, uint128 claimable, uint128 claimed,) = vault.withdrawalQueueMetadata();
        uint256 outstandingClaimable = claimable - claimed;
        uint256 vaultAssetBalance = usdc.balanceOf(address(vault));
        return vaultAssetBalance >= outstandingClaimable;
    }

    // ╔══════════════════════════════════════════════════════════════════════════════════════════╗
    // ║                                  REBASE INVARIANTS                                       ║
    // ╚══════════════════════════════════════════════════════════════════════════════════════════╝

    /// @notice Ensures lastRebase timestamp is never in the future
    /// @dev Prevents time manipulation attacks on rebase calculations
    function propertyLastRebaseNotInFuture() public view returns (bool) {
        return vault.lastRebase() <= block.timestamp;
    }

    // ╔══════════════════════════════════════════════════════════════════════════════════════════╗
    // ║                            CONFIGURATION BOUNDS INVARIANTS                               ║
    // ╚══════════════════════════════════════════════════════════════════════════════════════════╝

    /// @notice Ensures vault buffer percentage never exceeds 100%
    /// @dev Buffer is in 1e18 notation, so max is 1e18
    function propertyVaultBufferNotExceed100Percent() public view returns (bool) {
        return vault.vaultBuffer() <= 1e18;
    }

    /// @notice Ensures max supply diff is within reasonable bounds
    /// @dev Prevents configuration that would allow extreme supply/value divergence
    function propertyMaxSupplyDiffReasonable() public view returns (bool) {
        return vault.maxSupplyDiff() <= 1e18;
    }

    /// @notice Ensures trustee fee never exceeds 50%
    /// @dev Protects users from excessive fee extraction
    function propertyTrusteeFeeBpsNotExceed50Percent() public view returns (bool) {
        return vault.trusteeFeeBps() <= 5000;
    }

    // ╔══════════════════════════════════════════════════════════════════════════════════════════╗
    // ║                                 SOLVENCY INVARIANTS                                      ║
    // ╚══════════════════════════════════════════════════════════════════════════════════════════╝

    /// @notice Ensures the vault is always solvent (assets >= liabilities)
    /// @dev Total assets (scaled to 18 decimals) must cover total OUSD supply
    function propertyVaultIsSolvent() public view returns (bool) {
        uint256 totalAssets = vault.checkBalance(address(usdc));
        uint256 totalAssetsScaled = totalAssets * 1e12; // Scale USDC (6 decimals) to 18 decimals
        uint256 totalLiabilities = ousd.totalSupply();

        // Allow small rounding tolerance
        return totalAssetsScaled + 100 >= totalLiabilities;
    }

    /// @notice Ensures total value is correctly calculated from underlying balances
    /// @dev totalValue = (vaultBalance + strategyBalances - outstandingWithdrawals) * 1e12
    function propertyTotalValueConsistency() public view returns (bool) {
        uint256 vaultBalance = usdc.balanceOf(address(vault));
        uint256 strategyBalances;
        for (uint256 i; i < strategies.length; i++) {
            strategyBalances += usdc.balanceOf(strategies[i]);
        }

        (uint128 queued,, uint128 claimed,) = vault.withdrawalQueueMetadata();
        uint256 outstandingWithdrawals = queued - claimed;

        // Scale to 18 decimals for comparison with totalValue
        uint256 expectedValue = (vaultBalance + strategyBalances - outstandingWithdrawals) * 1e12;
        uint256 actualValue = vault.totalValue();

        return Math.approxEqAbs(expectedValue, actualValue, 10);
    }

    /// @notice Ensures decimal scaling between USDC and OUSD is correct
    /// @dev 1e6 USDC should always equal 1e18 OUSD in value terms
    function propertyCorrectDecimalScaling() public view returns (bool) {
        uint256 rawBalance = usdc.balanceOf(address(vault));
        for (uint256 i; i < strategies.length; i++) {
            rawBalance += usdc.balanceOf(strategies[i]);
        }

        (uint128 queued,, uint128 claimed,) = vault.withdrawalQueueMetadata();
        if (rawBalance + claimed < queued) return true; // Edge case handled in contract

        uint256 expectedValue = (rawBalance + claimed - queued) * 1e12;
        return Math.approxEqAbs(vault.totalValue(), expectedValue, 1e12);
    }
}
