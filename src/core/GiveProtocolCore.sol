// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/IACLManager.sol";
import "../storage/StorageLib.sol";
import "../types/GiveTypes.sol";
import "../modules/VaultModule.sol";
import "../modules/AdapterModule.sol";
import "../modules/DonationModule.sol";
import "../modules/SyntheticModule.sol";
import "../modules/RiskModule.sol";
import "../modules/EmergencyModule.sol";
// import "../synthetic/SyntheticLogic.sol"; // TODO: Phase 9
import "../vault/GiveVault4626.sol";

/**
 * @title GiveProtocolCore
 * @author GIVE Labs
 * @notice Thin orchestration layer that delegates lifecycle operations to module libraries
 * @dev UUPS upgradeable protocol coordinator that routes configuration calls to specialized modules.
 *
 *      Key Responsibilities:
 *      - Initialize protocol with ACL manager
 *      - Route configuration calls to module libraries
 *      - Provide read-only views for protocol state
 *      - Enforce role-based access control
 *      - Coordinate vault-risk synchronization
 *
 *      Architecture:
 *      - UUPS upgradeable proxy pattern
 *      - Stateless delegation to pure library modules
 *      - ACL-based permission system
 *      - Diamond storage via StorageLib
 *
 *      Module Delegation Pattern:
 *      This contract acts as the entry point for protocol management.
 *      All configuration operations are delegated to module libraries:
 *      - VaultModule: Vault configuration
 *      - AdapterModule: Yield adapter configuration
 *      - DonationModule: Donation routing configuration
 *      - RiskModule: Risk parameter configuration
 *      - EmergencyModule: Emergency operations
 *      - SyntheticModule: Synthetic assets (Phase 9 - stub only)
 *
 *      Modules are pure libraries that write to diamond storage.
 *      This keeps GiveProtocolCore thin and focused on orchestration.
 *
 *      Security Model:
 *      - All configuration functions require role checks via ACLManager
 *      - Upgrade authority restricted to ROLE_UPGRADER
 *      - Emergency operations require EMERGENCY_ROLE
 *      - No direct state modifications (delegated to modules)
 *
 *      Upgrade Safety:
 *      - UUPS pattern allows contract logic upgrades
 *      - Storage preserved across upgrades via diamond storage
 *      - Upgrade gated by ROLE_UPGRADER
 *      - Version tracking in SystemConfig
 */
