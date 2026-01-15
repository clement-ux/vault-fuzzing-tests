// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.31;

// Foundry
import {Test} from "@forge-std/Test.sol";

// Solmate
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

// Origin Dollar
import {OUSD} from "@origin-dollar/token/OUSD.sol";
import {OUSDVault} from "@origin-dollar/vault/OUSDVault.sol";
import {OUSDProxy} from "@origin-dollar/proxies/Proxies.sol";
import {VaultProxy} from "@origin-dollar/proxies/Proxies.sol";

// Internal
import {MockStrategyAMO} from "src/MockStrategyAMO.sol";
import {MockStrategyTrad} from "src/MockStrategyTrad.sol";

/// @title Base
/// @notice Abstract base contract defining shared state variables and contract instances for the test suite.
/// @dev    This contract serves as the foundation for all test contracts, providing:
///         - Contract instances (tokens, external dependencies)
///         - Address definitions (users, governance, deployers)
///         - No logic or setup should be included here, only state variable declarations
abstract contract Base is Test {
    ////////////////////////////////////////////////////
    /// --- CONSTANTS
    ////////////////////////////////////////////////////
    /// @notice Enable or disable logs during tests
    /// @dev Having it enable slows down tests.
    bool internal constant ENABLE_LOGS = true;
    /// @notice Initial USDC balance used to mint OUSD to dead address
    uint256 internal constant DEAD_AMOUNT = 100e6;

    ////////////////////////////////////////////////////
    /// --- USERS
    ////////////////////////////////////////////////////
    // Users
    address public dead = makeAddr("dead");
    address public alice = makeAddr("Alice");
    address public bobby = makeAddr("Bobby");
    address public cathy = makeAddr("Cathy");
    address public david = makeAddr("David");
    address public deployer = makeAddr("Deployer");
    address public operator = makeAddr("Operator");
    address public governor = makeAddr("Governor");
    address public treasury = makeAddr("Treasury");
    address[] public users;

    address[] public strategies;

    ////////////////////////////////////////////////////
    /// --- CONTRACTS & MOCKS
    ////////////////////////////////////////////////////
    OUSD internal ousd;
    MockERC20 internal usdc;
    OUSDVault internal vault;
    OUSDProxy internal ousdProxy;
    VaultProxy internal vaultProxy;
    MockStrategyAMO internal strategyAMO;
    MockStrategyTrad internal strategyTrad;

    ////////////////////////////////////////////////////
    /// --- INVARIANT RELATED STATE VARIABLES
    ////////////////////////////////////////////////////
    mapping(address user => uint256[] withdrawalRequestIds) internal userToWithdrawalRequestIds;

    function getWithdrawalRequestIds(address user) internal view returns (uint256[] memory) {
        return userToWithdrawalRequestIds[user];
    }
}
