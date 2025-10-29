// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../interfaces/IACLManager.sol";
import "../storage/StorageLib.sol";
import "../types/GiveTypes.sol";

/**
 * @title StrategyRegistry
 * @author GIVE Labs
 * @notice Canonical registry for protocol yield strategies and their lifecycle state
 * @dev Manages strategy registration, updates, status transitions, and vault associations.
 *      Strategies represent yield-generating approaches (e.g., Aave USDC, Compound DAI) that
 *      vaults can implement via adapters. Each strategy has a lifecycle: Active → FadingOut → Deprecated.
 *
 *      Key Features:
 *      - Dynamic strategy registration by STRATEGY_ADMIN
 *      - Lifecycle management (Active/FadingOut/Deprecated)
 *      - Strategy-vault binding tracking (deduplicated list)
 *      - Risk tier classification
 *      - TVL limits per strategy
 *      - UUPS upgradeability
 *
 *      Vault Tracking:
 *      - Vault list per strategy is deduplicated (no duplicates allowed)
 *      - Use registerStrategyVault() to link a vault to a strategy
 *      - Use unregisterStrategyVault() to unlink a vault from a strategy
 *      - Mapping tracks registration state to prevent duplicates
 *
 *      Security Model:
 *      - Only STRATEGY_ADMIN can register, update, or change strategy status
 *      - Only ROLE_UPGRADER can upgrade contract
 *      - Strategies are reusable across multiple vaults
 *      - Metadata stored off-chain (IPFS hash)
 */
