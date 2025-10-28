// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../types/GiveTypes.sol";

/**
 * @title GiveStorage
 * @author GIVE Labs
 * @notice Anchors the single shared storage struct used across the GIVE Protocol
 * @dev Uses Diamond Storage pattern with deterministic slot calculation to prevent
 *      storage collisions in upgradeable contracts. All protocol state is accessed
 *      through this single storage root.
 *
 *      Storage Layout Security:
 *      - SystemConfig: Fixed-size struct with 50-slot __gap (slots 0-56)
 *      - __gapAfterSystem: 50 additional slots to prevent collision (slots 57-106)
 *      - All mappings: Dynamic storage using keccak256(key, slot) - inherently isolated
 *      - State structs (ngoRegistry, payoutRouter): Contain mappings, documented for safety
 *
 *      Upgrade Safety Rules:
 *      1. NEVER reorder existing fields
 *      2. NEVER change field types
 *      3. NEVER remove fields (deprecate with comments instead)
 *      4. Always append new fields at the end
 *      5. Decrease gap size when adding fields to structs with gaps
 *      6. Mappings can be added freely (they don't affect layout of other fields)
 */
library GiveStorage {
    /**
     * @notice Storage slot for the protocol's shared state
     * @dev Calculated as keccak256("give.protocol.storage")
     *      This deterministic slot ensures no collision with standard storage
     */
    bytes32 internal constant STORAGE_SLOT = 0x9278f57ecbe047283e665e9a2fb0980ac932c01a01f401ad491194769d990f62;

    /**
     * @notice Root storage struct for the entire GIVE Protocol
     * @dev Contains all protocol state organized by functionality
     *
     *      Layout Overview:
     *      - Fixed-size configuration (slots 0-106)
     *      - Dynamic mappings (keccak256-based slots, inherently isolated)
     *
     *      Each mapping entry that points to a struct with a storage gap
     *      provides future upgradeability for that specific entry.
     */
    struct Store {
        // ============================================
        // FIXED-SIZE CONFIGURATION (Slots 0-106)
        // ============================================

        /**
         * @notice Global system configuration
         * @dev Contains 50-slot internal gap, occupies slots 0-56
         */
        GiveTypes.SystemConfig system;

        /**
         * @notice Storage gap after system configuration
         * @dev Protects against collision between SystemConfig and mappings.
         *      If SystemConfig adds fields (consuming its internal gap slots),
         *      this gap remains intact to prevent overflow into mapping territory.
         *      Occupies slots 57-106.
         */
        uint256[50] __gapAfterSystem;

        // ============================================
        // DYNAMIC MAPPINGS (keccak256-based slots)
        // ============================================
        // All mappings below use dynamic slot calculation via keccak256(key, baseSlot).
        // This makes them inherently isolated from each other and from fixed-size fields.

        // --- Core Protocol Mappings ---

        /**
         * @notice Vault configurations indexed by vault ID
         * @dev Each VaultConfig has a 50-slot internal gap for upgradeability
         */
        mapping(bytes32 => GiveTypes.VaultConfig) vaults;

        /**
         * @notice Asset configurations indexed by asset ID
         * @dev Each AssetConfig has a 50-slot internal gap for upgradeability
         */
        mapping(bytes32 => GiveTypes.AssetConfig) assets;

        /**
         * @notice Adapter configurations indexed by adapter ID
         * @dev Each AdapterConfig has a 50-slot internal gap for upgradeability
         */
        mapping(bytes32 => GiveTypes.AdapterConfig) adapters;

        /**
         * @notice Risk configurations indexed by risk ID
         * @dev Each RiskConfig has a 50-slot internal gap for upgradeability
         */
        mapping(bytes32 => GiveTypes.RiskConfig) riskConfigs;

        /**
         * @notice Position states indexed by position ID
         * @dev Each PositionState has a 50-slot internal gap for upgradeability
         */
        mapping(bytes32 => GiveTypes.PositionState) positions;

        /**
         * @notice Role assignments indexed by role ID
         * @dev Contains nested mappings, cannot have storage gap
         */
        mapping(bytes32 => GiveTypes.RoleAssignments) roles;

        /**
         * @notice Synthetic asset states indexed by synthetic ID
         * @dev Contains nested mappings, cannot have storage gap
         */
        mapping(bytes32 => GiveTypes.SyntheticAsset) synthetics;

        // --- Registry State Structs ---

        /**
         * @notice NGO registry state
         * @dev Contains nested mappings and arrays, cannot have storage gap
         */
        GiveTypes.NGORegistryState ngoRegistry;

        /**
         * @notice Payout router state for campaign-based distributions
         * @dev Contains nested mappings and arrays, cannot have storage gap
         */
        GiveTypes.PayoutRouterState payoutRouter;

        // --- Campaign & Strategy Mappings ---

        /**
         * @notice Strategy configurations indexed by strategy ID
         * @dev Each StrategyConfig has a 50-slot internal gap for upgradeability
         */
        mapping(bytes32 => GiveTypes.StrategyConfig) strategies;

        /**
         * @notice Campaign configurations indexed by campaign ID
         * @dev Each CampaignConfig has a 50-slot internal gap for upgradeability
         */
        mapping(bytes32 => GiveTypes.CampaignConfig) campaigns;

        /**
         * @notice Campaign stake states indexed by campaign ID
         * @dev Contains nested mappings for supporter stakes, cannot have storage gap
         */
        mapping(bytes32 => GiveTypes.CampaignStakeState) campaignStakes;

        /**
         * @notice Campaign checkpoint states indexed by campaign ID
         * @dev Contains nested mappings for voting data, cannot have storage gap
         */
        mapping(bytes32 => GiveTypes.CampaignCheckpointState) campaignCheckpoints;

        /**
         * @notice Campaign vault metadata indexed by vault ID
         * @dev Each CampaignVaultMeta has a 50-slot internal gap for upgradeability
         */
        mapping(bytes32 => GiveTypes.CampaignVaultMeta) campaignVaults;

        // --- Helper Mappings for Enumeration & Lookup ---

        /**
         * @notice Maps strategy IDs to arrays of vault addresses using that strategy
         * @dev Used to track strategy reusability across multiple campaigns
         */
        mapping(bytes32 => address[]) strategyVaults;

        /**
         * @notice Maps vault addresses to their associated campaign IDs
         * @dev Used for quick vault-to-campaign lookups
         */
        mapping(address => bytes32) vaultCampaignLookup;

        // --- Generic Registries for Extensibility ---

        /**
         * @notice Generic bytes32 registry for dynamic key-value storage
         * @dev Used for extensibility without schema changes
         */
        mapping(bytes32 => bytes32) bytes32Registry;

        /**
         * @notice Generic uint256 registry for dynamic key-value storage
         * @dev Used for extensibility without schema changes
         */
        mapping(bytes32 => uint256) uintRegistry;

        /**
         * @notice Generic address registry for dynamic key-value storage
         * @dev Used for extensibility without schema changes
         */
        mapping(bytes32 => address) addressRegistry;

        /**
         * @notice Generic bool registry for dynamic key-value storage
         * @dev Used for extensibility without schema changes
         */
        mapping(bytes32 => bool) boolRegistry;
        // ============================================
        // FUTURE FIELDS
        // ============================================
        // New fields can be added below this line:
        // - Mappings are always safe to append
        // - For fixed-size fields, add a new gap and document consumed slots
    }

    /**
     * @notice Returns the storage pointer for the shared store
     * @dev Uses inline assembly to set the storage slot to the deterministic location
     * @return s Storage pointer to the root Store struct
     */
    function store() internal pure returns (Store storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }
}
