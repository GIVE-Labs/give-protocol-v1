// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../storage/StorageLib.sol";
import "../types/GiveTypes.sol";

library RiskModule {
    bytes32 public constant MANAGER_ROLE = keccak256("RISK_MODULE_MANAGER_ROLE");

    uint8 internal constant LIMIT_DEPOSIT = 1;
    uint8 internal constant LIMIT_BORROW = 2;

    uint8 internal constant REASON_INVALID_THRESHOLD = 1;
    uint8 internal constant REASON_LTV_ABOVE_THRESHOLD = 2;
    uint8 internal constant REASON_INVALID_PENALTY = 3;
    uint8 internal constant REASON_INVALID_CAPS = 4;
    uint8 internal constant REASON_INVALID_MAXES = 5;
    uint8 internal constant REASON_ID_MISMATCH = 6;

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

    event RiskConfigured(
        bytes32 indexed id,
        uint64 version,
        uint16 ltvBps,
        uint16 liquidationThresholdBps,
        uint256 maxDeposit,
        uint256 maxBorrow
    );

    event VaultRiskAssigned(bytes32 indexed vaultId, bytes32 indexed riskId);

    event RiskLimitBreached(
        bytes32 indexed vaultId, bytes32 indexed riskId, uint8 limitType, uint256 currentValue, uint256 maxAllowed
    );

    error InvalidRiskParameters(bytes32 riskId, uint8 reason);
    error RiskLimitExceeded(bytes32 riskId, bytes32 vaultId, uint8 limitType, uint256 actualValue, uint256 maxAllowed);

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

    function assignVaultRisk(bytes32 vaultId, bytes32 riskId) internal {
        GiveTypes.VaultConfig storage vault = StorageLib.ensureVaultActive(vaultId);
        GiveTypes.RiskConfig storage risk = StorageLib.ensureRiskConfig(riskId);
        vault.riskId = riskId;
        vault.maxVaultDeposit = risk.maxDeposit;
        vault.maxVaultBorrow = risk.maxBorrow;
        emit VaultRiskAssigned(vaultId, riskId);
    }

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