contract StrategyRegistry is Initializable, UUPSUpgradeable {
    // ============================================
    // STATE VARIABLES
    // ============================================

    /**
     * @notice ACL manager for role-based access control
     * @dev All admin operations check roles via this contract
     */
    IACLManager public aclManager;

    /**
     * @notice Role identifier for contract upgrades
     * @dev Must match ACLManager.ROLE_UPGRADER
     */
    bytes32 public constant ROLE_UPGRADER = keccak256("ROLE_UPGRADER");

    /**
     * @notice Enumerable list of all strategy IDs
     * @dev Used for iteration and discovery. Order is insertion order.
     */
    bytes32[] private _strategyIds;

    /**
     * @notice Tracks whether a vault is registered to a strategy
     * @dev Prevents duplicate vault registrations. Maps strategyId => vault => isRegistered.
     */
    mapping(bytes32 => mapping(address => bool)) private _vaultRegistered;

    // ============================================
    // STRUCTS
    // ============================================

    /**
     * @notice Input parameters for strategy registration/update
     * @dev Separate from storage struct to avoid stack-too-deep errors
     */
    struct StrategyInput {
        bytes32 id; // Unique strategy identifier (keccak256 hash)
        address adapter; // Yield adapter implementation address
        bytes32 riskTier; // Risk classification (e.g., "LOW", "MEDIUM", "HIGH")
        uint256 maxTvl; // Maximum total value locked (in asset decimals)
        bytes32 metadataHash; // IPFS hash of strategy metadata (name, description, etc.)
    }

    // ============================================
    // EVENTS
    // ============================================

    /**
     * @notice Emitted when a new strategy is registered
     * @param id Unique strategy identifier
     * @param adapter Yield adapter address
     * @param riskTier Risk classification
     * @param maxTvl Maximum TVL allowed
     * @param metadataHash IPFS metadata hash
     */
    event StrategyRegistered(
        bytes32 indexed id, address indexed adapter, bytes32 riskTier, uint256 maxTvl, bytes32 metadataHash
    );

    /**
     * @notice Emitted when a strategy is updated
     * @param id Strategy identifier
     * @param adapter New adapter address
     * @param riskTier New risk tier
     * @param maxTvl New max TVL
     * @param metadataHash New metadata hash
     */
    event StrategyUpdated(
        bytes32 indexed id, address indexed adapter, bytes32 riskTier, uint256 maxTvl, bytes32 metadataHash
    );

    /**
     * @notice Emitted when a strategy's lifecycle status changes
     * @param id Strategy identifier
     * @param previousStatus Old status
     * @param newStatus New status
     */
    event StrategyStatusChanged(
        bytes32 indexed id, GiveTypes.StrategyStatus previousStatus, GiveTypes.StrategyStatus newStatus
    );

    /**
     * @notice Emitted when a vault is linked to a strategy
     * @param strategyId Strategy identifier
     * @param vault Vault address using this strategy
     */
    event StrategyVaultLinked(bytes32 indexed strategyId, address indexed vault);

    /**
     * @notice Emitted when a vault is unlinked from a strategy
     * @param strategyId Strategy identifier
     * @param vault Vault address removed from this strategy
     */
    event StrategyVaultUnlinked(bytes32 indexed strategyId, address indexed vault);

    // ============================================
    // ERRORS
    // ============================================

    /// @notice Zero address provided where non-zero required
    error ZeroAddress();

    /// @notice Caller lacks required role
    error Unauthorized(bytes32 roleId, address account);

    /// @notice Strategy ID already exists
    error StrategyAlreadyExists(bytes32 id);

    /// @notice Strategy ID not found
    error StrategyNotFound(bytes32 id);

    /// @notice Invalid strategy configuration parameters
    error InvalidStrategyConfig(bytes32 id);

    /// @notice Vault already registered to strategy
    error VaultAlreadyRegistered(bytes32 strategyId, address vault);

    /// @notice Vault not registered to strategy
    error VaultNotRegistered(bytes32 strategyId, address vault);

    // ============================================
    // MODIFIERS
    // ============================================

    /**
     * @notice Restricts access to accounts with specific role
     * @dev Reverts if caller does not have the required role
     * @param roleId The role to check
     */
    modifier onlyRole(bytes32 roleId) {
        if (!aclManager.hasRole(roleId, msg.sender)) {
            revert Unauthorized(roleId, msg.sender);
        }
        _;
    }

    // ============================================
    // INITIALIZATION
    // ============================================

    /**
     * @notice Initializes the strategy registry
     * @dev Only callable once due to initializer modifier.
     *      Sets up ACL manager reference.
     * @param acl Address of ACLManager contract
     */
    function initialize(address acl) external initializer {
        if (acl == address(0)) revert ZeroAddress();
        aclManager = IACLManager(acl);
    }

    // ============================================
    // EXTERNAL FUNCTIONS - STRATEGY MANAGEMENT
    // ============================================

    /**
     * @notice Registers a new yield strategy
     * @dev Only callable by STRATEGY_ADMIN.
     *      Strategy starts in Active status.
     *      Validates non-zero ID, adapter, and maxTvl.
     * @param input Strategy configuration parameters
     */
    function registerStrategy(StrategyInput calldata input) external onlyRole(aclManager.strategyAdminRole()) {
        if (input.id == bytes32(0) || input.adapter == address(0) || input.maxTvl == 0) {
            revert InvalidStrategyConfig(input.id);
        }

        GiveTypes.StrategyConfig storage cfg = StorageLib.strategy(input.id);
        if (cfg.exists) revert StrategyAlreadyExists(input.id);

        cfg.id = input.id;
        cfg.adapter = input.adapter;
        cfg.creator = msg.sender;
        cfg.metadataHash = input.metadataHash;
        cfg.riskTier = input.riskTier;
        cfg.maxTvl = input.maxTvl;
        cfg.createdAt = uint64(block.timestamp);
        cfg.updatedAt = uint64(block.timestamp);
        cfg.status = GiveTypes.StrategyStatus.Active;
        cfg.exists = true;

        _strategyIds.push(input.id);

        emit StrategyRegistered(input.id, input.adapter, input.riskTier, input.maxTvl, input.metadataHash);
    }

    /**
     * @notice Updates an existing strategy's parameters
     * @dev Only callable by STRATEGY_ADMIN.
     *      Cannot change strategy ID or creation timestamp.
     *      Updates adapter, metadata, risk tier, and max TVL.
     * @param input Updated strategy configuration
     */
    function updateStrategy(StrategyInput calldata input) external onlyRole(aclManager.strategyAdminRole()) {
        if (input.id == bytes32(0) || input.adapter == address(0) || input.maxTvl == 0) {
            revert InvalidStrategyConfig(input.id);
        }

        GiveTypes.StrategyConfig storage cfg = StorageLib.strategy(input.id);
        if (!cfg.exists) revert StrategyNotFound(input.id);

        cfg.adapter = input.adapter;
        cfg.metadataHash = input.metadataHash;
        cfg.riskTier = input.riskTier;
        cfg.maxTvl = input.maxTvl;
        cfg.updatedAt = uint64(block.timestamp);

        emit StrategyUpdated(input.id, input.adapter, input.riskTier, input.maxTvl, input.metadataHash);
    }

    /**
     * @notice Updates a strategy's lifecycle status
     * @dev Only callable by STRATEGY_ADMIN.
     *      Typical flow: Active → FadingOut → Deprecated.
     *      - Active: Available for new campaigns
     *      - FadingOut: Existing campaigns continue, new campaigns discouraged (product decision)
     *      - Deprecated: Blocked for new campaigns
     * @param strategyId Strategy identifier
     * @param newStatus New lifecycle status
     */
    function setStrategyStatus(bytes32 strategyId, GiveTypes.StrategyStatus newStatus)
        external
        onlyRole(aclManager.strategyAdminRole())
    {
        if (newStatus == GiveTypes.StrategyStatus.Unknown) {
            revert InvalidStrategyConfig(strategyId);
        }

        GiveTypes.StrategyConfig storage cfg = StorageLib.strategy(strategyId);
        if (!cfg.exists) revert StrategyNotFound(strategyId);

        GiveTypes.StrategyStatus previous = cfg.status;
        if (previous == newStatus) return; // Idempotent

        cfg.status = newStatus;
        cfg.updatedAt = uint64(block.timestamp);

        emit StrategyStatusChanged(strategyId, previous, newStatus);
    }

    /**
     * @notice Links a vault to a strategy
     * @dev Only callable by STRATEGY_ADMIN.
     *      Tracks which vaults are using which strategies.
     *      Same strategy can be used by multiple vaults (reusability).
     *      Prevents duplicate registrations.
     * @param strategyId Strategy identifier
     * @param vault Vault address to link
     */
    function registerStrategyVault(bytes32 strategyId, address vault)
        external
        onlyRole(aclManager.strategyAdminRole())
    {
        if (vault == address(0)) revert ZeroAddress();

        GiveTypes.StrategyConfig storage cfg = StorageLib.strategy(strategyId);
        if (!cfg.exists) revert StrategyNotFound(strategyId);

        // Prevent duplicate registrations
        if (_vaultRegistered[strategyId][vault]) {
            revert VaultAlreadyRegistered(strategyId, vault);
        }

        address[] storage vaults = StorageLib.strategyVaults(strategyId);
        vaults.push(vault);
        _vaultRegistered[strategyId][vault] = true;

        emit StrategyVaultLinked(strategyId, vault);
    }

    /**
     * @notice Unlinks a vault from a strategy
     * @dev Only callable by STRATEGY_ADMIN.
     *      Removes vault from strategy's vault list using swap-and-pop pattern.
     *      Updates tracking mapping to allow future re-registration if needed.
     * @param strategyId Strategy identifier
     * @param vault Vault address to unlink
     */
    function unregisterStrategyVault(bytes32 strategyId, address vault)
        external
        onlyRole(aclManager.strategyAdminRole())
    {
        if (vault == address(0)) revert ZeroAddress();

        GiveTypes.StrategyConfig storage cfg = StorageLib.strategy(strategyId);
        if (!cfg.exists) revert StrategyNotFound(strategyId);

        // Ensure vault is actually registered
        if (!_vaultRegistered[strategyId][vault]) {
            revert VaultNotRegistered(strategyId, vault);
        }

        address[] storage vaults = StorageLib.strategyVaults(strategyId);

        // Find and remove vault using swap-and-pop pattern
        bool removed;
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] == vault) {
                // Swap with last element and pop
                vaults[i] = vaults[vaults.length - 1];
                vaults.pop();
                removed = true;
                break;
            }
        }

        // Ensure removal actually occurred to keep array and mapping in sync
        if (!removed) revert VaultNotRegistered(strategyId, vault);

        // Update tracking mapping
        _vaultRegistered[strategyId][vault] = false;

        emit StrategyVaultUnlinked(strategyId, vault);
    }

    // ============================================
    // EXTERNAL VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Retrieves a strategy's configuration
     * @dev Reverts if strategy does not exist
     * @param strategyId Strategy identifier
     * @return Strategy configuration struct
     */
    function getStrategy(bytes32 strategyId) external view returns (GiveTypes.StrategyConfig memory) {
        GiveTypes.StrategyConfig storage cfg = StorageLib.strategy(strategyId);
        if (!cfg.exists) revert StrategyNotFound(strategyId);
        return cfg;
    }

    /**
     * @notice Returns all registered strategy IDs
     * @dev Useful for UI enumeration and discovery.
     *      Order is insertion order (not sorted).
     * @return Array of strategy identifiers
     */
    function listStrategyIds() external view returns (bytes32[] memory) {
        return _strategyIds;
    }

    /**
     * @notice Returns all vaults using a specific strategy
     * @dev Returns a copy of the storage array to avoid external mutation.
     *      List is deduplicated - each vault appears at most once.
     * @param strategyId Strategy identifier
     * @return Array of vault addresses
     */
    function getStrategyVaults(bytes32 strategyId) external view returns (address[] memory) {
        address[] storage vaults = StorageLib.strategyVaults(strategyId);
        address[] memory copy = new address[](vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            copy[i] = vaults[i];
        }
        return copy;
    }

    // ============================================
    // UUPS UPGRADE AUTHORIZATION
    // ============================================

    /**
     * @notice UUPS upgrade authorization hook
     * @dev Only addresses with ROLE_UPGRADER can upgrade this contract
     * @param newImplementation Address of new implementation (unused but required by interface)
     */
    function _authorizeUpgrade(address newImplementation) internal view override {
        if (!aclManager.hasRole(ROLE_UPGRADER, msg.sender)) {
            revert Unauthorized(ROLE_UPGRADER, msg.sender);
        }
    }
}
