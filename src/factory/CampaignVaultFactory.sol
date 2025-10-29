// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../interfaces/IACLManager.sol";
import "../types/GiveTypes.sol";

/**
 * @title CampaignVaultFactory
 * @author GIVE Labs
 * @notice Deploys campaign vaults as UUPS-upgradeable proxies (M-01 fix)
 * @dev Uses CREATE2 for deterministic deployment addresses.
 *      Critical change from v0.5: Deploys ERC1967Proxy instead of EIP-1167 clones.
 *
 *      Key Features:
 *      - Deterministic vault addresses via CREATE2
 *      - Campaign-strategy validation
 *      - Automatic registry and router integration
 *      - Vault implementation upgradability
 *
 *      M-01 Fix:
 *      v0.5 used EIP-1167 minimal proxies (Clones.cloneDeterministic) which cannot be upgraded.
 *      v1 uses ERC1967Proxy which supports UUPS upgradeability per vault instance.
 *
 *      Deployment Flow:
 *      1. Validate campaign-strategy match
 *      2. Compute CREATE2 salt from (campaignId, strategyId, lockProfile)
 *      3. Deploy ERC1967Proxy → CampaignVault4626 implementation
 *      4. Call initialize(asset, name, symbol, admin, acl, implementation, factory)
 *      5. Call initializeCampaign(campaignId, strategyId, lockProfile)
 *      6. Register vault with CampaignRegistry, StrategyRegistry, PayoutRouter
 *
 *      Security Model:
 *      - CAMPAIGN_ADMIN_ROLE: Deploy vaults, update implementation
 *      - ROLE_UPGRADER: Factory contract upgrades
 */
