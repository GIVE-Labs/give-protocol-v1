// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../base/AdapterBase.sol";
import "../../utils/GiveErrors.sol";

/**
 * @title ClaimableYieldAdapter
 * @author GIVE Labs
 * @notice Yield adapter for protocols where yield must be explicitly claimed
 * @dev Models protocols with separate claim mechanisms where rewards accumulate off-chain
 *      and must be pulled via claim transactions.
 *
 *      Claimable Yield Model:
 *      - investedAmount: Principal deposited (tracked separately)
 *      - queuedYield: Rewards that have been claimed but not yet harvested
 *      - totalAssets() returns only principal (yield separate until harvest)
 *
 *      Use Cases:
 *      - Staking protocols with claimRewards() functions
 *      - Liquidity mining with separate reward tokens
 *      - Protocols with merkle-based reward distribution
 *      - Any protocol requiring explicit claim transaction
 *
 *      Workflow:
 *      1. invest() deposits principal
 *      2. External claim() transaction pulls rewards into queuedYield
 *      3. harvest() distributes queuedYield to vault
 *      4. divest() withdraws principal only
 *
 *      Example:
 *      1. Deposit 100 tokens → investedAmount = 100
 *      2. Rewards accrue off-chain (5 tokens)
 *      3. queueYield(5) called → queuedYield = 5
 *      4. harvest() sends 5 to vault, queuedYield = 0
 *      5. investedAmount still 100
 *
 *      Security Notes:
 *      - Separates principal from yield tracking
 *      - Yield must be explicitly queued before harvesting
 *      - Emergency withdraw includes both principal and queued yield
 */
contract ClaimableYieldAdapter is AdapterBase {
    using SafeERC20 for IERC20;

    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Total principal amount invested by the vault
    uint256 public investedAmount;

    /// @notice Yield that has been claimed and queued for harvest
    uint256 public queuedYield;

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /**
     * @notice Initializes the claimable yield adapter
     * @param adapterId Unique identifier for this adapter
     * @param asset Underlying asset address
     * @param vault Vault address authorized to use this adapter
     */
    constructor(bytes32 adapterId, address asset, address vault) AdapterBase(adapterId, asset, vault) {}

    // ============================================
    // IYIELDADAPTER IMPLEMENTATION
    // ============================================

    /**
     * @notice Returns total assets under management (principal only, excludes queued yield)
     * @dev Queued yield is tracked separately and distributed via harvest().
     *      This prevents double-counting in vault asset calculations.
     * @return Total invested principal
     */
    function totalAssets() external view override returns (uint256) {
        return investedAmount;
    }

    /**
     * @notice Invests assets into the protocol
     * @dev Records principal investment. In production, vault would have staked/deposited
     *      into external protocol before calling this.
     * @param assets Amount of assets being invested
     */
    function invest(uint256 assets) external override onlyVault {
        if (assets == 0) revert GiveErrors.InvalidInvestAmount();
        investedAmount += assets;
        emit Invested(assets);
    }

    /**
     * @notice Divests principal from the protocol
     * @dev Withdraws only principal, not queued yield. Caps at available principal.
     *      Queued yield remains for future harvest.
     * @param assets Amount of assets to divest
     * @return returned Actual amount of principal returned to vault
     */
    function divest(uint256 assets) external override onlyVault returns (uint256 returned) {
        if (assets == 0) revert GiveErrors.InvalidDivestAmount();

        // Cap withdrawal at invested amount
        if (assets > investedAmount) {
            returned = investedAmount;
            investedAmount = 0;
        } else {
            investedAmount -= assets;
            returned = assets;
        }

        if (returned > 0) {
            asset().safeTransfer(vault(), returned);
        }

        emit Divested(assets, returned);
    }

    /**
     * @notice Harvests queued yield and sends to vault
     * @dev Distributes all queued yield to vault, resets queue to zero.
     *      Does not interact with external protocol - only distributes already-claimed rewards.
     * @return profit Amount of queued yield harvested
     * @return loss Always 0 (no loss mechanism in claimable model)
     */
    function harvest() external override onlyVault returns (uint256 profit, uint256 loss) {
        profit = queuedYield;
        queuedYield = 0;

        if (profit > 0) {
            asset().safeTransfer(vault(), profit);
        }

        loss = 0;
        emit Harvested(profit, loss);
        return (profit, loss);
    }

    /**
     * @notice Emergency withdrawal of all assets
     * @dev Returns both principal and queued yield to vault, resets all accounting.
     * @return returned Total of principal + queued yield withdrawn
     */
    function emergencyWithdraw() external override onlyVault returns (uint256 returned) {
        returned = investedAmount + queuedYield;

        investedAmount = 0;
        queuedYield = 0;

        if (returned > 0) {
            asset().safeTransfer(vault(), returned);
        }

        emit EmergencyWithdraw(returned);
    }

    // ============================================
    // YIELD MANAGEMENT
    // ============================================

    /**
     * @notice Queues claimed yield for future harvest
     * @dev For testing/integration - simulates external claim transaction.
     *      In production, this would be called after claiming from external protocol.
     *      Transfers tokens from caller to adapter and adds to yield queue.
     * @param amount Amount of yield to queue
     */
    function queueYield(uint256 amount) external {
        asset().safeTransferFrom(msg.sender, address(this), amount);
        queuedYield += amount;
    }
}
