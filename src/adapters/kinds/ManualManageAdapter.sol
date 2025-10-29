// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "../base/AdapterBase.sol";
import "../../utils/GiveErrors.sol";

/**
 * @title ManualManageAdapter
 * @author GIVE Labs
 * @notice Yield adapter for manually managed off-chain or custodial yield strategies
 * @dev Enables authorized yield managers to withdraw funds for off-chain management,
 *      update balances after external operations, and maintain a buffer for user withdrawals.
 *
 *      Manual Management Model:
 *      - investedAmount: Total principal recorded as invested
 *      - managedBalance: Current balance under management (updated by yield manager)
 *      - bufferAmount: Reserved amount kept in adapter for quick withdrawals
 *      - YIELD_MANAGER_ROLE: Authorized to withdraw, deposit, and update balance
 *
 *      Use Cases:
 *      - Off-chain yield generation (CEX staking, lending desks)
 *      - Custodial yield strategies
 *      - Manual rebalancing across multiple protocols
 *      - Bridging to L2/sidechains for higher yields
 *      - Temporary manual management during migration
 *
 *      Workflow:
 *      1. Vault invests → tokens transferred to adapter
 *      2. Yield manager withdraws for off-chain management
 *      3. Yield manager updates managedBalance to reflect current value
 *      4. Yield manager deposits returns and updates balance
 *      5. harvest() calculates profit from balance updates
 *      6. Buffer maintained for instant withdrawals
 *
 *      Example:
 *      1. invest(100) → investedAmount = 100, balance = 100
 *      2. managerWithdraw(90) → 90 sent to manager, 10 buffer remains
 *      3. Manager generates yield off-chain → 95 total
 *      4. updateManagedBalance(95) → managedBalance = 95
 *      5. harvest() → profit = 95 - 100 = -5 (loss) or +5 if grew
 *      6. managerDeposit(90) → returns capital, balance updated
 *
 *      Security Model:
 *      - YIELD_MANAGER_ROLE: Withdraw, deposit, update balance
 *      - Vault-only for invest/divest/harvest/emergency
 *      - Buffer prevents manager from withdrawing all funds
 *      - Balance updates are trusted (manager must be reputable)
 *
 *      Risk Considerations:
 *      - Requires trust in yield manager
 *      - Balance updates are self-reported (not verifiable on-chain)
 *      - Manager must return funds for withdrawals
 *      - Buffer amount should cover expected withdrawal needs
 */
