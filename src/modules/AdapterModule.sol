// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../storage/StorageLib.sol";
import "../types/GiveTypes.sol";

/**
 * @title AdapterModule
 * @author GIVE Labs
 * @notice Library module for yield adapter configuration and management
 * @dev Provides functions to register and configure yield adapters in protocol storage.
 *      Used by GiveProtocolCore to track adapter instances and their properties.
 *
 *      Key Responsibilities:
 *      - Register adapter proxy and implementation addresses
 *      - Bind adapters to assets and vaults
 *      - Track adapter kind (see GiveTypes.AdapterKind enum)
 *      - Store adapter metadata hash for off-chain information
 *
 *      Architecture:
 *      - Pure library (no state, called via delegatecall from GiveProtocolCore)
 *      - Writes to diamond storage via StorageLib
 *      - Emits events from GiveProtocolCore context
 *
 *      Adapter Kinds (from GiveTypes.AdapterKind):
 *      - CompoundingValue: Balance constant, exchange rate accrues (Compound cTokens, wstETH)
 *      - ClaimableYield: Yield must be claimed during harvest (liquidity mining)
 *      - BalanceGrowth: Balance increases automatically (Aave aTokens)
 *      - FixedMaturityToken: Principal/yield tokens with maturity (Pendle PT, Element)
 *
 *      Security Model:
 *      - Only GiveProtocolCore should call these functions
 *      - MANAGER_ROLE required in calling contract
 *      - Adapter ID must be unique (handled by caller)
 *
 *      Use Cases:
 *      - Deploy new Aave adapter → configure()
 *      - Query adapter configuration → StorageLib.adapter()
 *      - Switch vault to different adapter → update vault config (VaultModule)
 */
library AdapterModule {
    // ============================================
    // CONSTANTS
    // ============================================

    /// @notice Role required to manage adapter configurations
    bytes32 public constant MANAGER_ROLE = keccak256("ADAPTER_MODULE_MANAGER_ROLE");

    // ============================================
    // STRUCTS
    // ============================================

    /**
     * @notice Input parameters for adapter configuration
     * @param id Unique identifier for the adapter
     * @param proxy Address of the adapter contract (or proxy if upgradeable)
     * @param implementation Address of the adapter implementation (if proxied)
     * @param asset Underlying asset address this adapter manages
     * @param vault Vault address authorized to use this adapter
     * @param kind Type of adapter (Growth, Compounding, PT, etc.)
     * @param metadataHash IPFS/Arweave hash containing adapter metadata
     */
    struct AdapterConfigInput {
        bytes32 id;
        address proxy;
        address implementation;
        address asset;
        address vault;
        GiveTypes.AdapterKind kind;
        bytes32 metadataHash;
    }

    // ============================================
    // EVENTS
    // ============================================

    /**
     * @notice Emitted when an adapter is configured in the protocol
     * @param id Unique adapter identifier
     * @param proxy Adapter proxy/contract address
     * @param implementation Adapter implementation address
     * @param asset Underlying asset address
     */
    event AdapterConfigured(bytes32 indexed id, address proxy, address implementation, address asset);

    // ============================================
    // FUNCTIONS
    // ============================================

    /**
     * @notice Configures an adapter in protocol storage
     * @dev Writes adapter configuration to diamond storage slot.
     *      Automatically sets adapter as active.
     *      Does not validate addresses or adapter-vault binding - caller must ensure validity.
     * @param adapterId Unique identifier for the adapter
     * @param cfg Adapter configuration parameters
     */
    function configure(bytes32 adapterId, AdapterConfigInput memory cfg) internal {
        GiveTypes.AdapterConfig storage info = StorageLib.adapter(adapterId);
        info.id = adapterId;
        info.proxy = cfg.proxy;
        info.implementation = cfg.implementation;
        info.asset = cfg.asset;
        info.vault = cfg.vault;
        info.kind = cfg.kind;
        info.metadataHash = cfg.metadataHash;
        info.active = true;

        emit AdapterConfigured(adapterId, cfg.proxy, cfg.implementation, cfg.asset);
    }
}
