// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.31;

// Solmate
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

// Origin Dollar
import {OUSD} from "@origin-dollar/token/OUSD.sol";
import {OUSDVault} from "@origin-dollar/vault/OUSDVault.sol";
import {OUSDProxy} from "@origin-dollar/proxies/Proxies.sol";
import {VaultProxy} from "@origin-dollar/proxies/Proxies.sol";
import {VaultInitializer} from "@origin-dollar/vault/VaultInitializer.sol";

// Internal
import {MockStrategyAMO} from "src/MockStrategyAMO.sol";
import {MockStrategyTrad} from "src/MockStrategyTrad.sol";

// Test
import {Base} from "test/Base.t.sol";

/// @title Setup
/// @notice Abstract contract responsible for test environment initialization and contract deployment.
/// @dev    This contract orchestrates the complete test setup process in a structured manner:
///         1. Environment configuration (block timestamp, number)
///         2. User address generation and role assignment
///         3. External contract deployment (mocks, dependencies)
///         4. Main contract deployment
///         5. System initialization and configuration
///         6. Address labeling for improved traceability
///         No test logic should be implemented here, only setup procedures.
abstract contract Setup is Base {
    ////////////////////////////////////////////////////
    /// --- SETUP
    ////////////////////////////////////////////////////
    function setUp() public virtual {
        // 1. Setup a realistic test environment
        _setUpRealisticEnvironment();

        // 2. Create user
        _createUsers();

        // To increase performance, we will not use fork., mocking contract instead.
        // 3. Deploy mocks.
        _deployMocks();

        // 4. Deploy contracts.
        _deployContracts();

        // 5. Initialize users and contracts.
        _initiliaze();

        // 6. Label addresses for clarity in traces.
        _labelAddresses();
    }

    //////////////////////////////////////////////////////
    /// --- ENVIRONMENT
    //////////////////////////////////////////////////////
    function _setUpRealisticEnvironment() private {
        vm.warp(1_760_000_000);
        vm.roll(24_000_000);
    }

    //////////////////////////////////////////////////////
    /// --- USERS
    //////////////////////////////////////////////////////
    function _createUsers() private {
        users.push(alice);
        users.push(bobby);
        users.push(cathy);
        users.push(david);
    }

    //////////////////////////////////////////////////////
    /// --- MOCKS
    /////////////////////////////////////////////////////
    function _deployMocks() private {
        usdc = new MockERC20("USD Coin", "USDC", 6);
    }

    //////////////////////////////////////////////////////
    /// --- CONTRACTS
    //////////////////////////////////////////////////////
    function _deployContracts() private {
        vm.startPrank(deployer);

        // Deploy proxies first
        ousdProxy = new OUSDProxy();
        vaultProxy = new VaultProxy();

        // Deploy implementations
        ousd = new OUSD();
        vault = new OUSDVault(address(usdc));

        // Initialize proxies
        ousdProxy.initialize(
            address(ousd), governor, abi.encodeWithSelector(OUSD.initialize.selector, address(vaultProxy), 1e27)
        );
        vaultProxy.initialize(
            address(vault), governor, abi.encodeWithSelector(VaultInitializer.initialize.selector, address(ousdProxy))
        );

        // Set logic contract on proxies
        ousd = OUSD(address(ousdProxy));
        vault = OUSDVault(address(vaultProxy));

        vm.stopPrank();

        strategyAMO = new MockStrategyAMO(address(vault));
        strategyTrad = new MockStrategyTrad(address(vault));
        strategies.push(address(strategyAMO));
        strategies.push(address(strategyTrad));
    }

    //////////////////////////////////////////////////////
    /// --- INITIALIZE
    //////////////////////////////////////////////////////
    function _initiliaze() private {
        vm.startPrank(governor);
        vault.setStrategistAddr(operator);
        vault.unpauseCapital();
        vault.setWithdrawalClaimDelay(10 minutes);
        vault.approveStrategy(address(strategyAMO));
        vault.approveStrategy(address(strategyTrad));
        vault.addStrategyToMintWhitelist(address(strategyAMO));
        vault.setDefaultStrategy(address(strategyTrad));
        vault.setTrusteeAddress(treasury);
        vm.stopPrank();

        // All users approve vault to spend USDC
        for (uint256 i; i < users.length; i++) {
            vm.prank(users[i]);
            usdc.approve(address(vault), type(uint256).max);
        }

        // Alice mints some OUSD and give them to dead address
        vm.startPrank(alice);
        usdc.mint(alice, DEAD_AMOUNT);
        vault.mint(DEAD_AMOUNT);
        ousd.transfer(dead, DEAD_AMOUNT * 1e12); // Convert to 18 decimals
        vm.stopPrank();
    }

    //////////////////////////////////////////////////////
    /// --- LABELS
    //////////////////////////////////////////////////////
    function _labelAddresses() private {
        vm.label(address(usdc), "USDC");
        vm.label(address(ousd), "OUSD");
        vm.label(address(vault), "Vault");
        vm.label(address(ousdProxy), "OUSD Proxy");
        vm.label(address(vaultProxy), "Vault Proxy");
        vm.label(address(strategyAMO), "Strategy AMO");
        vm.label(address(strategyTrad), "Strategy Trad");
    }
}
