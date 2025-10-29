// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../storage/StorageLib.sol";
import "../types/GiveTypes.sol";

/**
 * @title RiskModule
 * @author GIVE Labs
 * @notice Library module for risk parameter configuration and enforcement
 * @dev Provides functions to configure risk limits and enforce them during vault operations.
 *      Used by GiveProtocolCore to manage vault risk profiles.
 *
 *      Key Responsibilities:
 *      - Configure risk parameters (LTV, liquidation thresholds, penalties)
 *      - Assign risk profiles to vaults
 *      - Enforce deposit and borrow limits during operations
 *      - Track risk violations with events
 *
 *      Architecture:
 *      - Pure library (no state, called via delegatecall from GiveProtocolCore)
 *      - Writes to diamond storage via StorageLib
 *      - Emits events from GiveProtocolCore context
 *      - Enforces risk limits with reverts
 *
 *      Risk Parameters:
 *      - LTV (Loan-to-Value): Maximum borrow ratio relative to collateral (stored, not enforced by this module)
 *      - Liquidation Threshold: Point at which liquidation becomes possible (stored, not enforced by this module)
 *      - Liquidation Penalty: Fee charged during liquidation (stored, not enforced by this module)
 *      - Deposit/Borrow Cap Percentages: Stored as depositCapBps/borrowCapBps but NOT enforced by this module
 *      - Max Deposit/Borrow: Absolute amount limits enforced by enforceDepositLimit() and enforceBorrowLimit()
 *
 *      Security Model:
 *      - Only GiveProtocolCore should call these functions
 *      - MANAGER_ROLE required in calling contract
 *      - Risk ID must be unique (handled by caller)
 *      - Parameter validation ensures safe risk configuration
 *
 *      Use Cases:
 *      - Create risk profile → configure()
 *      - Assign profile to vault → assignVaultRisk()
 *      - Enforce limits during deposit → enforceDepositLimit()
 *      - Enforce limits during borrow → enforceBorrowLimit()
 */