contract ManualManageAdapter is AdapterBase, AccessControl {
    using SafeERC20 for IERC20;

    // ============================================
    // CONSTANTS
    // ============================================

    /// @notice Role for authorized yield managers
    bytes32 public constant YIELD_MANAGER_ROLE = keccak256("YIELD_MANAGER_ROLE");

    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Total principal amount invested by vault
    uint256 public investedAmount;

    /// @notice Current balance under management (updated by yield manager)
    /// @dev Includes both on-chain buffer and off-chain managed funds
    uint256 public managedBalance;

    /// @notice Minimum buffer to maintain in adapter for withdrawals
    uint256 public bufferAmount;

    /// @notice Total amount currently managed off-chain by yield manager
    uint256 public offChainAmount;

    // ============================================
    // EVENTS
    // ============================================

    event ManagerWithdraw(address indexed manager, uint256 amount, address recipient);
    event ManagerDeposit(address indexed manager, uint256 amount);
    event ManagedBalanceUpdated(address indexed manager, uint256 oldBalance, uint256 newBalance);
    event BufferAmountUpdated(uint256 oldBuffer, uint256 newBuffer);

    // ============================================
    // ERRORS
    // ============================================

    error InsufficientBuffer();
    error InsufficientAdapterBalance();
    error InvalidBalanceUpdate();

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /**
     * @notice Initializes the manual manage adapter
     * @param adapterId Unique identifier for this adapter
     * @param asset Underlying asset address
     * @param vault Vault address authorized to use this adapter
     * @param admin Admin address to grant DEFAULT_ADMIN_ROLE
     * @param yieldManager Address to grant YIELD_MANAGER_ROLE
     * @param initialBuffer Initial buffer amount to maintain
     */
    constructor(
        bytes32 adapterId,
        address asset,
        address vault,
        address admin,
        address yieldManager,
        uint256 initialBuffer
    ) AdapterBase(adapterId, asset, vault) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(YIELD_MANAGER_ROLE, yieldManager);
        bufferAmount = initialBuffer;
    }

    // ============================================
    // IYIELDADAPTER IMPLEMENTATION
    // ============================================

    /**
     * @notice Returns total assets under management
     * @dev Returns managedBalance which includes both on-chain buffer and off-chain managed funds
     * @return Total managed balance
     */
    function totalAssets() external view override returns (uint256) {
        return managedBalance;
    }

    /**
     * @notice Invests assets into manual management
     * @dev Records investment and updates managed balance.
     *      Assumes vault has already transferred tokens to adapter.
     * @param assets Amount of assets being invested
     */
    function invest(uint256 assets) external override onlyVault {
        if (assets == 0) revert GiveErrors.InvalidInvestAmount();

        investedAmount += assets;
        managedBalance += assets;

        emit Invested(assets);
    }

    /**
     * @notice Divests assets from manual management
     * @dev Transfers assets from adapter buffer to vault.
     *      If insufficient buffer, manager must deposit funds first.
     * @param assets Amount of assets to divest
     * @return returned Actual amount returned to vault
     */
    function divest(uint256 assets) external override onlyVault returns (uint256 returned) {
        if (assets == 0) revert GiveErrors.InvalidDivestAmount();

        uint256 adapterBalance = asset().balanceOf(address(this));

        // Cap at available balance
        returned = assets > adapterBalance ? adapterBalance : assets;

        if (returned > 0) {
            asset().safeTransfer(vault(), returned);

            // Update accounting
            if (returned <= investedAmount) {
                investedAmount -= returned;
            } else {
                investedAmount = 0;
            }

            if (returned <= managedBalance) {
                managedBalance -= returned;
            } else {
                managedBalance = 0;
            }
        }

        emit Divested(assets, returned);
    }

    /**
     * @notice Harvests yield based on managed balance updates
     * @dev Calculates profit/loss as difference between managedBalance and investedAmount.
     *      Does not transfer funds - yield manager must deposit profit separately.
     * @return profit Amount of profit (if managedBalance > investedAmount)
     * @return loss Amount of loss (if managedBalance < investedAmount)
     */
    function harvest() external override onlyVault returns (uint256 profit, uint256 loss) {
        if (managedBalance > investedAmount) {
            profit = managedBalance - investedAmount;

            // Check if profit is available in adapter to send
            uint256 adapterBalance = asset().balanceOf(address(this));
            uint256 transferable = profit > adapterBalance ? adapterBalance : profit;

            if (transferable > 0) {
                asset().safeTransfer(vault(), transferable);
                managedBalance -= transferable;
                profit = transferable;
            } else {
                // Profit exists but not yet deposited by manager
                profit = 0;
            }

            loss = 0;
        } else if (managedBalance < investedAmount) {
            loss = investedAmount - managedBalance;
            investedAmount = managedBalance;
            profit = 0;
        } else {
            profit = 0;
            loss = 0;
        }

        emit Harvested(profit, loss);
        return (profit, loss);
    }

    /**
     * @notice Emergency withdrawal of all available assets
     * @dev Returns full adapter balance to vault, resets accounting.
     *      Cannot retrieve off-chain funds - manager must return them separately.
     * @return returned Amount withdrawn from adapter
     */
    function emergencyWithdraw() external override onlyVault returns (uint256 returned) {
        uint256 adapterBalance = asset().balanceOf(address(this));

        if (adapterBalance > 0) {
            asset().safeTransfer(vault(), adapterBalance);
        }

        returned = adapterBalance;
        investedAmount = 0;
        managedBalance = 0;
        offChainAmount = 0;

        emit EmergencyWithdraw(returned);
    }

    // ============================================
    // YIELD MANAGER FUNCTIONS
    // ============================================

    /**
     * @notice Withdraws funds for off-chain management
     * @dev Only yield manager can call. Must maintain minimum buffer for user withdrawals.
     * @param amount Amount to withdraw
     * @param recipient Address to receive withdrawn funds
     */
    function managerWithdraw(uint256 amount, address recipient) external onlyRole(YIELD_MANAGER_ROLE) {
        if (recipient == address(0)) revert GiveErrors.ZeroAddress();

        uint256 adapterBalance = asset().balanceOf(address(this));

        // Ensure we maintain minimum buffer
        if (adapterBalance - amount < bufferAmount) {
            revert InsufficientBuffer();
        }

        offChainAmount += amount;
        asset().safeTransfer(recipient, amount);

        emit ManagerWithdraw(msg.sender, amount, recipient);
    }

    /**
     * @notice Deposits funds back from off-chain management
     * @dev Yield manager returns funds to adapter. Updates off-chain tracking.
     * @param amount Amount to deposit
     */
    function managerDeposit(uint256 amount) external onlyRole(YIELD_MANAGER_ROLE) {
        if (amount == 0) revert GiveErrors.InvalidInvestAmount();

        asset().safeTransferFrom(msg.sender, address(this), amount);

        if (amount <= offChainAmount) {
            offChainAmount -= amount;
        } else {
            offChainAmount = 0;
        }

        emit ManagerDeposit(msg.sender, amount);
    }

    /**
     * @notice Updates the managed balance to reflect current value
     * @dev Yield manager reports current total value (on-chain + off-chain).
     *      Used to track profit/loss from off-chain operations.
     * @param newBalance New total managed balance
     */
    function updateManagedBalance(uint256 newBalance) external onlyRole(YIELD_MANAGER_ROLE) {
        uint256 oldBalance = managedBalance;
        managedBalance = newBalance;

        emit ManagedBalanceUpdated(msg.sender, oldBalance, newBalance);
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    /**
     * @notice Updates the minimum buffer amount
     * @dev Only admin can modify buffer requirements
     * @param newBuffer New minimum buffer amount
     */
    function setBufferAmount(uint256 newBuffer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldBuffer = bufferAmount;
        bufferAmount = newBuffer;

        emit BufferAmountUpdated(oldBuffer, newBuffer);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Returns current adapter state
     * @return invested Total invested principal
     * @return managed Current managed balance
     * @return buffer Minimum buffer requirement
     * @return offChain Amount currently managed off-chain
     * @return adapterBal Current adapter token balance
     */
    function getAdapterState()
        external
        view
        returns (uint256 invested, uint256 managed, uint256 buffer, uint256 offChain, uint256 adapterBal)
    {
        return (investedAmount, managedBalance, bufferAmount, offChainAmount, asset().balanceOf(address(this)));
    }
}
