// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./GiveStorage.sol";
import "../types/GiveTypes.sol";

/**
 * @title StorageLib
 * @author GIVE Labs
 * @notice Convenience helpers for reading and writing the shared storage struct
 * @dev Provides type-safe accessors to the protocol's Diamond Storage pattern.
 *      All contracts should use these functions instead of directly accessing storage
 *      to ensure consistency and prevent storage slot collisions.
 */
library StorageLib {
    // ============================================
    // ERRORS
    // ============================================

    error StorageNotInitialized();
    error InvalidVault(bytes32 vaultId);
    error InvalidAdapter(bytes32 adapterId);
    error InvalidRisk(bytes32 riskId);
    error InvalidStrategy(bytes32 strategyId);
    error InvalidCampaign(bytes32 campaignId);
    error InvalidCampaignVault(bytes32 vaultId);
    error InvalidRole(bytes32 roleId);

    // ============================================
    // CORE ACCESSORS
    // ============================================

    /**
     * @notice Returns the root storage struct
     * @dev All storage is accessed through this single entry point
     * @return s The root storage struct
     */
    function root() internal pure returns (GiveStorage.Store storage s) {
        return GiveStorage.store();
    }

    /**
     * @notice Returns the system configuration storage
     * @dev Uses inline assembly to directly access the first slot of Store
     * @return cfg System configuration storage reference
     */
    function system() internal pure returns (GiveTypes.SystemConfig storage cfg) {
        GiveStorage.Store storage s = GiveStorage.store();
        assembly {
            cfg.slot := s.slot
        }
    }

    // ============================================
    // VAULT ACCESSORS
    // ============================================

    /**
     * @notice Returns vault configuration for a given vault ID
     * @dev Does not validate existence - use ensureVaultActive for validation
     * @param vaultId The unique vault identifier
     * @return cfg Vault configuration storage reference
     */
    function vault(bytes32 vaultId) internal view returns (GiveTypes.VaultConfig storage cfg) {
        GiveStorage.Store storage s = GiveStorage.store();
        cfg = s.vaults[vaultId];
    }

    /**
     * @notice Returns vault configuration and validates it is active
     * @dev Reverts if vault does not exist or is not active
     * @param vaultId The unique vault identifier
     * @return cfg Vault configuration storage reference
     */
    function ensureVaultActive(bytes32 vaultId) internal view returns (GiveTypes.VaultConfig storage cfg) {
        cfg = vault(vaultId);
        if (cfg.proxy == address(0)) revert InvalidVault(vaultId);
        if (!cfg.active) revert InvalidVault(vaultId);
    }

    /**
     * @notice Returns campaign vault metadata for a given vault ID
     * @dev Does not validate existence - use ensureCampaignVault for validation
     * @param vaultId The unique vault identifier
     * @return meta Campaign vault metadata storage reference
     */
    function campaignVaultMeta(bytes32 vaultId) internal view returns (GiveTypes.CampaignVaultMeta storage meta) {
        GiveStorage.Store storage s = GiveStorage.store();
        meta = s.campaignVaults[vaultId];
    }

    /**
     * @notice Returns campaign vault metadata and validates existence
     * @dev Reverts if vault metadata does not exist
     * @param vaultId The unique vault identifier
     * @return meta Campaign vault metadata storage reference
     */
    function ensureCampaignVault(bytes32 vaultId) internal view returns (GiveTypes.CampaignVaultMeta storage meta) {
        meta = campaignVaultMeta(vaultId);
        if (!meta.exists) revert InvalidCampaignVault(vaultId);
    }

    /**
     * @notice Sets the campaign ID for a vault address
     * @dev Used to map vault addresses to their campaign IDs
     * @param vaultAddress The vault contract address
     * @param campaignId The campaign identifier
     */
    function setVaultCampaign(address vaultAddress, bytes32 campaignId) internal {
        GiveStorage.store().vaultCampaignLookup[vaultAddress] = campaignId;
    }

    /**
     * @notice Gets the campaign ID for a vault address
     * @dev Returns bytes32(0) if no campaign is associated
     * @param vaultAddress The vault contract address
     * @return Campaign identifier
     */
    function getVaultCampaign(address vaultAddress) internal view returns (bytes32) {
        return GiveStorage.store().vaultCampaignLookup[vaultAddress];
    }

    // ============================================
    // ADAPTER ACCESSORS
    // ============================================

    /**
     * @notice Returns adapter configuration for a given adapter ID
     * @dev Does not validate existence - use ensureAdapterActive for validation
     * @param adapterId The unique adapter identifier
     * @return cfg Adapter configuration storage reference
     */
    function adapter(bytes32 adapterId) internal view returns (GiveTypes.AdapterConfig storage cfg) {
        GiveStorage.Store storage s = GiveStorage.store();
        cfg = s.adapters[adapterId];
    }

    /**
     * @notice Returns adapter configuration and validates it is active
     * @dev Reverts if adapter does not exist or is not active
     * @param adapterId The unique adapter identifier
     * @return cfg Adapter configuration storage reference
     */
    function ensureAdapterActive(bytes32 adapterId) internal view returns (GiveTypes.AdapterConfig storage cfg) {
        cfg = adapter(adapterId);
        if (cfg.proxy == address(0) || !cfg.active) {
            revert InvalidAdapter(adapterId);
        }
    }

    // ============================================
    // ASSET ACCESSORS
    // ============================================

    /**
     * @notice Returns asset configuration for a given asset ID
     * @dev Does not validate existence
     * @param assetId The unique asset identifier
     * @return cfg Asset configuration storage reference
     */
    function asset(bytes32 assetId) internal view returns (GiveTypes.AssetConfig storage cfg) {
        GiveStorage.Store storage s = GiveStorage.store();
        cfg = s.assets[assetId];
    }

    // ============================================
    // RISK CONFIGURATION ACCESSORS
    // ============================================

    /**
     * @notice Returns risk configuration for a given risk ID
     * @dev Does not validate existence - use ensureRiskConfig for validation
     * @param riskId The unique risk configuration identifier
     * @return cfg Risk configuration storage reference
     */
    function riskConfig(bytes32 riskId) internal view returns (GiveTypes.RiskConfig storage cfg) {
        GiveStorage.Store storage s = GiveStorage.store();
        cfg = s.riskConfigs[riskId];
    }

    /**
     * @notice Returns risk configuration and validates existence
     * @dev Reverts if risk configuration does not exist
     * @param riskId The unique risk configuration identifier
     * @return cfg Risk configuration storage reference
     */
    function ensureRiskConfig(bytes32 riskId) internal view returns (GiveTypes.RiskConfig storage cfg) {
        cfg = riskConfig(riskId);
        if (!cfg.exists) revert InvalidRisk(riskId);
    }

    // ============================================
    // POSITION ACCESSORS
    // ============================================

    /**
     * @notice Returns position state for a given position ID
     * @dev Does not validate existence
     * @param positionId The unique position identifier
     * @return state Position state storage reference
     */
    function position(bytes32 positionId) internal view returns (GiveTypes.PositionState storage state) {
        GiveStorage.Store storage s = GiveStorage.store();
        state = s.positions[positionId];
    }

    // ============================================
    // STRATEGY ACCESSORS
    // ============================================

    /**
     * @notice Returns strategy configuration for a given strategy ID
     * @dev Does not validate existence - use ensureStrategy for validation
     * @param strategyId The unique strategy identifier
     * @return cfg Strategy configuration storage reference
     */
    function strategy(bytes32 strategyId) internal view returns (GiveTypes.StrategyConfig storage cfg) {
        GiveStorage.Store storage s = GiveStorage.store();
        cfg = s.strategies[strategyId];
    }

    /**
     * @notice Returns strategy configuration and validates existence
     * @dev Reverts if strategy does not exist
     * @param strategyId The unique strategy identifier
     * @return cfg Strategy configuration storage reference
     */
    function ensureStrategy(bytes32 strategyId) internal view returns (GiveTypes.StrategyConfig storage cfg) {
        cfg = strategy(strategyId);
        if (!cfg.exists) revert InvalidStrategy(strategyId);
    }

    /**
     * @notice Returns the list of vault addresses using a strategy
     * @dev Used to track strategy reusability across multiple campaigns
     * @param strategyId The unique strategy identifier
     * @return list Array of vault addresses using this strategy
     */
    function strategyVaults(bytes32 strategyId) internal view returns (address[] storage list) {
        GiveStorage.Store storage s = GiveStorage.store();
        return s.strategyVaults[strategyId];
    }

    // ============================================
    // CAMPAIGN ACCESSORS
    // ============================================

    /**
     * @notice Returns campaign configuration for a given campaign ID
     * @dev Does not validate existence - use ensureCampaign for validation
     * @param campaignId The unique campaign identifier
     * @return cfg Campaign configuration storage reference
     */
    function campaign(bytes32 campaignId) internal view returns (GiveTypes.CampaignConfig storage cfg) {
        GiveStorage.Store storage s = GiveStorage.store();
        cfg = s.campaigns[campaignId];
    }

    /**
     * @notice Returns campaign configuration and validates existence
     * @dev Reverts if campaign does not exist
     * @param campaignId The unique campaign identifier
     * @return cfg Campaign configuration storage reference
     */
    function ensureCampaign(bytes32 campaignId) internal view returns (GiveTypes.CampaignConfig storage cfg) {
        cfg = campaign(campaignId);
        if (!cfg.exists) revert InvalidCampaign(campaignId);
    }

    /**
     * @notice Returns campaign stake state for supporters
     * @dev Contains aggregated stake information and supporter mappings
     * @param campaignId The unique campaign identifier
     * @return stakeState Campaign stake state storage reference
     */
    function campaignStake(bytes32 campaignId) internal view returns (GiveTypes.CampaignStakeState storage stakeState) {
        GiveStorage.Store storage s = GiveStorage.store();
        stakeState = s.campaignStakes[campaignId];
    }

    /**
     * @notice Returns campaign checkpoint state for voting
     * @dev Contains all checkpoints and voting data for a campaign
     * @param campaignId The unique campaign identifier
     * @return checkpointState Campaign checkpoint state storage reference
     */
    function campaignCheckpoints(bytes32 campaignId)
        internal
        view
        returns (GiveTypes.CampaignCheckpointState storage checkpointState)
    {
        GiveStorage.Store storage s = GiveStorage.store();
        checkpointState = s.campaignCheckpoints[campaignId];
    }

    // ============================================
    // NGO REGISTRY ACCESSORS
    // ============================================

    /**
     * @notice Returns the NGO registry state
     * @dev Contains approved NGOs and their metadata
     * @return state NGO registry state storage reference
     */
    function ngoRegistry() internal view returns (GiveTypes.NGORegistryState storage state) {
        GiveStorage.Store storage s = GiveStorage.store();
        state = s.ngoRegistry;
    }

    // ============================================
    // PAYOUT ROUTER ACCESSORS
    // ============================================

    /**
     * @notice Returns the payout router state
     * @dev Contains campaign payout distribution configuration and tracking
     * @return state Payout router state storage reference
     */
    function payoutRouter() internal view returns (GiveTypes.PayoutRouterState storage state) {
        GiveStorage.Store storage s = GiveStorage.store();
        state = s.payoutRouter;
    }

    // ============================================
    // SYNTHETIC ASSET ACCESSORS
    // ============================================

    /**
     * @notice Returns synthetic asset state
     * @dev Used for synthetic asset functionality (optional feature)
     * @param syntheticId The unique synthetic asset identifier
     * @return synthetic Synthetic asset storage reference
     */
    function syntheticState(bytes32 syntheticId) internal view returns (GiveTypes.SyntheticAsset storage synthetic) {
        GiveStorage.Store storage s = GiveStorage.store();
        synthetic = s.synthetics[syntheticId];
    }

    // ============================================
    // ROLE ACCESSORS
    // ============================================

    /**
     * @notice Returns role assignment data
     * @dev Does not validate existence - use ensureRole for validation
     * @param roleId The unique role identifier
     * @return assignment Role assignment storage reference
     */
    function role(bytes32 roleId) internal view returns (GiveTypes.RoleAssignments storage assignment) {
        GiveStorage.Store storage s = GiveStorage.store();
        assignment = s.roles[roleId];
    }

    /**
     * @notice Returns role assignment data and validates existence
     * @dev Reverts if role does not exist
     * @param roleId The unique role identifier
     * @return assignment Role assignment storage reference
     */
    function ensureRole(bytes32 roleId) internal view returns (GiveTypes.RoleAssignments storage assignment) {
        assignment = role(roleId);
        if (!assignment.exists) revert InvalidRole(roleId);
    }

    // ============================================
    // VALIDATION HELPERS
    // ============================================

    /**
     * @notice Validates that the storage has been initialized
     * @dev Reverts if system has not been initialized via bootstrap
     */
    function ensureInitialized() internal view {
        if (!system().initialized) revert StorageNotInitialized();
    }

    // ============================================
    // GENERIC REGISTRY HELPERS
    // ============================================

    /**
     * @notice Sets an address value in the generic registry
     * @dev Used for dynamic address lookups not in typed structs
     * @param key The registry key
     * @param value The address value to store
     */
    function setAddress(bytes32 key, address value) internal {
        GiveStorage.store().addressRegistry[key] = value;
    }

    /**
     * @notice Gets an address value from the generic registry
     * @dev Returns address(0) if key does not exist
     * @param key The registry key
     * @return value The stored address value
     */
    function getAddress(bytes32 key) internal view returns (address value) {
        return GiveStorage.store().addressRegistry[key];
    }

    /**
     * @notice Sets a uint256 value in the generic registry
     * @dev Used for dynamic uint lookups not in typed structs
     * @param key The registry key
     * @param value The uint256 value to store
     */
    function setUint(bytes32 key, uint256 value) internal {
        GiveStorage.store().uintRegistry[key] = value;
    }

    /**
     * @notice Gets a uint256 value from the generic registry
     * @dev Returns 0 if key does not exist
     * @param key The registry key
     * @return value The stored uint256 value
     */
    function getUint(bytes32 key) internal view returns (uint256 value) {
        return GiveStorage.store().uintRegistry[key];
    }

    /**
     * @notice Sets a bool value in the generic registry
     * @dev Used for dynamic bool lookups not in typed structs
     * @param key The registry key
     * @param value The bool value to store
     */
    function setBool(bytes32 key, bool value) internal {
        GiveStorage.store().boolRegistry[key] = value;
    }

    /**
     * @notice Gets a bool value from the generic registry
     * @dev Returns false if key does not exist
     * @param key The registry key
     * @return value The stored bool value
     */
    function getBool(bytes32 key) internal view returns (bool value) {
        return GiveStorage.store().boolRegistry[key];
    }

    /**
     * @notice Sets a bytes32 value in the generic registry
     * @dev Used for dynamic bytes32 lookups not in typed structs
     * @param key The registry key
     * @param value The bytes32 value to store
     */
    function setBytes32(bytes32 key, bytes32 value) internal {
        GiveStorage.store().bytes32Registry[key] = value;
    }

    /**
     * @notice Gets a bytes32 value from the generic registry
     * @dev Returns bytes32(0) if key does not exist
     * @param key The registry key
     * @return value The stored bytes32 value
     */
    function getBytes32(bytes32 key) internal view returns (bytes32 value) {
        return GiveStorage.store().bytes32Registry[key];
    }
}
