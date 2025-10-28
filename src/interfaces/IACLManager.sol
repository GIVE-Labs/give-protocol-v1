// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IACLManager
 * @author GIVE Labs
 * @notice Interface for the centralized Access Control List manager
 * @dev Defines the standard interface for role-based access control across the GIVE Protocol.
 *      The ACLManager supports:
 *      - Dynamic role creation and management
 *      - Two-step role admin transfers for safety
 *      - Role member enumeration
 *      - Canonical protocol roles with deterministic identifiers
 */
interface IACLManager {
    // ============================================
    // EVENTS
    // ============================================

    /**
     * @notice Emitted when a new role is created
     * @param roleId The unique role identifier
     * @param admin The address set as the role's initial admin
     * @param sender The address that created the role
     */
    event RoleCreated(bytes32 indexed roleId, address indexed admin, address indexed sender);

    /**
     * @notice Emitted when a role is granted to an account
     * @param roleId The role identifier
     * @param account The address that received the role
     * @param sender The address that granted the role
     */
    event RoleGranted(bytes32 indexed roleId, address indexed account, address indexed sender);

    /**
     * @notice Emitted when a role is revoked from an account
     * @param roleId The role identifier
     * @param account The address that lost the role
     * @param sender The address that revoked the role
     */
    event RoleRevoked(bytes32 indexed roleId, address indexed account, address indexed sender);

    /**
     * @notice Emitted when a role admin transfer is proposed
     * @param roleId The role identifier
     * @param currentAdmin The current admin address
     * @param proposedAdmin The proposed new admin address
     */
    event RoleAdminProposed(bytes32 indexed roleId, address indexed currentAdmin, address indexed proposedAdmin);

    /**
     * @notice Emitted when a role admin transfer is accepted
     * @param roleId The role identifier
     * @param previousAdmin The previous admin address
     * @param newAdmin The new admin address
     */
    event RoleAdminAccepted(bytes32 indexed roleId, address indexed previousAdmin, address indexed newAdmin);

    // ============================================
    // INITIALIZATION
    // ============================================

    /**
     * @notice Initializes the ACL manager with initial roles and admins
     * @dev Should only be callable once during deployment/proxy initialization
     * @param initialSuperAdmin Address to receive super admin role
     * @param upgrader Address authorized to upgrade contracts
     */
    function initialize(address initialSuperAdmin, address upgrader) external;

    // ============================================
    // ROLE MANAGEMENT
    // ============================================

    /**
     * @notice Creates a new role with specified admin
     * @dev Only callable by addresses with appropriate permissions
     * @param roleId The unique identifier for the role
     * @param admin The address that will administer this role
     */
    function createRole(bytes32 roleId, address admin) external;

    /**
     * @notice Grants a role to an account
     * @dev Only callable by the role's admin
     * @param roleId The role identifier
     * @param account The address to receive the role
     */
    function grantRole(bytes32 roleId, address account) external;

    /**
     * @notice Revokes a role from an account
     * @dev Only callable by the role's admin
     * @param roleId The role identifier
     * @param account The address to lose the role
     */
    function revokeRole(bytes32 roleId, address account) external;

    /**
     * @notice Proposes a new admin for a role (step 1 of 2)
     * @dev Initiates two-step admin transfer for safety
     * @param roleId The role identifier
     * @param newAdmin The proposed new admin address
     */
    function proposeRoleAdmin(bytes32 roleId, address newAdmin) external;

    /**
     * @notice Accepts role admin transfer (step 2 of 2)
     * @dev Must be called by the proposed admin to complete transfer
     * @param roleId The role identifier
     */
    function acceptRoleAdmin(bytes32 roleId) external;

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Checks if an account has a specific role
     * @param roleId The role identifier to check
     * @param account The address to check
     * @return True if account has the role, false otherwise
     */
    function hasRole(bytes32 roleId, address account) external view returns (bool);

    /**
     * @notice Returns the admin address for a role
     * @param roleId The role identifier
     * @return The address that administers this role
     */
    function roleAdmin(bytes32 roleId) external view returns (address);

    /**
     * @notice Returns all addresses that have a specific role
     * @dev Useful for enumeration and governance dashboards
     * @param roleId The role identifier
     * @return Array of addresses holding the role
     */
    function getRoleMembers(bytes32 roleId) external view returns (address[] memory);

    /**
     * @notice Checks if a role has been created
     * @param roleId The role identifier
     * @return True if role exists, false otherwise
     */
    function roleExists(bytes32 roleId) external view returns (bool);

    /**
     * @notice Returns all canonical protocol role identifiers
     * @dev Canonical roles are predefined roles with special meaning in the protocol
     * @return Array of canonical role identifiers
     */
    function canonicalRoles() external pure returns (bytes32[] memory);

    /**
     * @notice Checks if a role is a canonical protocol role
     * @param roleId The role identifier to check
     * @return True if role is canonical, false otherwise
     */
    function isCanonicalRole(bytes32 roleId) external pure returns (bool);

    // ============================================
    // CANONICAL ROLE GETTERS
    // ============================================

    /**
     * @notice Returns the protocol admin role identifier
     * @dev Protocol admins can manage global protocol settings
     * @return The protocol admin role identifier
     */
    function protocolAdminRole() external pure returns (bytes32);

    /**
     * @notice Returns the strategy admin role identifier
     * @dev Strategy admins can create and manage yield strategies
     * @return The strategy admin role identifier
     */
    function strategyAdminRole() external pure returns (bytes32);

    /**
     * @notice Returns the campaign admin role identifier
     * @dev Campaign admins can approve/reject campaigns and manage campaign lifecycle
     * @return The campaign admin role identifier
     */
    function campaignAdminRole() external pure returns (bytes32);

    /**
     * @notice Returns the campaign creator role identifier
     * @dev Campaign creators can submit new campaigns (permissionless with deposit)
     * @return The campaign creator role identifier
     */
    function campaignCreatorRole() external pure returns (bytes32);

    /**
     * @notice Returns the campaign curator role identifier
     * @dev Campaign curators are assigned to manage specific campaigns
     * @return The campaign curator role identifier
     */
    function campaignCuratorRole() external pure returns (bytes32);

    /**
     * @notice Returns the checkpoint council role identifier
     * @dev Checkpoint council members can schedule and finalize checkpoints
     * @return The checkpoint council role identifier
     */
    function checkpointCouncilRole() external pure returns (bytes32);
}
