// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.31;

// Test imports
import {Setup} from "test/Setup.t.sol";

/// @title TargetFunctions
/// @notice TargetFunctions contract for tests, containing the target functions that should be tested.
///         This is the entry point with the contract we are testing. Ideally, it should never revert.
abstract contract TargetFunctions is Setup {
    // ╔══════════════════════════════════════════════════════════════════════════════╗
    // ║                           ✦✦✦ TARGET FUNCTIONS ✦✦✦                           ║
    // ╚══════════════════════════════════════════════════════════════════════════════╝
    // --- Mint & Redeem
    // [ ] mint
    // [ ] requestWithdrawal
    // [ ] claimWithdrawals
    // [ ] claimWithdrawal
    // [ ] addWithdrawalQueueLiquidity
    //
    // --- Liquidity Management
    // [ ] rebase
    // [ ] allocate
    // [ ] depositToStrategy
    // [ ] withdrawAllFromStrategy
    // [ ] withdrawAllFromStrategies
    // [ ] withdrawFromStrategy
    //
    // --- Setters
    // [ ] setAutoAllocateThreshold
    // [ ] setDripDuration
    // [ ] setMaxSupplyDiff
    // [ ] setRebaseRateMax
    // [ ] setRebaseThreshold
    // [ ] setTrusteeFeeBps
    // [ ] setVaultBuffer
    // [ ] setWithdrawalClaimDelay

    }
