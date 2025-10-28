// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IYieldAdapter
 * @author GIVE Labs
 * @notice Interface for yield adapters that invest vault assets into external DeFi protocols
 * @dev All adapters must implement this interface to be compatible with GiveVault4626.
 *      Adapters act as intermediaries between vaults and external yield sources (Aave, Compound, etc).
 *
 *      Adapter Kinds (defined in GiveTypes.AdapterKind):
 *      - CompoundingValue: Balance stays constant while the exchange rate accrues value (e.g., sUSDe, wstETH, Compound cTokens)
 *      - ClaimableYield: Yield must be claimed separately and realised during harvest (e.g., Pancake V2 liquidity mining)
 *      - BalanceGrowth: Token balance increases automatically over time (e.g., Aave aTokens)
 *      - FixedMaturityToken: Principal/yield tokens with maturity or expiry (e.g., Pendle PT) – requires settlement logic upstream
 *
 *      Security Requirements:
 *      - Only the vault should be able to call invest/divest/harvest
 *      - Emergency withdraw should be restricted to authorized roles
 *      - All external protocol interactions should handle failures gracefully
 */
interface IYieldAdapter {
    // ============================================
    // EVENTS
    // ============================================

    /**
     * @notice Emitted when assets are invested into the yield protocol
     * @param assets The amount of assets invested
     */
    event Invested(uint256 assets);

    /**
     * @notice Emitted when assets are divested from the yield protocol
     * @param requested The amount of assets requested for divestment
     * @param returned The actual amount of assets returned (may differ due to slippage)
     */
    event Divested(uint256 requested, uint256 returned);

    /**
     * @notice Emitted when yield is harvested
     * @param profit The amount of profit realized (assets gained)
     * @param loss The amount of loss realized (assets lost)
     */
    event Harvested(uint256 profit, uint256 loss);

    /**
     * @notice Emitted during emergency withdrawal
     * @param returned The amount of assets returned from emergency withdrawal
     */
    event EmergencyWithdraw(uint256 returned);

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Returns the underlying asset that this adapter accepts
     * @dev Must be the same asset as the vault's underlying asset
     * @return The ERC20 token address
     */
    function asset() external view returns (IERC20);

    /**
     * @notice Returns the total assets under management by this adapter
     * @dev Should include:
     *      - Assets deposited in external protocol
     *      - Accrued but unclaimed yield
     *      - Assets held in adapter (idle capital)
     * @return The total amount of underlying assets
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Returns the vault address that owns this adapter
     * @dev Used for access control to ensure only vault can call sensitive functions
     * @return The vault contract address
     */
    function vault() external view returns (address);

    // ============================================
    // STATE-CHANGING FUNCTIONS
    // ============================================

    /**
     * @notice Invests the specified amount of assets into the yield protocol
     * @dev Should transfer assets from vault and deposit into external protocol.
     *      Only callable by the vault.
     * @param assets The amount of assets to invest
     */
    function invest(uint256 assets) external;

    /**
     * @notice Divests the specified amount of assets from the yield protocol
     * @dev Should withdraw from external protocol and transfer back to vault.
     *      Actual returned amount may differ from requested due to slippage or withdrawal fees.
     *      Only callable by the vault.
     * @param assets The amount of assets to divest
     * @return returned The actual amount of assets returned (may be less due to slippage)
     */
    function divest(uint256 assets) external returns (uint256 returned);

    /**
     * @notice Harvests yield and realizes profit/loss
     * @dev Should:
     *      1. Calculate accrued yield since last harvest
     *      2. Claim any pending rewards from external protocol
     *      3. Update internal accounting
     *      4. Return profit/loss amounts for vault tracking
     *
     *      Only callable by the vault.
     * @return profit The amount of profit realized (0 if loss)
     * @return loss The amount of loss realized (0 if profit)
     */
    function harvest() external returns (uint256 profit, uint256 loss);

    /**
     * @notice Emergency function to withdraw all assets from the protocol
     * @dev Should:
     *      - Withdraw all assets from external protocol immediately
     *      - Bypass normal slippage/fee checks if necessary
     *      - Transfer all recovered assets back to vault
     *
     *      Only callable by authorized emergency roles (typically via vault's emergency mode).
     * @return returned The amount of assets returned
     */
    function emergencyWithdraw() external returns (uint256 returned);
}
