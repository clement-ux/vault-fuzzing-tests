// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.31;

import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

import {OUSDVault} from "@origin-dollar/vault/OUSDVault.sol";

contract MockStrategyAMO {
    OUSDVault public vault;
    MockERC20 public asset;

    event AssetDeposited(uint256 amount);
    event AssetWithdrawn(uint256 amount);

    modifier onlyVault() {
        require(msg.sender == address(vault), "Only vault can call");
        _;
    }

    constructor(address _vault) {
        vault = OUSDVault(_vault);
        asset = MockERC20(vault.asset());
    }

    function checkBalance(address) public view returns (uint256 balance) {
        return asset.balanceOf(address(this));
    }

    function supportsAsset(address _asset) public view returns (bool) {
        return _asset == address(asset);
    }

    function deposit(address, uint256 amount) public onlyVault {
        // Mint same amount of asset deposited, simulate OUSD/USDC pool.
        vault.mintForStrategy(amount * 1e12); // assuming 6 to 18 decimals
        emit AssetDeposited(amount);
    }
    function depositAll() public onlyVault {}

    function withdraw(address, address, uint256 amount) public onlyVault {
        asset.transfer(address(vault), amount);
        vault.burnForStrategy(amount * 1e12); // assuming 6 to 18 decimals
        emit AssetWithdrawn(amount);
    }

    function withdrawAll() public onlyVault {
        uint256 balance = asset.balanceOf(address(this));
        asset.transfer(address(vault), balance);
        vault.burnForStrategy(balance * 1e12); // assuming 6 to 18 decimals
        emit AssetWithdrawn(balance);
    }
}