library RiskModule {
    // ============================================
    // CONSTANTS
    // ============================================

    /// @notice Role required to manage risk configurations
    bytes32 public constant MANAGER_ROLE = keccak256("RISK_MODULE_MANAGER_ROLE");

    /// @dev Limit type identifier for deposit limits
    uint8 internal constant LIMIT_DEPOSIT = 1;
    /// @dev Limit type identifier for borrow limits
    uint8 internal constant LIMIT_BORROW = 2;

    /// @dev Validation error: Liquidation threshold exceeds 100%
    uint8 internal constant REASON_INVALID_THRESHOLD = 1;
    /// @dev Validation error: LTV exceeds liquidation threshold
    uint8 internal constant REASON_LTV_ABOVE_THRESHOLD = 2;
    /// @dev Validation error: Liquidation penalty exceeds 50%
    uint8 internal constant REASON_INVALID_PENALTY = 3;
    /// @dev Validation error: Cap percentages invalid
    uint8 internal constant REASON_INVALID_CAPS = 4;
    /// @dev Validation error: Max deposit/borrow amounts invalid
    uint8 internal constant REASON_INVALID_MAXES = 5;
    /// @dev Validation error: Configuration ID mismatch
    uint8 internal constant REASON_ID_MISMATCH = 6;

    // ============================================
    // STRUCTS
    // ============================================

    /**
     * @notice Input parameters for risk configuration
     * @param id Unique identifier for the risk profile
     * @param ltvBps Loan-to-value ratio in basis points (max 10000) - stored but not enforced by this module
     * @param liquidationThresholdBps Threshold for liquidation in basis points - stored but not enforced by this module
     * @param liquidationPenaltyBps Penalty charged on liquidation in basis points - stored but not enforced by this module
     * @param borrowCapBps Borrow capacity as % of deposits in basis points - stored but NOT consumed by enforcement functions
     * @param depositCapBps Deposit capacity limit in basis points - stored but NOT consumed by enforcement functions
     * @param dataHash IPFS/Arweave hash for additional risk metadata
     * @param maxDeposit Absolute maximum deposit amount - enforced by enforceDepositLimit()
     * @param maxBorrow Absolute maximum borrow amount - enforced by enforceBorrowLimit()
     */
    struct RiskConfigInput {
        bytes32 id;
        uint16 ltvBps;
        uint16 liquidationThresholdBps;
        uint16 liquidationPenaltyBps;
        uint16 borrowCapBps;
        uint16 depositCapBps;
        bytes32 dataHash;
        uint256 maxDeposit;
        uint256 maxBorrow;
    }

    // ============================================
    // EVENTS
    // ============================================

    /**
     * @notice Emitted when a risk profile is configured
     * @param id Unique risk profile identifier
     * @param version Risk configuration version number
     * @param ltvBps Loan-to-value ratio in basis points
     * @param liquidationThresholdBps Liquidation threshold in basis points
     * @param maxDeposit Maximum deposit amount
     * @param maxBorrow Maximum borrow amount
     */
    event RiskConfigured(
        bytes32 indexed id,
        uint64 version,
        uint16 ltvBps,
        uint16 liquidationThresholdBps,
        uint256 maxDeposit,
        uint256 maxBorrow
    );

    /**
     * @notice Emitted when a risk profile is assigned to a vault
     * @param vaultId Vault identifier
     * @param riskId Risk profile identifier
     */
    event VaultRiskAssigned(bytes32 indexed vaultId, bytes32 indexed riskId);

    /**
     * @notice Emitted when a risk limit is breached
     * @param vaultId Vault identifier
     * @param riskId Risk profile identifier
     * @param limitType Type of limit breached (1=deposit, 2=borrow)
     * @param currentValue Actual value that breached the limit
     * @param maxAllowed Maximum allowed value
     */
    event RiskLimitBreached(
        bytes32 indexed vaultId, bytes32 indexed riskId, uint8 limitType, uint256 currentValue, uint256 maxAllowed
    );

    // ============================================
    // ERRORS
    // ============================================

    /**
     * @notice Invalid risk parameters provided
     * @param riskId Risk profile identifier
     * @param reason Error reason code (see REASON_* constants)
     */
    error InvalidRiskParameters(bytes32 riskId, uint8 reason);

    /**
     * @notice Risk limit exceeded during operation
     * @param riskId Risk profile identifier
     * @param vaultId Vault identifier
     * @param limitType Type of limit exceeded (1=deposit, 2=borrow)
     * @param actualValue Actual value
     * @param maxAllowed Maximum allowed value
     */
    error RiskLimitExceeded(bytes32 riskId, bytes32 vaultId, uint8 limitType, uint256 actualValue, uint256 maxAllowed);

    // ============================================
    // FUNCTIONS
    // ============================================

    /**
     * @notice Configures a risk profile in protocol storage
     * @dev Writes risk configuration to diamond storage.
     *      Validates all parameters before writing.
     *      Creates new risk profile or updates existing one (increments version).
     * @param riskId Unique identifier for the risk profile
     * @param cfg Risk configuration parameters
     */
    function configure(bytes32 riskId, RiskConfigInput memory cfg) internal {
        if (cfg.id != riskId) revert InvalidRiskParameters(riskId, REASON_ID_MISMATCH);
        _validateConfig(riskId, cfg);

        GiveTypes.RiskConfig storage info = StorageLib.riskConfig(riskId);
        if (!info.exists) {
            info.id = riskId;
            info.createdAt = uint64(block.timestamp);
            info.version = 1;
        } else {
            info.version += 1;
        }
        info.updatedAt = uint64(block.timestamp);
        info.ltvBps = cfg.ltvBps;
        info.liquidationThresholdBps = cfg.liquidationThresholdBps;
        info.liquidationPenaltyBps = cfg.liquidationPenaltyBps;
        info.borrowCapBps = cfg.borrowCapBps;
        info.depositCapBps = cfg.depositCapBps;
        info.dataHash = cfg.dataHash;
        info.maxDeposit = cfg.maxDeposit;
        info.maxBorrow = cfg.maxBorrow;
        info.exists = true;
        info.active = true;

        emit RiskConfigured(
            riskId, info.version, cfg.ltvBps, cfg.liquidationThresholdBps, cfg.maxDeposit, cfg.maxBorrow
        );
    }

    /**
     * @notice Assigns a risk profile to a vault
     * @dev Updates vault configuration with risk profile limits.
     *      Syncs absolute maxDeposit and maxBorrow amounts from risk config to vault.
     *      Note: depositCapBps/borrowCapBps percentages are NOT synced or used.
     * @param vaultId Unique identifier for the vault
     * @param riskId Unique identifier for the risk profile
     */
    function assignVaultRisk(bytes32 vaultId, bytes32 riskId) internal {
        GiveTypes.VaultConfig storage vault = StorageLib.ensureVaultActive(vaultId);
        GiveTypes.RiskConfig storage risk = StorageLib.ensureRiskConfig(riskId);
        vault.riskId = riskId;
        vault.maxVaultDeposit = risk.maxDeposit;
        vault.maxVaultBorrow = risk.maxBorrow;
        emit VaultRiskAssigned(vaultId, riskId);
    }

    /**
     * @notice Enforces deposit limit for a vault
     * @dev Reverts if total assets would exceed absolute maxVaultDeposit limit.
     *      Uses vault.maxVaultDeposit (absolute amount), NOT depositCapBps percentages.
     *      Emits RiskLimitBreached event before reverting.
     *      Does nothing if limit is 0 (unlimited).
     * @param vaultId Unique identifier for the vault
     * @param currentAssets Current asset amount in vault
     * @param incomingAssets New assets being deposited
     */
    function enforceDepositLimit(bytes32 vaultId, uint256 currentAssets, uint256 incomingAssets) internal {
        GiveTypes.VaultConfig storage vault = StorageLib.ensureVaultActive(vaultId);
        uint256 limit = vault.maxVaultDeposit;
        if (limit == 0) return;

        bytes32 riskId = vault.riskId;

        uint256 nextAssets = currentAssets + incomingAssets;
        if (nextAssets > limit) {
            emit RiskLimitBreached(vaultId, riskId, LIMIT_DEPOSIT, nextAssets, limit);
            revert RiskLimitExceeded(riskId, vaultId, LIMIT_DEPOSIT, nextAssets, limit);
        }
    }

    /**
     * @notice Enforces borrow limit for a vault
     * @dev Reverts if projected borrow would exceed absolute maxVaultBorrow limit.
     *      Uses vault.maxVaultBorrow (absolute amount), NOT borrowCapBps percentages.
     *      Emits RiskLimitBreached event before reverting.
     *      Does nothing if limit is 0 (unlimited).
     * @param vaultId Unique identifier for the vault
     * @param projectedBorrow Projected borrow amount after operation
     */
    function enforceBorrowLimit(bytes32 vaultId, uint256 projectedBorrow) internal {
        GiveTypes.VaultConfig storage vault = StorageLib.ensureVaultActive(vaultId);
        uint256 limit = vault.maxVaultBorrow;
        if (limit == 0) return;

        bytes32 riskId = vault.riskId;

        if (projectedBorrow > limit) {
            emit RiskLimitBreached(vaultId, riskId, LIMIT_BORROW, projectedBorrow, limit);
            revert RiskLimitExceeded(riskId, vaultId, LIMIT_BORROW, projectedBorrow, limit);
        }
    }

    /**
     * @notice Validates risk configuration parameters
     * @dev Internal validation function called before storing configuration.
     *      Checks all parameter constraints:
     *      - Liquidation threshold ≤ 100%
     *      - LTV ≤ liquidation threshold
     *      - Liquidation penalty ≤ 50%
     *      - Caps ≤ 100% and borrow cap ≤ deposit cap
     *      - Max deposit > 0 and max borrow ≤ max deposit
     * @param riskId Unique identifier for the risk profile
     * @param cfg Risk configuration parameters to validate
     */
    function _validateConfig(bytes32 riskId, RiskConfigInput memory cfg) private pure {
        if (cfg.liquidationThresholdBps > 10_000) revert InvalidRiskParameters(riskId, REASON_INVALID_THRESHOLD);
        if (cfg.ltvBps > cfg.liquidationThresholdBps) revert InvalidRiskParameters(riskId, REASON_LTV_ABOVE_THRESHOLD);
        if (cfg.liquidationPenaltyBps > 5_000) revert InvalidRiskParameters(riskId, REASON_INVALID_PENALTY);
        if (cfg.depositCapBps > 10_000 || cfg.borrowCapBps > 10_000 || cfg.borrowCapBps > cfg.depositCapBps) {
            revert InvalidRiskParameters(riskId, REASON_INVALID_CAPS);
        }
        if (cfg.maxDeposit == 0 || cfg.maxBorrow > cfg.maxDeposit) {
            revert InvalidRiskParameters(riskId, REASON_INVALID_MAXES);
        }
    }
}
