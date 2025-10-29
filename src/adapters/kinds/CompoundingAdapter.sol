// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../base/AdapterBase.sol";
import "../../utils/GiveErrors.sol";

/**
 * @title CompoundingAdapter
 * @author GIVE Labs
 * @notice Yield adapter for protocols with continuously compounding balance growth
 * @dev Models protocols where the adapter holds tokens that appreciate in balance over time.
 *      Yield is tracked by comparing actual balance to invested amount.
 *
 *      Compounding Model:
 *      - investedAmount: Principal deposited by vault
 *      - actualBalance: Current token balance (grows over time)
 *      - profit = actualBalance - investedAmount
 *
 *      Use Cases:
 *      - Staking protocols with auto-compounding rewards
 *      - Rebasing tokens (e.g., stETH, rETH)
 *      - Liquid staking derivatives
 *      - DeFi protocols that distribute rewards in same token
 *
 *      Example:
 *      1. Vault transfers 100 tokens → investedAmount = 100, balance = 100
 *      2. Protocol accrues rewards → balance grows to 105
 *      3. harvest() calculates profit = 105 - 100 = 5, sends 5 to vault
 *      4. investedAmount stays 100, balance now 100 again
 *
 *      Security Notes:
 *      - Tracks invested principal separately from grown balance
 *      - Harvest extracts only profit (balance - principal)
 *      - Emergency withdraw returns full balance regardless of accounting
 */
contract CompoundingAdapter is AdapterBase {
    using SafeERC20 for IERC20;

    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Total principal amount invested by the vault
    uint256 public investedAmount;

    /// @notice Pending profit to be distributed (for testing)
    uint256 public pendingProfit;

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /**
     * @notice Initializes the compounding adapter
     * @param adapterId Unique identifier for this adapter
     * @param asset Underlying asset address
     * @param vault Vault address authorized to use this adapter
     */
    constructor(bytes32 adapterId, address asset, address vault) AdapterBase(adapterId, asset, vault) {}

    // ============================================
    // IYIELDADAPTER IMPLEMENTATION
    // ============================================

    /**
     * @notice Returns total assets under management (actual token balance)
     * @dev Returns current balance held by adapter, which includes principal + accrued yield
     * @return Total assets in underlying token units
     */
    function totalAssets() external view override returns (uint256) {
        return asset().balanceOf(address(this));
    }

    /**
     * @notice Invests assets into the compounding protocol
     * @dev Vault must have already transferred tokens to this adapter.
     *      Increases invested amount tracker. Assumes tokens are already held.
     * @param assets Amount of assets being invested
     */
    function invest(uint256 assets) external override onlyVault {
        if (assets == 0) revert GiveErrors.InvalidInvestAmount();
        investedAmount += assets;
        emit Invested(assets);
    }

    /**
     * @notice Divests assets from the compounding protocol
     * @dev Withdraws requested amount (or full balance if insufficient).
     *      Reduces invested amount proportionally.
     * @param assets Amount of assets to divest
     * @return returned Actual amount of assets returned to vault
     */
    function divest(uint256 assets) external override onlyVault returns (uint256 returned) {
        if (assets == 0) revert GiveErrors.InvalidDivestAmount();

        uint256 balance = asset().balanceOf(address(this));
        returned = assets > balance ? balance : assets;

        if (returned > 0) {
            asset().safeTransfer(vault(), returned);
        }

        // Reduce invested amount (cap at 0 if divesting profit)
        if (returned <= investedAmount) {
            investedAmount -= returned;
        } else {
            investedAmount = 0;
        }

        emit Divested(assets, returned);
    }

    /**
     * @notice Harvests yield by transferring profit to vault
     * @dev Calculates profit as (current balance - invested principal).
     *      Transfers profit to vault and resets balance to principal level.
     * @return profit Amount of profit harvested and sent to vault
     * @return loss Always 0 (no loss tracking in compounding model)
     */
    function harvest() external override onlyVault returns (uint256 profit, uint256) {
        uint256 balance = asset().balanceOf(address(this));

        if (balance > investedAmount) {
            profit = balance - investedAmount;
            asset().safeTransfer(vault(), profit);
        }

        emit Harvested(profit, 0);
        return (profit, 0);
    }

    /**
     * @notice Emergency withdrawal of all assets
     * @dev Returns full balance to vault, resets accounting to zero.
     *      Does not distinguish between principal and profit in emergency.
     * @return returned Total assets withdrawn and sent to vault
     */
    function emergencyWithdraw() external override onlyVault returns (uint256 returned) {
        uint256 balance = asset().balanceOf(address(this));

        if (balance > 0) {
            asset().safeTransfer(vault(), balance);
        }

        investedAmount = 0;
        emit EmergencyWithdraw(balance);
        return balance;
    }

    // ============================================
    // TEST HELPERS
    // ============================================

    /**
     * @notice Adds external profit to simulate yield generation
     * @dev For testing only - simulates protocol rewards being deposited.
     *      Transfers tokens from caller to adapter to increase balance.
     * @param amount Amount of profit to add
     */
    function addProfit(uint256 amount) external {
        pendingProfit += amount;
        asset().safeTransferFrom(msg.sender, address(this), amount);
    }
}
