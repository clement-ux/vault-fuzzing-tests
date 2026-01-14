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
contract FuzzerFoundry is Properties {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual override {
        super.setUp();

        // --- Setup Fuzzer target ---
        // Setup target
        targetContract(address(this));

        // Add selectors

        bytes4[] memory selectors = new bytes4[](18);
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

        // Strategy interaction handlers
        selectors[9] = this.handlerAllocate.selector;
        selectors[10] = this.handlerRebase.selector;
        selectors[11] = this.handlerDepositToStrategy.selector;
        selectors[12] = this.handlerWithdrawFromStrategy.selector;
        selectors[13] = this.handlerWithdrawAllFromStrategy.selector;
        selectors[14] = this.handlerWithdrawAllFromStrategies.selector;
        selectors[15] = this.handlerSimulateYieldOnVault.selector;
        selectors[16] = this.handlerSimulateYieldOnStrategy.selector;

        // Time manipulation handler
        selectors[17] = this.handlerTimeJump.selector;

        // Target selectors
        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
        targetSender(makeAddr("FuzzerSender"));
    }

    function invariantA() public view {}
}
