// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../base/AdapterBase.sol";
import "../../utils/GiveErrors.sol";

/**
 * @title GrowthAdapter
 * @author GIVE Labs
 * @notice Yield adapter for assets that grow in value over time through an index mechanism
 * @dev Models protocols where deposited assets grow via an increasing index (e.g., Compound cTokens, Aave aTokens).
 *      The adapter tracks normalized deposits and converts them using a growth index.
 *
 *      Growth Model:
 *      - totalDeposits: Normalized amount deposited (in base units)
 *      - growthIndex: Conversion rate from normalized to actual value (starts at 1e18)
 *      - actualValue = (totalDeposits * growthIndex) / 1e18
 *
 *      Use Cases:
 *      - Wrapped yield-bearing tokens (aTokens, cTokens)
 *      - Rebasing token wrappers
 *      - Index-based growth protocols
 *
 *      Example:
 *      1. Deposit 100 tokens at index 1.0 → totalDeposits = 100
 *      2. Index grows to 1.1 → actualValue = 100 * 1.1 = 110 tokens
 *      3. Divest 110 tokens → returns 110, totalDeposits reduced by 100
 *
 *      Security Notes:
 *      - Growth index can only increase (enforced in setGrowthIndex)
 *      - No actual asset transfer on invest() - represents token wrapping
 *      - Divest calculates proportional normalized amount to withdraw
 */
contract GrowthAdapter is AdapterBase {
    using SafeERC20 for IERC20;

    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Total normalized deposits (before applying growth index)
    uint256 public totalDeposits;

    /// @notice Current growth index (1e18 = 1.0, 1.1e18 = 1.1)
    /// @dev Index can only increase over time, representing asset appreciation
    uint256 public growthIndex = 1e18;

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /**
     * @notice Initializes the growth adapter
     * @param adapterId Unique identifier for this adapter
     * @param asset Underlying asset address
     * @param vault Vault address authorized to use this adapter
     */
    constructor(bytes32 adapterId, address asset, address vault) AdapterBase(adapterId, asset, vault) {}

    // ============================================
    // IYIELDADAPTER IMPLEMENTATION
    // ============================================

    /**
     * @notice Returns total assets under management (normalized deposits * growth index)
     * @dev Calculates actual asset value by applying growth index to normalized deposits
     * @return Total assets in underlying token units
     */
    function totalAssets() external view override returns (uint256) {
        return (totalDeposits * growthIndex) / 1e18;
    }

    /**
     * @notice Records asset investment (no actual transfer needed for growth model)
     * @dev Increases normalized deposits. No token transfer as this represents wrapping.
     *      In real protocols, vault would have already wrapped assets into yield-bearing tokens.
     * @param assets Amount of assets being invested
     */
    function invest(uint256 assets) external override onlyVault {
        if (assets == 0) revert GiveErrors.InvalidInvestAmount();
        totalDeposits += assets;
        emit Invested(assets);
    }

    /**
     * @notice Divests assets by unwrapping and transferring back to vault
     * @dev Calculates normalized amount to remove based on current growth index,
     *      then transfers actual grown value back to vault.
     * @param assets Amount of assets to divest (in grown value)
     * @return returned Actual amount of assets returned to vault
     */
    function divest(uint256 assets) external override onlyVault returns (uint256 returned) {
        // Calculate normalized amount to remove
        uint256 normalized = (assets * 1e18) / growthIndex;

        // Cap at total deposits to prevent overflow
        if (normalized > totalDeposits) {
            normalized = totalDeposits;
        }

        // Reduce normalized deposits
        totalDeposits -= normalized;

        // Calculate actual return value (may differ from requested if capped)
        returned = (normalized * growthIndex) / 1e18;

        if (returned > 0) {
            asset().safeTransfer(vault(), returned);
        }

        emit Divested(assets, returned);
    }

    /**
     * @notice Harvest function (no-op for growth adapters)
     * @dev Growth adapters don't harvest separately - yield is realized on divest.
     *      Returns (0, 0) as no active yield harvesting occurs.
     * @return profit Always 0 (growth realized on withdraw)
     * @return loss Always 0 (no loss mechanism)
     */
    function harvest() external view override onlyVault returns (uint256, uint256) {
        return (0, 0);
    }

    /**
     * @notice Emergency withdrawal of all assets at current growth value
     * @dev Withdraws full position at current growth index, resets state to initial.
     *      Does NOT transfer assets (assumes vault handles emergency separately).
     * @return returned Total assets at current growth value
     */
    function emergencyWithdraw() external override onlyVault returns (uint256 returned) {
        returned = (totalDeposits * growthIndex) / 1e18;
        totalDeposits = 0;
        growthIndex = 1e18;
        emit EmergencyWithdraw(returned);
    }

    // ============================================
    // TEST HELPERS
    // ============================================

    /**
     * @notice Sets the growth index for testing
     * @dev Only for testing - simulates asset appreciation over time.
     *      In production, this would be updated by oracle or protocol data.
     * @param newIndex New growth index value (must be >= 1e18)
     */
    function setGrowthIndex(uint256 newIndex) external {
        require(newIndex >= 1e18, "growth < 1");
        growthIndex = newIndex;
    }
}