contract GiveProtocolCore is Initializable, UUPSUpgradeable {
    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice ACL manager for protocol-wide permissions
    /// @dev Immutable after initialization, checked on all restricted operations
    IACLManager public aclManager;

    // ============================================
    // CONSTANTS
    // ============================================

    /// @notice Role required to upgrade the contract
    bytes32 public constant ROLE_UPGRADER = keccak256("ROLE_UPGRADER");

    /// @notice Role required for emergency operations
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // ============================================
    // ERRORS
    // ============================================

    /**
     * @notice Caller lacks required role
     * @param roleId Required role identifier
     * @param account Address that attempted the operation
     */
    error Unauthorized(bytes32 roleId, address account);

    // ============================================
    // EVENTS
    // ============================================

    /**
     * @notice Emitted when protocol is initialized
     * @param acl ACL manager address
     * @param caller Address that initialized the protocol
     */
    event Initialized(address indexed acl, address indexed caller);

    // ============================================
    // MODIFIERS
    // ============================================

    /**
     * @notice Restricts access to callers with a specific role
     * @dev Reverts with Unauthorized error if caller lacks the role
     * @param roleId Role identifier to check
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
     * @notice Initializes the protocol with ACL manager
     * @dev Can only be called once due to initializer modifier.
     *      Stores ACL reference in both state and diamond storage.
     *      Increments protocol version number.
     * @param _aclManager Address of the ACL manager contract
     */
    function initialize(address _aclManager) external initializer {
        if (_aclManager == address(0)) revert Unauthorized(ROLE_UPGRADER, address(0));

        aclManager = IACLManager(_aclManager);

        // Initialize system config in diamond storage
        GiveTypes.SystemConfig storage sys = StorageLib.system();
        sys.aclManager = _aclManager;
        sys.initialized = true;
        sys.version += 1;
        sys.lastBootstrapAt = uint64(block.timestamp);

        emit Initialized(_aclManager, msg.sender);
    }

    // ============================================
    // VAULT MODULE ENTRYPOINTS
    // ============================================

    /**
     * @notice Configures a vault in protocol storage
     * @dev Delegates to VaultModule.configure().
     *      Requires VAULT_MODULE_MANAGER_ROLE.
     * @param vaultId Unique identifier for the vault
     * @param cfg Vault configuration parameters
     */
    function configureVault(bytes32 vaultId, VaultModule.VaultConfigInput memory cfg)
        external
        onlyRole(VaultModule.MANAGER_ROLE)
    {
        VaultModule.configure(vaultId, cfg);
    }

    // ============================================
    // ADAPTER MODULE ENTRYPOINTS
    // ============================================

    /**
     * @notice Configures a yield adapter in protocol storage
     * @dev Delegates to AdapterModule.configure().
     *      Requires ADAPTER_MODULE_MANAGER_ROLE.
     * @param adapterId Unique identifier for the adapter
     * @param cfg Adapter configuration parameters
     */
    function configureAdapter(bytes32 adapterId, AdapterModule.AdapterConfigInput memory cfg)
        external
        onlyRole(AdapterModule.MANAGER_ROLE)
    {
        AdapterModule.configure(adapterId, cfg);
    }

    /**
     * @notice Gets adapter configuration
     * @dev Read-only view of adapter storage
     * @param adapterId Unique identifier for the adapter
     * @return assetAddress Underlying asset address
     * @return vaultAddress Vault address using this adapter
     * @return kind Adapter kind (CompoundingValue, ClaimableYield, BalanceGrowth, FixedMaturityToken)
     * @return active Whether adapter is active
     */
    function getAdapterConfig(bytes32 adapterId)
        external
        view
        returns (address assetAddress, address vaultAddress, GiveTypes.AdapterKind kind, bool active)
    {
        GiveTypes.AdapterConfig storage cfg = StorageLib.adapter(adapterId);
        return (cfg.asset, cfg.vault, cfg.kind, cfg.active);
    }

    // ============================================
    // DONATION MODULE ENTRYPOINTS
    // ============================================

    /**
     * @notice Configures donation routing parameters
     * @dev Delegates to DonationModule.configure().
     *      Requires DONATION_MODULE_MANAGER_ROLE.
     * @param donationId Unique identifier for donation configuration
     * @param cfg Donation configuration parameters
     */
    function configureDonation(bytes32 donationId, DonationModule.DonationConfigInput memory cfg)
        external
        onlyRole(DonationModule.MANAGER_ROLE)
    {
        DonationModule.configure(donationId, cfg);
    }

    // ============================================
    // RISK MODULE ENTRYPOINTS
    // ============================================

    /**
     * @notice Configures risk parameters for a risk profile
     * @dev Delegates to RiskModule.configure().
     *      Requires RISK_MODULE_MANAGER_ROLE.
     * @param riskId Unique identifier for the risk profile
     * @param cfg Risk configuration parameters
     */
    function configureRisk(bytes32 riskId, RiskModule.RiskConfigInput memory cfg)
        external
        onlyRole(RiskModule.MANAGER_ROLE)
    {
        RiskModule.configure(riskId, cfg);
    }

    /**
     * @notice Assigns a risk profile to a vault and syncs limits
     * @dev Delegates to RiskModule.assignVaultRisk() then syncs limits to vault contract.
     *      If vault proxy exists, calls syncRiskLimits() on the vault.
     *      Requires RISK_MODULE_MANAGER_ROLE.
     * @param vaultId Unique identifier for the vault
     * @param riskId Unique identifier for the risk profile
     */
    function assignVaultRisk(bytes32 vaultId, bytes32 riskId) external onlyRole(RiskModule.MANAGER_ROLE) {
        GiveTypes.VaultConfig storage vaultCfg = StorageLib.vault(vaultId);
        RiskModule.assignVaultRisk(vaultId, riskId);

        // Sync limits to vault contract if it exists
        address vaultProxy = vaultCfg.proxy;
        if (vaultProxy != address(0)) {
            GiveTypes.RiskConfig storage riskCfg = StorageLib.ensureRiskConfig(riskId);
            GiveVault4626(payable(vaultProxy)).syncRiskLimits(riskId, riskCfg.maxDeposit, riskCfg.maxBorrow);
        }
    }

    /**
     * @notice Gets risk configuration
     * @dev Read-only view of risk storage
     * @param riskId Unique identifier for the risk profile
     * @return Risk configuration struct
     */
    function getRiskConfig(bytes32 riskId) external view returns (GiveTypes.RiskConfig memory) {
        return StorageLib.riskConfig(riskId);
    }

    // ============================================
    // EMERGENCY MODULE ENTRYPOINTS
    // ============================================

    /**
     * @notice Triggers emergency action on a vault
     * @dev Delegates to EmergencyModule.execute().
     *      Emergency actions: Pause, Unpause, Withdraw.
     *      Requires EMERGENCY_ROLE.
     * @param vaultId Unique identifier for the vault
     * @param action Emergency action to perform
     * @param data ABI-encoded parameters for the action
     */
    function triggerEmergency(bytes32 vaultId, EmergencyModule.EmergencyAction action, bytes calldata data)
        external
        onlyRole(EMERGENCY_ROLE)
    {
        EmergencyModule.execute(vaultId, action, data);
    }

    // ============================================
    // SYNTHETIC MODULE ENTRYPOINTS (PHASE 9 - STUB)
    // ============================================

    /**
     * @notice Configures a synthetic asset
     * @dev **PHASE 9 STUB**: Currently only emits event, does NOT populate storage.
     *      Delegates to SyntheticModule.configure().
     *      Requires SYNTHETIC_MODULE_MANAGER_ROLE.
     * @param syntheticId Unique identifier for the synthetic asset
     * @param cfg Synthetic asset configuration parameters
     */
    function configureSynthetic(bytes32 syntheticId, SyntheticModule.SyntheticConfigInput memory cfg)
        external
        onlyRole(SyntheticModule.MANAGER_ROLE)
    {
        SyntheticModule.configure(syntheticId, cfg);
    }

    // TODO: Phase 9 - Uncomment when SyntheticLogic is implemented
    /*
    function mintSynthetic(bytes32 syntheticId, address account, uint256 amount)
        external
        onlyRole(SyntheticModule.MANAGER_ROLE)
    {
        SyntheticLogic.mint(syntheticId, account, amount);
    }

    function burnSynthetic(bytes32 syntheticId, address account, uint256 amount)
        external
        onlyRole(SyntheticModule.MANAGER_ROLE)
    {
        SyntheticLogic.burn(syntheticId, account, amount);
    }

    function getSyntheticBalance(bytes32 syntheticId, address account) external view returns (uint256) {
        return StorageLib.syntheticState(syntheticId).balances[account];
    }

    function getSyntheticTotalSupply(bytes32 syntheticId) external view returns (uint256) {
        return StorageLib.syntheticState(syntheticId).totalSupply;
    }

    function getSyntheticConfig(bytes32 syntheticId)
        external
        view
        returns (address proxy, address asset, bool active)
    {
        GiveTypes.SyntheticAsset storage syntheticAsset = StorageLib.syntheticState(syntheticId);
        return (syntheticAsset.proxy, syntheticAsset.asset, syntheticAsset.active);
    }
    */

    // ============================================
    // UPGRADEABILITY
    // ============================================

    /**
     * @notice Authorizes contract upgrades
     * @dev Called by UUPSUpgradeable during upgrade process.
     *      Only addresses with ROLE_UPGRADER can upgrade.
     * @param newImplementation Address of new implementation (unused but required by interface)
     */
    function _authorizeUpgrade(address newImplementation) internal view override {
        newImplementation; // Silence unused parameter warning
        if (!aclManager.hasRole(ROLE_UPGRADER, msg.sender)) {
            revert Unauthorized(ROLE_UPGRADER, msg.sender);
        }
    }
}
