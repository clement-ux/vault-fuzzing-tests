// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.31;

// Foundry
import {console} from "@forge-std/console.sol";

// Library
import {Logger} from "src/Logger.sol";

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
    // [x] mint
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
    // [x] setAutoAllocateThreshold
    // [x] setDripDuration
    // [x] setMaxSupplyDiff
    // [x] setRebaseRateMax
    // [x] setRebaseThreshold
    // [x] setTrusteeFeeBps
    // [x] setVaultBuffer
    // [x] setWithdrawalClaimDelay

    using Logger for uint48;
    using Logger for uint64;
    using Logger for uint256;

    ////////////////////////////////////////////////////
    /// --- Mint & Redeem Handlers
    ////////////////////////////////////////////////////
    /// @notice Handler for mint function
    /// @param amount The amount to mint
    /// @param random A random value for fuzzing random user
    /// @dev amount is uint48 because it can represent up to ~281m with 6 decimals (USDC)
    function handlerMint(uint48 amount, uint8 random) public {
        // Ensure amount is greater than 0 (restricted by vault)
        vm.assume(amount > 0);

        // Select random user
        address user = users[random % users.length];

        // Mint USDC to user
        usdc.mint(user, amount);

        // Cache balance before
        uint256 balanceBefore = ousd.balanceOf(user);

        // Prank as user and mint OUSD
        vm.prank(user);
        vault.mint(amount);

        // Cache balance after;
        uint256 ousdMinted = ousd.balanceOf(user) - balanceBefore;

        // Log mint info
        if (!ENABLE_LOGS) return;
        console.log(
            string(
                abi.encodePacked(
                    "> ",
                    vm.getLabel(user),
                    "   ",
                    " -> mint():                        ",
                    ousdMinted.decimals(18, true, true),
                    " OUSD with ",
                    amount.decimals(6, true, true),
                    " USDC"
                )
            )
        );
    }

    ////////////////////////////////////////////////////
    /// --- Setters Handlers
    ////////////////////////////////////////////////////
    /// @notice Handler for setAutoAllocateThreshold function
    /// @param exponent The auto allocate threshold value
    /// @dev This function can only be called by governor, thus parameters range can be less randomized.
    ///      In the current setup, 25_000 OUSD is used.
    ///      For the test, the range will be 0 -> 100m OUSD, by orders of magnitude (0-8).
    ///      Using 9 to represent 0 (disabled)
    function handlerSetAutoAllocateThreshold(uint8 exponent) public {
        // Bound the parameter to valid range
        exponent = uint8(_bound(exponent, 0, 9));

        uint256 threshold = exponent == 9 ? 0 : 10 ** exponent * 1e18;
        // Prank as governor and set exponent
        vm.prank(governor);
        vault.setAutoAllocateThreshold(threshold);

        // Log set info
        if (!ENABLE_LOGS) return;
        console.log(
            string(
                abi.encodePacked(
                    "> ",
                    vm.getLabel(governor),
                    " -> setAutoAllocateThreshold():    ",
                    threshold.decimals(18, true, true),
                    " USDC"
                )
            )
        );
    }

    /// @notice Handler for setDripDuration function
    /// @param dripDuration The drip duration value (in days)
    /// @dev This function can only be called by operator, which cannot be fully trusted.
    ///      Thus, the parameter is fully randomized
    function handlerSetDripDuration(uint64 dripDuration) public {
        // Prank as operator and set drip duration
        vm.prank(operator);
        vault.setDripDuration(dripDuration);

        // Log set info
        if (!ENABLE_LOGS) return; // forgefmt: disable-start
        console.log(
            string(
                abi.encodePacked(
                    "> ",
                    vm.getLabel(operator),
                    " -> setDripDuration():             ",
                    dripDuration.formatTime()
                )
            )
        );
        // forgefmt: disable-end
    }

    /// @notice Handler for setMaxSupplyDiff function
    /// @param maxSupplyDiffPct The max supply diff percentage.
    /// @dev This function can only be called by governor, thus parameters range can be less randomized.
    ///      In the current setup, 5% is used.
    ///      For the test, the range will be 2 -> 10%
    function handlerSetMaxSupplyDiff(uint8 maxSupplyDiffPct) public {
        // Bound the parameter to valid range
        maxSupplyDiffPct = uint8(_bound(maxSupplyDiffPct, 2, 10));

        // Prank as governor and set max supply diff
        vm.prank(governor);
        vault.setMaxSupplyDiff(uint256(maxSupplyDiffPct) * 1e16);

        // Log set info
        if (!ENABLE_LOGS) return;
        console.log(
            string(
                abi.encodePacked(
                    "> ",
                    vm.getLabel(governor),
                    " -> setMaxSupplyDiff():            ",
                    uint256(maxSupplyDiffPct).decimals(0, true, true),
                    " %"
                )
            )
        );
    }

    /// @notice Handler for setRebaseRateMax function
    /// @param yearlyApr The rebase rate max value.
    /// @dev This function can only be called by operator, which cannot be fully trusted.
    ///      Thus, the parameter is fully randomized.
    ///      Maximum value is determined by yearlyApr/100/365 days <= 0.05 ether / 1 days
    ///                                  -> yearlyApr <= 18.25 ether
    ///      Minimum value is 0, but due to div, using 1 or 10 will be equivalent -> 0.
    ///      To not use too many useless calls,using 365 days * 100 - 1 = 3153599999 as minimum.
    ///      Using uint64 as this is the smallest type that can contain the max value.
    function handlerSetRebaseRateMax(uint64 yearlyApr) public {
        // Bound the parameter to valid range
        yearlyApr = uint64(_bound(yearlyApr, 3153599999, 18.25 ether));

        // Prank as operator and set rebase rate max
        vm.prank(operator);
        vault.setRebaseRateMax(yearlyApr);

        // Log set info
        if (!ENABLE_LOGS) return;
        console.log(
            string(
                abi.encodePacked(
                    "> ",
                    vm.getLabel(operator),
                    " -> setRebaseRateMax():            ",
                    yearlyApr.decimals(18, true, true),
                    " % APR, ",
                    (yearlyApr / 100 / 365 days).decimals(0, true, true),
                    " per second"
                )
            )
        );
    }

    /// @notice Handler for setRebaseThreshold function
    /// @param exponent The exponent to determine the rebase threshold value 1 * 10 ** (18 + exponent)
    /// @dev This function can only be called by governor, thus parameters range can be less randomized.
    ///      In the current setup, 1_000 ETH is used.
    ///      For the test, the range will be 0 -> 100m ETH, only 10 multiples of exponent (0-8).
    ///      Using 9 to represent 0 (disabled)
    function handlerSetRebaseThreshold(uint8 exponent) public {
        // Bound the parameter to valid range
        exponent = uint8(_bound(exponent, 0, 8));

        uint256 threshold = exponent == 9 ? 0 : 10 ** exponent * 1e18;

        // Prank as governor and set rebase threshold
        vm.prank(governor);
        vault.setRebaseThreshold(threshold);

        // Log set info
        if (!ENABLE_LOGS) return;
        console.log(
            string(
                abi.encodePacked(
                    "> ",
                    vm.getLabel(governor),
                    " -> setRebaseThreshold():          ",
                    threshold.decimals(18, true, true),
                    " OUSD"
                )
            )
        );
    }

    /// @notice Handler for setTrusteeFeeBps function
    /// @param trusteeFeeBps The trustee fee in basis points
    /// @dev This function can only be called by governor, thus parameters range can be less randomized.
    ///      In the current setup, 50 bps is used.
    ///      For the test, the range will be 0 -> 50% (only using round values)
    function handlerSetTrusteeFeeBps(uint8 trusteeFeeBps) public {
        // Bound the parameter to valid range
        trusteeFeeBps = uint8(_bound(trusteeFeeBps, 0, 50));

        // Prank as governor and set trustee fee bps
        vm.prank(governor);
        vault.setTrusteeFeeBps(uint256(trusteeFeeBps) * 100);

        // Log set info
        if (!ENABLE_LOGS) return;
        console.log(
            string(
                abi.encodePacked(
                    "> ",
                    vm.getLabel(governor),
                    " -> setTrusteeFeeBps():            ",
                    uint256(trusteeFeeBps).decimals(0, true, true),
                    " %"
                )
            )
        );
    }

    /// @notice Handler for setVaultBuffer function
    /// @param vaultBuffer The vault buffer value (0-100%)
    /// @dev This function can be called by operator, which cannot be fully trusted.
    ///      Thus, the parameter is fully randomized.
    function handlerSetVaultBuffer(uint64 vaultBuffer) public {
        // Bound the parameter to valid range
        vaultBuffer = uint64(_bound(vaultBuffer, 0, 1 ether));

        // Prank as operator and set vault buffer
        vm.prank(operator);
        vault.setVaultBuffer(vaultBuffer);

        // Log set info
        if (!ENABLE_LOGS) return;
        console.log(
            string(
                abi.encodePacked(
                    "> ",
                    vm.getLabel(operator),
                    " -> setVaultBuffer():              ",
                    vaultBuffer.decimals(16, true, true),
                    " %"
                )
            )
        );
    }

    /// @notice Handler for setWithdrawalClaimDelay function
    /// @param withdrawalClaimDelay The withdrawal claim delay value (in seconds)
    function handlerSetWithdrawalClaimDelay(uint24 withdrawalClaimDelay) public {
        // Bound the parameter to valid range
        withdrawalClaimDelay = uint24(_bound(withdrawalClaimDelay, 10 minutes, 15 days));

        // Prank as governor and set withdrawal claim delay
        vm.prank(governor);
        vault.setWithdrawalClaimDelay(withdrawalClaimDelay);

        // Log set info
        if (!ENABLE_LOGS) return;
        console.log(
            string(
                abi.encodePacked(
                    "> ",
                    vm.getLabel(governor),
                    " -> setWithdrawalClaimDelay():     ",
                    uint256(withdrawalClaimDelay).formatTime()
                )
            )
        );
    }
}
