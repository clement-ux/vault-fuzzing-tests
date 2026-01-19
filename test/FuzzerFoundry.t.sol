// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.31;

// Test
import {Properties} from "test/Properties.t.sol";

/// @title FuzzerFoundry
/// @notice Concrete fuzzing contract implementing Foundry's invariant testing framework.
/// @dev    This contract configures and executes property-based testing:
///         - Inherits from Properties to access handler functions and properties
///         - Configures fuzzer targeting (contracts, selectors, senders)
///         - Implements invariant test functions that call property validators
///         - Each invariant function represents a critical system property to maintain
///         - Fuzzer will call targeted handlers randomly and check invariants after each call
///
///         Invariants are split into separate functions for Foundry parallelization:
///         - invariant_core_*           : Core system invariants
///         - invariant_withdrawalQueue_*: Withdrawal queue invariants
///         - invariant_rebase_*         : Rebase mechanism invariants
///         - invariant_config_*         : Configuration bounds invariants
///         - invariant_solvency_*       : Solvency and accounting invariants
contract FuzzerFoundry is Properties {
    // ╔══════════════════════════════════════════════════════════════════════════════════════════╗
    // ║                                        SETUP                                             ║
    // ╚══════════════════════════════════════════════════════════════════════════════════════════╝

    function setUp() public virtual override {
        super.setUp();

        // --- Setup Fuzzer target ---
        targetContract(address(this));

        // Add selectors
        bytes4[] memory selectors = new bytes4[](22);

        // Setter handlers
        selectors[0] = this.handlerSetAutoAllocateThreshold.selector;
        selectors[1] = this.handlerSetDripDuration.selector;
        selectors[2] = this.handlerSetMaxSupplyDiff.selector;
        selectors[3] = this.handlerSetRebaseRateMax.selector;
        selectors[4] = this.handlerSetTrusteeFeeBps.selector;
        selectors[5] = this.handlerSetRebaseThreshold.selector;
        selectors[6] = this.handlerSetVaultBuffer.selector;
        selectors[7] = this.handlerSetWithdrawalClaimDelay.selector;

        // Mint & Redeem handlers
        selectors[8] = this.handlerMint.selector;
        selectors[9] = this.handlerRequestWithdrawal.selector;
        selectors[10] = this.handlerClaimWithdrawal.selector;
        selectors[11] = this.handlerClaimWithdrawals.selector;
        selectors[12] = this.handlerAddWithdrawalQueueLiquidity.selector;

        // Strategy interaction handlers
        selectors[13] = this.handlerAllocate.selector;
        selectors[14] = this.handlerRebase.selector;
        selectors[15] = this.handlerDepositToStrategy.selector;
        selectors[16] = this.handlerWithdrawFromStrategy.selector;
        selectors[17] = this.handlerWithdrawAllFromStrategy.selector;
        selectors[18] = this.handlerWithdrawAllFromStrategies.selector;
        selectors[19] = this.handlerSimulateYieldOnVault.selector;
        selectors[20] = this.handlerSimulateYieldOnStrategy.selector;

        // Time manipulation handler
        selectors[21] = this.handlerTimeJump.selector;

        // Target selectors
        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
        targetSender(makeAddr("FuzzerSender"));
    }

    // ╔══════════════════════════════════════════════════════════════════════════════════════════╗
    // ║                                  CORE INVARIANTS                                         ║
    // ╚══════════════════════════════════════════════════════════════════════════════════════════╝

    /// @notice OUSD total supply should never exceed vault's total value
    function invariant_core_totalSupplyLteVaultValue() public view {
        assertTrue(propertyTotalSupplyLessThanOrEqualToVaultValue());
    }

    /// @notice All OUSD should be accounted for across known addresses
    function invariant_core_totalSharesAccountedFor() public view {
        assertTrue(propertyTotalSharesEqualsUserSharesPlusDeadShares());
    }

    // ╔══════════════════════════════════════════════════════════════════════════════════════════╗
    // ║                            WITHDRAWAL QUEUE INVARIANTS                                   ║
    // ╚══════════════════════════════════════════════════════════════════════════════════════════╝

    /// @notice Withdrawal queue metadata ordering: claimed <= claimable <= queued
    function invariant_withdrawalQueue_metadataOrdering() public view {
        assertTrue(propertyClaimedLessThanOrEqualToClaimableAndLessThanOrEqualToQueued());
    }

    /// @notice Individual request queued amounts should not exceed total queued
    function invariant_withdrawalQueue_requestQueuedBounds() public view {
        assertTrue(propertyWithdrawalRequestsQueuedLessThanOrEqualToMetadataQueued());
    }

    /// @notice All withdrawal request indices should have valid withdrawers
    function invariant_withdrawalQueue_indexConsistency() public view {
        assertTrue(propertyNextWithdrawalIndexConsistent());
    }

    /// @notice Withdrawal requests should be monotonically increasing
    function invariant_withdrawalQueue_monotonicallyIncreasing() public view {
        assertTrue(propertyWithdrawalRequestsQueuedMonotonicallyIncreasing());
    }

    /// @notice Vault should have enough assets for claimable withdrawals
    function invariant_withdrawalQueue_sufficientLiquidity() public view {
        assertTrue(propertyVaultHasEnoughAssetForClaimableWithdrawals());
    }

    // ╔══════════════════════════════════════════════════════════════════════════════════════════╗
    // ║                                 REBASE INVARIANTS                                        ║
    // ╚══════════════════════════════════════════════════════════════════════════════════════════╝

    /// @notice lastRebase timestamp should never be in the future
    function invariant_rebase_timestampNotInFuture() public view {
        assertTrue(propertyLastRebaseNotInFuture());
    }

    // ╔══════════════════════════════════════════════════════════════════════════════════════════╗
    // ║                           CONFIGURATION BOUNDS INVARIANTS                                ║
    // ╚══════════════════════════════════════════════════════════════════════════════════════════╝

    /// @notice Vault buffer should never exceed 100%
    function invariant_config_vaultBufferBounds() public view {
        assertTrue(propertyVaultBufferNotExceed100Percent());
    }

    /// @notice Max supply diff should be within reasonable bounds
    function invariant_config_maxSupplyDiffBounds() public view {
        assertTrue(propertyMaxSupplyDiffReasonable());
    }

    /// @notice Trustee fee should never exceed 50%
    function invariant_config_trusteeFeeBounds() public view {
        assertTrue(propertyTrusteeFeeBpsNotExceed50Percent());
    }

    // ╔══════════════════════════════════════════════════════════════════════════════════════════╗
    // ║                                SOLVENCY INVARIANTS                                       ║
    // ╚══════════════════════════════════════════════════════════════════════════════════════════╝

    /// @notice Vault should always be solvent (assets >= liabilities)
    function invariant_solvency_vaultIsSolvent() public view {
        assertTrue(propertyVaultIsSolvent());
    }

    /// @notice Total value should be correctly calculated from underlying balances
    function invariant_solvency_totalValueConsistency() public view {
        assertTrue(propertyTotalValueConsistency());
    }

    /// @notice Decimal scaling between USDC and OUSD should be correct
    function invariant_solvency_decimalScaling() public view {
        assertTrue(propertyCorrectDecimalScaling());
    }
}
