// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.31;

// Foundry
import {Vm} from "@forge-std/Vm.sol";

// Origin Dollar
import {OUSD} from "@origin-dollar/token/OUSD.sol";
import {OUSDVault} from "@origin-dollar/vault/OUSDVault.sol";

library Getter {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Replicates the logic in OUSDVault to determine the available asset
    /// @param vault The vault to check
    /// @return The amount of asset available in the vault
    function availableAsset(OUSDVault vault) internal view returns (uint256) {
        (uint128 queued,, uint128 claimed,) = vault.withdrawalQueueMetadata();

        // The amount of asset that is still to be claimed in the withdrawal queue
        uint256 outstandingWithdrawals = queued - claimed;

        // The amount of sitting in asset in the vault
        uint256 assetBalance = OUSD(vault.asset()).balanceOf(address(vault));
        // If there is not enough asset in the vault to cover the outstanding withdrawals
        if (assetBalance <= outstandingWithdrawals) return 0;

        return assetBalance - outstandingWithdrawals;
    }

    /// @notice Gets the last withdrawal request index from the vault
    /// @param vault The vault to check
    /// @return The last withdrawal request index
    function getLastWithdrawalIndex(OUSDVault vault) internal view returns (uint256) {
        (,,, uint128 lastIndex) = vault.withdrawalQueueMetadata();
        return lastIndex - 1;
    }

    /// @notice Gets the timestamp of a withdrawal request
    /// @param vault The vault to check
    /// @param requestId The id of the withdrawal request
    /// @return The timestamp of the withdrawal request
    function getRequestTimestamp(OUSDVault vault, uint256 requestId) internal view returns (uint256) {
        (,, uint40 requestTimestamp,,) = vault.withdrawalRequests(requestId);
        return requestTimestamp;
    }
}
