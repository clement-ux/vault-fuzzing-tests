// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.31;

// Foundry
import {console} from "@forge-std/console.sol";

// Origin Dollar
import {OUSDVault} from "@origin-dollar/vault/OUSDVault.sol";

// Library
import {Logger} from "src/Logger.sol";
import {Getter} from "src/Getter.sol";

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
    // [x] requestWithdrawal
    // [x] claimWithdrawals
    // [x] claimWithdrawal
    // [ ] addWithdrawalQueueLiquidity
    //
    // --- Liquidity Management
    // [x] rebase
    // [x] allocate
    // [x] depositToStrategy
    // [x] withdrawAllFromStrategy
    // [x] withdrawAllFromStrategies
    // [x] withdrawFromStrategy
    // [x] simulateYieldOnStrategy
    // [x] simulateYieldOnVault
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
    //
    // --- Time Manipulation
    // [x] timeJump

    using Logger for uint24;
    using Logger for uint48;
    using Logger for uint64;
    using Logger for uint96;
    using Logger for uint256;
    using Logger for uint256[];
    using Getter for OUSDVault;

    ////////////////////////////////////////////////////
    /// --- Mint & Redeem Handlers
    ////////////////////////////////////////////////////
    /// @notice Handler for mint function
    /// @param amount The amount to mint
    /// @param random A random value for fuzzing random user
    /// @dev amount is uint48 because it can represent up to ~281m with 6 decimals (USDC)
    function handlerMint(uint48 amount, uint8 random) public {
        // Ensure amount is greater than 0 (restricted by vault)
        amount = uint48(_bound(amount, 1, type(uint48).max));

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
                    " OUSD"
                )
            )
        );
    }

    /// @notice Handler for requestWithdrawal function
    /// @param amount The amount to request withdrawal
    /// @param random A random value for fuzzing random user
    /// @dev amount is uint56 because it can represent up to ~79b with 18 decimals (OUSD)
    function handlerRequestWithdrawal(uint96 amount, uint8 random) public {
        // Ensure async withdrawals are enabled
        vm.assume(vault.withdrawalClaimDelay() > 0);

        address user;
        uint256 userOusdBalance;
        uint256 len = users.length;
        // Select random user that has at least 1 wei of OUSD balance, otherwise skip
        for (uint256 i = random; i < random + len; i++) {
            userOusdBalance = ousd.balanceOf(users[i % len]);
            if (userOusdBalance >= 1) {
                user = users[i % len];
                break;
            }
        }

        // Assume we find a valid user
        vm.assume(user != address(0));
        // Bound amount to user's OUSD balance
        amount = uint96(_bound(amount, 1, userOusdBalance));

        // Prank as user and request withdrawal
        vm.prank(user);
        try vault.requestWithdrawal(amount) {}
        catch Error(string memory reason) {
            vm.assume(
                keccak256(abi.encodePacked(reason)) != keccak256(abi.encodePacked("Backing supply liquidity error"))
            );
            revert(reason);
        }
        uint256 index = vault.getLastWithdrawalIndex();
        userToWithdrawalRequestIds[user].push(index);

        // Log request withdrawal info
        if (!ENABLE_LOGS) return;
        // Get index of the last withdrawal request
        console.log(
            string(
                abi.encodePacked(
                    "> ",
                    vm.getLabel(user),
                    "   ",
                    " -> requestWithdrawal():           ",
                    amount.decimals(18, true, true),
                    " OUSD (index: ",
                    index.decimals(0, true, false),
                    ")"
                )
            )
        );
    }

    /// @notice Handler for claimWithdrawal function
    /// @param random A random value for fuzzing random user
    /// @param randomRequest A random value for fuzzing random request index
    function handlerClaimWithdrawal(uint8 random, uint16 randomRequest) public {
        // Ensure async withdrawals are enabled
        uint256 claimDelay = vault.withdrawalClaimDelay();
        vm.assume(claimDelay > 0);
        address user;
        uint256 request;
        uint256 len = users.length;
        // Select random user that has at least 1 pending withdrawal request, otherwise skip
        for (uint256 i = random; i < random + len; i++) {
            uint256 pendingRequests = userToWithdrawalRequestIds[users[i % len]].length;
            if (pendingRequests > 0) {
                user = users[i % len];
                request = userToWithdrawalRequestIds[user][randomRequest % pendingRequests];
                break;
            }
        }

        // Assume we find a valid user
        vm.assume(user != address(0));

        // Timejump to after maturity only if needed
        uint256 requestTimestamp = vault.getRequestTimestamp(request);
        if (block.timestamp < (requestTimestamp + claimDelay)) vm.warp(requestTimestamp + claimDelay);

        uint256 balanceBefore = usdc.balanceOf(user);
        // Prank as user and claim withdrawal
        vm.prank(user);
        try vault.claimWithdrawal(request) {}
        catch Error(string memory reason) {
            vm.assume(
                keccak256(abi.encodePacked(reason)) != keccak256(abi.encodePacked("Backing supply liquidity error"))
            );
            vm.assume(keccak256(abi.encodePacked(reason)) != keccak256(abi.encodePacked("Queue pending liquidity")));
            revert(reason);
        }

        // Remove the request from the user's pending requests
        uint256[] storage requests = userToWithdrawalRequestIds[user];
        for (uint256 i = 0; i < requests.length; i++) {
            if (requests[i] == request) {
                requests[i] = requests[requests.length - 1];
                requests.pop();
                break;
            }
        }

        // Log claim withdrawal info
        if (!ENABLE_LOGS) return;
        uint256 balanceAfter = usdc.balanceOf(user);
        console.log(
            string(
                abi.encodePacked(
                    "> ",
                    vm.getLabel(user),
                    "   ",
                    " -> claimWithdrawal():             ",
                    (balanceAfter - balanceBefore).decimals(6, true, true),
                    " USDC (from request index: ",
                    request.decimals(0, true, false),
                    ")"
                )
            )
        );
    }

    /// @notice Handler for claimWithdrawals function
    /// @param random A random value for fuzzing random user
    /// @param randomRequestCount A random value for fuzzing random number of requests to claim
    function handlerClaimWithdrawals(uint8 random, uint16 randomRequestCount) public {
        // Ensure async withdrawals are enabled
        uint256 claimDelay = vault.withdrawalClaimDelay();
        vm.assume(claimDelay > 0);

        // Select random user that has at least 1 pending withdrawal request, otherwise skip
        address user;
        uint256[] memory requests;
        uint256 len = users.length;
        for (uint256 i = random; i < random + len; i++) {
            uint256 pendingRequests = userToWithdrawalRequestIds[users[i % len]].length;
            if (pendingRequests > 0) {
                user = users[i % len];
                requests = userToWithdrawalRequestIds[user];
                break;
            }
        }

        // Assume we find a valid user
        vm.assume(user != address(0));

        // Build a random list of requests to claim
        uint256 latestRequestTimestamp;
        uint256 claimCount = _bound(randomRequestCount, 1, requests.length);
        uint256[] memory shuffledRequests = vm.shuffle(requests);
        uint256[] memory requestsToClaim = new uint256[](claimCount);
        for (uint256 i = 0; i < claimCount; i++) {
            requestsToClaim[i] = shuffledRequests[i];
            uint256 requestTimestamp = vault.getRequestTimestamp(shuffledRequests[i]);
            if (requestTimestamp > latestRequestTimestamp) latestRequestTimestamp = requestTimestamp;
        }

        // Timejump to after maturity only if needed
        if (block.timestamp < (latestRequestTimestamp + claimDelay)) vm.warp(latestRequestTimestamp + claimDelay);

        uint256 balanceBefore = usdc.balanceOf(user);
        // Prank as user and claim withdrawals
        vm.prank(user);
        try vault.claimWithdrawals(requestsToClaim) {}
        catch Error(string memory reason) {
            vm.assume(
                keccak256(abi.encodePacked(reason)) != keccak256(abi.encodePacked("Backing supply liquidity error"))
            );
            vm.assume(keccak256(abi.encodePacked(reason)) != keccak256(abi.encodePacked("Queue pending liquidity")));
            revert(reason);
        }

        // Remove the requests from the user's pending requests
        uint256[] storage userRequests = userToWithdrawalRequestIds[user];
        for (uint256 i; i < requestsToClaim.length; i++) {
            for (uint256 j; j < userRequests.length; j++) {
                if (userRequests[j] == requestsToClaim[i]) {
                    userRequests[j] = userRequests[userRequests.length - 1];
                    userRequests.pop();
                    break;
                }
            }
        }

        // Log claim withdrawals info
        if (!ENABLE_LOGS) return;
        uint256 balanceAfter = usdc.balanceOf(user);
        console.log(
            string(
                abi.encodePacked(
                    "> ",
                    vm.getLabel(user),
                    "   ",
                    " -> claimWithdrawals():            ",
                    (balanceAfter - balanceBefore).decimals(6, true, true),
                    " USDC (from ",
                    requestsToClaim.uintArrayToString(),
                    " requests)"
                )
            )
        );
    }

    ////////////////////////////////////////////////////
    /// --- Liquidity Management Handlers
    ////////////////////////////////////////////////////
    /// @notice Handler for rebase function
    function handlerRebase() public {
        uint256 supplyBefore = ousd.totalSupply();
        vault.rebase();

        // Log rebase info
        if (!ENABLE_LOGS) return;
        uint256 supplyAfter = ousd.totalSupply();
        uint256 pctChange = supplyAfter > supplyBefore
            ? ((supplyAfter - supplyBefore) * 1e18) / supplyBefore
            : ((supplyBefore - supplyAfter) * 1e18) / supplyBefore;
        string memory sign = supplyAfter >= supplyBefore ? "+" : "-";
        console.log(
            string(
                abi.encodePacked(
                    "> ",
                    "Fuzzer  ",
                    " -> rebase():                      ",
                    supplyBefore.decimals(18, true, true),
                    " OUSD (before) -> ",
                    supplyAfter.decimals(18, true, true),
                    " OUSD (after) +",
                    (supplyAfter - supplyBefore).decimals(18, true, true),
                    " OUSD (",
                    sign,
                    pctChange.decimals(18, true, true),
                    " %)"
                )
            )
        );
    }

    /// @notice Handler for allocate function
    function handlerAllocate() public {
        // Cache strategy balance before
        // Allocate always deposits to default strategy (strategyTrad)
        uint256 strategyBalanceBefore = usdc.balanceOf(address(strategyTrad));

        // Prank as governor and call allocate
        vm.prank(governor);
        vault.allocate();

        // Cache strategy balance after
        uint256 strategyBalanceAfter = usdc.balanceOf(address(strategyTrad));

        // Calculate amount deposited
        uint256 amountDeposited = strategyBalanceAfter - strategyBalanceBefore;

        // Log allocate info
        if (!ENABLE_LOGS) return;
        console.log(
            string(
                abi.encodePacked(
                    "> ",
                    vm.getLabel(governor),
                    " -> allocate():                    ",
                    amountDeposited.decimals(6, true, true),
                    " USDC"
                )
            )
        );
    }

    /// @notice Handler for depositToStrategy function
    /// @param random A random value for fuzzing random strategy
    /// @param amount The amount to deposit
    /// @dev amount is uint256 to allow large deposit amounts
    function handlerDepositToStrategy(uint8 random, uint256 amount) public {
        // Pick a random strategy
        address strategy = strategies[random % strategies.length];

        // Get available asset in the vault
        uint256 availableAsset = vault.availableAsset();

        // Assume there is at least 1 USDC available
        vm.assume(availableAsset >= 1);

        // Bound amount to available asset
        amount = _bound(amount, 1, availableAsset);

        // Prepare deposit parameters
        address[] memory assets = new address[](1);
        assets[0] = address(usdc);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        // Prank as operator and call depositToStrategy
        vm.prank(operator);
        vault.depositToStrategy(strategy, assets, amounts);

        // Log depositToStrategy info
        if (!ENABLE_LOGS) return;
        console.log(
            string(
                abi.encodePacked(
                    "> ",
                    vm.getLabel(operator),
                    " -> depositToStrategy():           ",
                    amount.decimals(6, true, true),
                    " USDC to: ",
                    vm.getLabel(strategy)
                )
            )
        );
    }

    /// @notice Handler for withdrawFromStrategy function
    /// @param random A random value for fuzzing random strategy
    /// @param amount The amount to withdraw
    /// @dev amount is uint256 to allow large withdraw amounts
    function handlerWithdrawFromStrategy(uint8 random, uint256 amount) public {
        address strategy;
        uint256 strategyBalance;
        uint256 len = strategies.length;
        // Select random strategy that has at least 1 USDC balance, otherwise skip
        for (uint256 i = random; i < random + len; i++) {
            if (usdc.balanceOf(strategies[i % len]) >= 1) {
                strategyBalance = usdc.balanceOf(strategies[i % len]);
                strategy = strategies[i % len];
                break;
            }
        }

        // Assume we find a valid strategy
        vm.assume(strategy != address(0));

        // Bound amount to strategy balance
        amount = _bound(amount, 1, strategyBalance);

        address[] memory assets = new address[](1);
        assets[0] = address(usdc);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        // Prank as operator and call withdrawFromStrategy
        vm.prank(operator);
        vault.withdrawFromStrategy(strategy, assets, amounts);

        // Log withdrawFromStrategy info
        if (!ENABLE_LOGS) return;
        console.log(
            string(
                abi.encodePacked(
                    "> ",
                    vm.getLabel(operator),
                    " -> withdrawFromStrategy():        ",
                    amount.decimals(6, true, true),
                    " USDC from: ",
                    vm.getLabel(strategy)
                )
            )
        );
    }

    /// @notice Handler for withdrawAllFromStrategy function
    /// @param random A random value for fuzzing random strategy
    function handlerWithdrawAllFromStrategy(uint8 random) public {
        address strategy;
        uint256 strategyBalance;
        uint256 len = strategies.length;
        // Select random strategy that has at least 1 USDC balance, otherwise skip
        for (uint256 i = random; i < random + len; i++) {
            if (usdc.balanceOf(strategies[i % len]) >= 1) {
                strategyBalance = usdc.balanceOf(strategies[i % len]);
                strategy = strategies[i % len];
                break;
            }
        }

        // Assume we find a valid strategy
        vm.assume(strategy != address(0));

        uint256 balanceBefore = usdc.balanceOf(address(strategy));
        // Prank as operator and call withdrawAllFromStrategy
        vm.prank(operator);
        vault.withdrawAllFromStrategy(strategy);

        // Log withdrawAllFromStrategy info
        if (!ENABLE_LOGS) return;
        uint256 balanceAfter = usdc.balanceOf(address(strategy));
        console.log(
            string(
                abi.encodePacked(
                    "> ",
                    vm.getLabel(operator),
                    " -> withdrawAllFromStrategy():     ",
                    (balanceBefore - balanceAfter).decimals(6, true, true),
                    " USDC from: ",
                    vm.getLabel(strategy)
                )
            )
        );
    }

    /// @notice Handler for withdrawAllFromStrategies function
    function handlerWithdrawAllFromStrategies() public {
        // Note: To avoid withdrawing from empty strategies, perhaps we can
        // check that at least one strategy has balance before calling this function.
        uint256 balanceBefore = usdc.balanceOf(address(vault));
        // Prank as operator and call withdrawAllFromStrategies
        vm.prank(operator);
        vault.withdrawAllFromStrategies();

        // Log withdrawAllFromStrategies info
        if (!ENABLE_LOGS) return;
        uint256 balanceAfter = usdc.balanceOf(address(vault));
        console.log(
            string(
                abi.encodePacked(
                    "> ",
                    vm.getLabel(operator),
                    " -> withdrawAllFromStrategies():   ",
                    (balanceAfter - balanceBefore).decimals(6, true, true),
                    " USDC"
                )
            )
        );
    }

    /// @notice Handler for simulateYieldOnStrategy function
    /// @param random A random value for fuzzing random strategy
    /// @param amount The amount of yield to simulate
    /// @dev amount is uint256 to allow large yield amounts
    function handlerSimulateYieldOnStrategy(uint8 random, uint256 amount) public {
        // Select random strategy that has at least 20 USDC balance, otherwise skip
        // 20 USDC is chosen to ensure we can simulate at least 0.05% yield
        address strategy;
        uint256 balanceBefore;
        uint256 len = strategies.length;
        for (uint256 i = random; i < random + len; i++) {
            if (usdc.balanceOf(strategies[i % len]) >= 20) {
                balanceBefore = usdc.balanceOf(strategies[i % len]);
                strategy = strategies[i % len];
                break;
            }
        }

        // Assume we find a valid strategy
        vm.assume(strategy != address(0));

        // Max reasonable yield is 5% of the current balance
        uint256 maxYield = balanceBefore / 20;

        // Bound amount to maxYield
        amount = _bound(amount, 1, maxYield);

        // Simulate yield on strategy
        usdc.mint(strategy, amount);

        // Log simulate yield info
        if (!ENABLE_LOGS) return;
        // Calculate yield percentage
        uint256 yieldPct = (amount * 1e18) / balanceBefore;
        console.log(
            string(
                abi.encodePacked(
                    "> ",
                    "Fuzzer  ",
                    " -> simulateYieldOnStrategy():     ",
                    amount.decimals(6, true, true),
                    " USDC (+",
                    yieldPct.decimals(16, true, true),
                    " %) for: ",
                    vm.getLabel(strategy)
                )
            )
        );
    }

    /// @notice Handler for simulateYieldOnVault function
    /// @param amount The amount of yield to simulate
    /// @dev amount is uint256 to allow large yield amounts
    function handlerSimulateYieldOnVault(uint256 amount) public {
        // Get vault balance (includes strategy balances)
        uint256 balance = vault.checkBalance(address(usdc));

        // Assume vault has at least 20 USDC balance
        vm.assume(balance >= 20);

        // Max reasonable yield is 5% of the current balance
        uint256 maxYield = balance / 20;

        // Bound amount to maxYield
        amount = _bound(amount, 1, maxYield);

        // Simulate yield on vault
        usdc.mint(address(vault), amount);

        // Log simulate yield info
        if (!ENABLE_LOGS) return;
        // Calculate yield percentage
        uint256 yieldPct = (amount * 1e18) / balance;
        console.log(
            string(
                abi.encodePacked(
                    "> ",
                    "Fuzzer  ",
                    " -> simulateYieldOnVault():        ",
                    amount.decimals(6, true, true),
                    " USDC (+",
                    yieldPct.decimals(16, true, true),
                    " %)"
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

        if (!ENABLE_LOGS) return;
        // Log set info
        // forgefmt: disable-start
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
    ///      For the test, the range will be 5 -> 15%
    function handlerSetMaxSupplyDiff(uint8 maxSupplyDiffPct) public {
        // Bound the parameter to valid range
        maxSupplyDiffPct = uint8(_bound(maxSupplyDiffPct, 5, 15));

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

    ////////////////////////////////////////////////////
    /// --- Time Manipulation Handlers
    ////////////////////////////////////////////////////
    /// @notice Handler for timeJump function
    /// @param secondsToWarp The number of seconds to warp forward
    function handlerTimeJump(uint24 secondsToWarp) public {
        // Bound the parameter to a reasonable range (10 minute to 30 days)
        uint256 timestampBefore = block.timestamp;
        secondsToWarp = uint24(_bound(secondsToWarp, 10 minutes, 30 days));
        // Time jump forward
        vm.warp(block.timestamp + secondsToWarp);

        // Log time jump info
        if (!ENABLE_LOGS) return;
        uint256 timestampAfter = block.timestamp;
        console.log(
            string(
                abi.encodePacked(
                    "> ",
                    "Fuzzer  ",
                    " -> timeJump():                    ",
                    timestampBefore.decimals(0, true, false),
                    " -> ",
                    timestampAfter.decimals(0, true, false),
                    " (+",
                    secondsToWarp.formatTime(),
                    ")"
                )
            )
        );
    }

    ////////////////////////////////////////////////////
    /// --- After Invariant
    ////////////////////////////////////////////////////
    function afterInvariant() public {
        if (ENABLE_LOGS) {
            console.log("");
            console.log("=== After Invariant ===");
        }

        // 1. Withdraw all from all strategies to ensure all assets are in the vault
        if (ENABLE_LOGS) {
            console.log("> Withdrawing all from all strategies...");
        }
        vm.prank(operator);
        vault.withdrawAllFromStrategies();

        // 2. Set Rebase Rate Max to high value to ensure all yield is rebased
        if (ENABLE_LOGS) {
            console.log("> Setting rebase rate max to high value...");
        }
        vm.prank(operator);
        vault.setRebaseRateMax(18.25 ether); // 18.25 ether

        // 3. Set drip duration to 1 day to ensure all fees are dripped quickly
        if (ENABLE_LOGS) {
            console.log("> Setting drip duration to 1 day...");
        }
        vm.prank(operator);
        vault.setDripDuration(1 days);
        vault.rebase();

        // 4. Timejump 100 days to ensure all fees are dripped
        if (ENABLE_LOGS) {
            console.log("> Timejumping 100 days to drip all fees...");
        }
        for (uint256 i; i < 10; i++) {
            skip(1 days);
            vault.rebase();
        }

        // 5. Ensure async withdrawals are enabled
        if (ENABLE_LOGS) {
            console.log("> Enabling async withdrawals with 1 day delay...");
        }
        vm.prank(governor);
        vault.setWithdrawalClaimDelay(1 days);

        // 6. Set max supply diff to 100% to avoid rebase issues during withdrawals
        if (ENABLE_LOGS) {
            console.log("> Setting max supply diff to 100%...");
        }
        vm.prank(governor);
        vault.setMaxSupplyDiff(1e18); // 100%

        // 7. Each user requests to withdraw their full OUSD balance
        if (ENABLE_LOGS) {
            console.log("> Users requesting withdrawals of their full OUSD balance...");
        }
        uint256 len = users.length;
        for (uint256 i = 0; i < len; i++) {
            address user = users[i];
            uint256 ousdBalance = ousd.balanceOf(user);
            if (ousdBalance > 0) {
                if (ENABLE_LOGS) {
                    console.log(
                        string(
                            abi.encodePacked(
                                "> ",
                                vm.getLabel(user),
                                "   ",
                                " -> requestWithdrawal():           ",
                                ousdBalance.decimals(18, true, true),
                                " OUSD"
                            )
                        )
                    );
                }
                vm.prank(user);
                vault.requestWithdrawal(ousdBalance);
                userToWithdrawalRequestIds[user].push(vault.getLastWithdrawalIndex());
            }
        }

        // 8. Timejump to after all withdrawal maturities
        if (ENABLE_LOGS) {
            console.log("> Timejumping 2 days to pass withdrawal claim delay...");
        }
        skip(2 days);

        // 9. Each user claims all their pending withdrawals
        if (ENABLE_LOGS) {
            console.log("> Users claiming all their pending withdrawals...");
        }
        for (uint256 i = 0; i < len; i++) {
            address user = users[i];
            uint256[] memory requests = userToWithdrawalRequestIds[user];
            if (requests.length > 0) {
                vm.prank(user);
                vault.claimWithdrawals(requests);
            }
        }
    }
}