contract CampaignVaultFactory is Initializable, UUPSUpgradeable {
    // ============================================
    // STATE VARIABLES
    // ============================================

    IACLManager public aclManager;
    address public campaignRegistry;
    address public strategyRegistry;
    address public payoutRouter;

    /// @notice Implementation contract for vault proxies
    address public vaultImplementation;

    /// @notice Role for contract upgrades
    bytes32 public constant ROLE_UPGRADER = keccak256("ROLE_UPGRADER");

    // ============================================
    // STRUCTS
    // ============================================

    struct DeployParams {
        bytes32 campaignId;
        bytes32 strategyId;
        bytes32 lockProfile;
        address asset;
        address admin;
        string name;
        string symbol;
    }

    // ============================================
    // EVENTS
    // ============================================

    event VaultCreated(
        bytes32 indexed campaignId,
        bytes32 indexed strategyId,
        bytes32 lockProfile,
        address indexed vault,
        bytes32 vaultId
    );

    event ImplementationUpdated(address indexed oldImpl, address indexed newImpl);

    // ============================================
    // ERRORS
    // ============================================

    error ZeroAddress();
    error Unauthorized(bytes32 roleId, address account);
    error DeploymentExists(bytes32 salt);
    error CampaignStrategyMismatch(bytes32 campaignId, bytes32 expectedStrategy, bytes32 providedStrategy);
    error InvalidParameters();

    // ============================================
    // MODIFIERS
    // ============================================

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
     * @notice Initializes the factory
     * @param acl ACL manager address
     * @param campaignRegistry_ CampaignRegistry address
     * @param strategyRegistry_ StrategyRegistry address
     * @param payoutRouter_ PayoutRouter address
     * @param vaultImplementation_ CampaignVault4626 implementation address
     */
    function initialize(
        address acl,
        address campaignRegistry_,
        address strategyRegistry_,
        address payoutRouter_,
        address vaultImplementation_
    ) external initializer {
        if (
            acl == address(0) || campaignRegistry_ == address(0) || strategyRegistry_ == address(0)
                || payoutRouter_ == address(0) || vaultImplementation_ == address(0)
        ) {
            revert ZeroAddress();
        }

        __UUPSUpgradeable_init();

        aclManager = IACLManager(acl);
        campaignRegistry = campaignRegistry_;
        strategyRegistry = strategyRegistry_;
        payoutRouter = payoutRouter_;
        vaultImplementation = vaultImplementation_;
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    /**
     * @notice Update vault implementation for future deployments
     * @dev Only affects new deployments. Existing vaults must upgrade individually via UUPS.
     * @param newImpl New CampaignVault4626 implementation address
     */
    function setVaultImplementation(address newImpl) external onlyRole(aclManager.campaignAdminRole()) {
        if (newImpl == address(0)) revert ZeroAddress();
        address oldImpl = vaultImplementation;
        vaultImplementation = newImpl;
        emit ImplementationUpdated(oldImpl, newImpl);
    }

    // ============================================
    // DEPLOYMENT FUNCTIONS
    // ============================================

    /**
     * @notice Deploys a new campaign vault as UUPS proxy
     * @dev Validates campaign-strategy match, deploys ERC1967Proxy, initializes vault,
     *      and registers with all relevant contracts.
     * @param params Deployment parameters (campaignId, strategyId, lockProfile, asset, admin, name, symbol)
     * @return vault Address of deployed vault proxy
     */
    function deployCampaignVault(DeployParams calldata params)
        external
        onlyRole(aclManager.campaignAdminRole())
        returns (address vault)
    {
        // Validate parameters
        if (params.asset == address(0) || params.admin == address(0) || bytes(params.name).length == 0) {
            revert InvalidParameters();
        }

        // Validate campaign-strategy match
        (bool success, bytes memory data) = campaignRegistry.staticcall(
            abi.encodeWithSignature("getCampaign(bytes32)", params.campaignId)
        );
        if (!success) revert InvalidParameters();

        GiveTypes.CampaignConfig memory campaignCfg = abi.decode(data, (GiveTypes.CampaignConfig));
        if (campaignCfg.strategyId != params.strategyId) {
            revert CampaignStrategyMismatch(params.campaignId, campaignCfg.strategyId, params.strategyId);
        }

        // Compute deterministic salt from campaign params
        bytes32 salt = keccak256(abi.encodePacked(params.campaignId, params.strategyId, params.lockProfile));

        // Predict address and check if already deployed
        address predicted = predictVaultAddress(params);
        if (predicted.code.length > 0) {
            revert DeploymentExists(salt);
        }

        // Encode initializer call for CampaignVault4626.initialize()
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,string,string,address,address,address,address)",
            params.asset,
            params.name,
            params.symbol,
            params.admin,
            address(aclManager),
            vaultImplementation,
            address(this) // factory address
        );

        // Deploy ERC1967Proxy with CREATE2 for deterministic address
        vault = address(new ERC1967Proxy{salt: salt}(vaultImplementation, initData));

        // Initialize campaign metadata (factory-only call)
        (success,) = vault.call(
            abi.encodeWithSignature(
                "initializeCampaign(bytes32,bytes32,bytes32)", params.campaignId, params.strategyId, params.lockProfile
            )
        );
        if (!success) revert InvalidParameters();

        // Wire into registries and router
        (success,) = campaignRegistry.call(
            abi.encodeWithSignature("setCampaignVault(bytes32,address,bytes32)", params.campaignId, vault, params.lockProfile)
        );
        if (!success) revert InvalidParameters();

        (success,) =
            strategyRegistry.call(abi.encodeWithSignature("registerStrategyVault(bytes32,address)", params.strategyId, vault));
        if (!success) revert InvalidParameters();

        (success,) =
            payoutRouter.call(abi.encodeWithSignature("registerCampaignVault(address,bytes32)", vault, params.campaignId));
        if (!success) revert InvalidParameters();

        (success,) = payoutRouter.call(abi.encodeWithSignature("setAuthorizedCaller(address,bool)", vault, true));
        if (!success) revert InvalidParameters();

        // Get vaultId for event
        (success, data) = vault.staticcall(abi.encodeWithSignature("vaultId()"));
        bytes32 vaultId = success ? abi.decode(data, (bytes32)) : bytes32(0);

        emit VaultCreated(params.campaignId, params.strategyId, params.lockProfile, vault, vaultId);

        return vault;
    }

    /**
     * @notice Predict vault address before deployment
     * @dev Computes CREATE2 address for ERC1967Proxy deployment.
     *      Requires all deployment parameters because init data affects bytecode hash.
     *      Useful for off-chain address computation and front-running protection.
     * @param params Full deployment parameters
     * @return Predicted vault proxy address
     */
    function predictVaultAddress(DeployParams calldata params) public view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(params.campaignId, params.strategyId, params.lockProfile));

        // Encode initializer data (must match deployCampaignVault exactly)
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,string,string,address,address,address,address)",
            params.asset,
            params.name,
            params.symbol,
            params.admin,
            address(aclManager),
            vaultImplementation,
            address(this) // factory address
        );

        // Compute CREATE2 address
        bytes memory proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(vaultImplementation, initData)
        );

        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(proxyBytecode)));

        return address(uint160(uint256(hash)));
    }

    // ============================================
    // UUPS UPGRADE
    // ============================================

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal view override {
        if (!aclManager.hasRole(ROLE_UPGRADER, msg.sender)) {
            revert Unauthorized(ROLE_UPGRADER, msg.sender);
        }
    }
}
