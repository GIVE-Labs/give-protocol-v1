// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/IACLManager.sol";

/**
 * @title ACLManager
 * @author GIVE Labs
 * @notice Centralised role registry with propose/accept admin flow and upgrade gating (UUPS)
 * @dev Stores role membership in contract storage so it can serve AccessControl-aware contracts directly.
 *      Shared ACL components call `hasRole` to defer role checks to this registry while keeping backwards compatibility.
 */
contract ACLManager is Initializable, UUPSUpgradeable, IACLManager {
    struct RoleData {
        address admin;
        address pendingAdmin;
        bool exists;
        address[] members;
        mapping(address => bool) isMember;
        mapping(address => uint256) indexPlusOne; // index + 1 to enable swap & pop
    }

    bytes32 public constant ROLE_SUPER_ADMIN = keccak256("ROLE_SUPER_ADMIN");
    bytes32 public constant ROLE_UPGRADER = keccak256("ROLE_UPGRADER");
    bytes32 public constant ROLE_PROTOCOL_ADMIN = keccak256("ROLE_PROTOCOL_ADMIN");
    bytes32 public constant ROLE_STRATEGY_ADMIN = keccak256("ROLE_STRATEGY_ADMIN");
    bytes32 public constant ROLE_CAMPAIGN_ADMIN = keccak256("ROLE_CAMPAIGN_ADMIN");
    bytes32 public constant ROLE_CAMPAIGN_CREATOR = keccak256("ROLE_CAMPAIGN_CREATOR");
    bytes32 public constant ROLE_CAMPAIGN_CURATOR = keccak256("ROLE_CAMPAIGN_CURATOR");
    bytes32 public constant ROLE_CHECKPOINT_COUNCIL = keccak256("ROLE_CHECKPOINT_COUNCIL");

    mapping(bytes32 => RoleData) private _roles;

    modifier onlySuperAdmin() {
        if (!hasRole(ROLE_SUPER_ADMIN, msg.sender)) {
            revert UnauthorizedRole(ROLE_SUPER_ADMIN, msg.sender);
        }
        _;
    }

    modifier onlyRoleAdmin(bytes32 roleId) {
        RoleData storage role = _roles[roleId];
        if (!role.exists) revert RoleDoesNotExist(roleId);
        address admin = role.admin;
        if (msg.sender != admin && !hasRole(ROLE_SUPER_ADMIN, msg.sender)) {
            revert UnauthorizedRole(roleId, msg.sender);
        }
        _;
    }

    error ZeroAddress();
    error RoleAlreadyExists(bytes32 roleId);
    error RoleDoesNotExist(bytes32 roleId);
    error UnauthorizedRole(bytes32 roleId, address account);
    error PendingAdminMissing(bytes32 roleId);
    error PendingAdminMismatch(bytes32 roleId, address expected, address actual);
    error AdminMustBeSuper(bytes32 roleId, address admin);

    function initialize(address initialSuperAdmin, address upgrader) external initializer {
        if (initialSuperAdmin == address(0) || upgrader == address(0)) revert ZeroAddress();

        _createRole(ROLE_SUPER_ADMIN, initialSuperAdmin, false);
        _grantRole(ROLE_SUPER_ADMIN, initialSuperAdmin);

        _createRole(ROLE_UPGRADER, initialSuperAdmin, false);
        _grantRole(ROLE_UPGRADER, upgrader);

        _createCanonicalRoles(initialSuperAdmin);
    }

    function createRole(bytes32 roleId, address admin) external onlySuperAdmin {
        if (admin == address(0)) revert ZeroAddress();
        if (!hasRole(ROLE_SUPER_ADMIN, admin)) {
            revert AdminMustBeSuper(roleId, admin);
        }
        _createRole(roleId, admin, true);
    }

    function grantRole(bytes32 roleId, address account) external onlyRoleAdmin(roleId) {
        if (account == address(0)) revert ZeroAddress();
        _grantRole(roleId, account);
    }

    function revokeRole(bytes32 roleId, address account) external onlyRoleAdmin(roleId) {
        if (account == address(0)) revert ZeroAddress();
        _revokeRole(roleId, account);
    }

    function hasRole(bytes32 roleId, address account) public view returns (bool) {
        RoleData storage role = _roles[roleId];
        if (!role.exists) return false;
        return role.isMember[account];
    }

    function roleAdmin(bytes32 roleId) public view returns (address) {
        RoleData storage role = _roles[roleId];
        if (!role.exists) return address(0);
        return role.admin;
    }

    function proposeRoleAdmin(bytes32 roleId, address newAdmin) external onlyRoleAdmin(roleId) {
        if (newAdmin == address(0)) revert ZeroAddress();
        if (!hasRole(ROLE_SUPER_ADMIN, newAdmin)) {
            revert AdminMustBeSuper(roleId, newAdmin);
        }

        RoleData storage role = _roles[roleId];
        role.pendingAdmin = newAdmin;

        emit RoleAdminProposed(roleId, role.admin, newAdmin);
    }

    function acceptRoleAdmin(bytes32 roleId) external {
        RoleData storage role = _roles[roleId];
        if (!role.exists) revert RoleDoesNotExist(roleId);

        address pending = role.pendingAdmin;
        if (pending == address(0)) revert PendingAdminMissing(roleId);
        if (pending != msg.sender) {
            revert PendingAdminMismatch(roleId, pending, msg.sender);
        }
        if (!hasRole(ROLE_SUPER_ADMIN, msg.sender)) {
            revert AdminMustBeSuper(roleId, msg.sender);
        }

        address previousAdmin = role.admin;
        role.admin = msg.sender;
        role.pendingAdmin = address(0);

        emit RoleAdminAccepted(roleId, previousAdmin, msg.sender);
    }

    function getRoleMembers(bytes32 roleId) external view returns (address[] memory) {
        RoleData storage role = _roles[roleId];
        if (!role.exists) revert RoleDoesNotExist(roleId);
        return role.members;
    }

    function roleExists(bytes32 roleId) external view returns (bool) {
        return _roles[roleId].exists;
    }

    function canonicalRoles() external pure returns (bytes32[] memory roles) {
        roles = new bytes32[](8);
        roles[0] = ROLE_SUPER_ADMIN;
        roles[1] = ROLE_UPGRADER;
        roles[2] = ROLE_PROTOCOL_ADMIN;
        roles[3] = ROLE_STRATEGY_ADMIN;
        roles[4] = ROLE_CAMPAIGN_ADMIN;
        roles[5] = ROLE_CAMPAIGN_CREATOR;
        roles[6] = ROLE_CAMPAIGN_CURATOR;
        roles[7] = ROLE_CHECKPOINT_COUNCIL;
    }

    function isCanonicalRole(bytes32 roleId) public pure returns (bool) {
        return roleId == ROLE_SUPER_ADMIN || roleId == ROLE_UPGRADER || roleId == ROLE_PROTOCOL_ADMIN
            || roleId == ROLE_STRATEGY_ADMIN || roleId == ROLE_CAMPAIGN_ADMIN || roleId == ROLE_CAMPAIGN_CREATOR
            || roleId == ROLE_CAMPAIGN_CURATOR || roleId == ROLE_CHECKPOINT_COUNCIL;
    }

    function protocolAdminRole() external pure returns (bytes32) {
        return ROLE_PROTOCOL_ADMIN;
    }

    function strategyAdminRole() external pure returns (bytes32) {
        return ROLE_STRATEGY_ADMIN;
    }

    function campaignAdminRole() external pure returns (bytes32) {
        return ROLE_CAMPAIGN_ADMIN;
    }

    function campaignCreatorRole() external pure returns (bytes32) {
        return ROLE_CAMPAIGN_CREATOR;
    }

    function campaignCuratorRole() external pure returns (bytes32) {
        return ROLE_CAMPAIGN_CURATOR;
    }

    function checkpointCouncilRole() external pure returns (bytes32) {
        return ROLE_CHECKPOINT_COUNCIL;
    }

    function _createRole(bytes32 roleId, address admin, bool checkExists) internal {
        RoleData storage role = _roles[roleId];
        if (role.exists) revert RoleAlreadyExists(roleId);

        if (checkExists && !hasRole(ROLE_SUPER_ADMIN, admin)) {
            revert AdminMustBeSuper(roleId, admin);
        }

        role.admin = admin;
        role.exists = true;

        emit RoleCreated(roleId, admin, msg.sender);
    }

    function _grantRole(bytes32 roleId, address account) internal {
        RoleData storage role = _roles[roleId];
        if (!role.exists) revert RoleDoesNotExist(roleId);
        if (role.isMember[account]) return;

        role.isMember[account] = true;
        role.members.push(account);
        role.indexPlusOne[account] = role.members.length; // store index + 1

        emit RoleGranted(roleId, account, msg.sender);
    }

    function _revokeRole(bytes32 roleId, address account) internal {
        RoleData storage role = _roles[roleId];
        if (!role.exists) revert RoleDoesNotExist(roleId);
        if (!role.isMember[account]) return;

        uint256 index = role.indexPlusOne[account];
        if (index != 0) {
            uint256 lastIndex = role.members.length;
            if (index != lastIndex) {
                address lastMember = role.members[lastIndex - 1];
                role.members[index - 1] = lastMember;
                role.indexPlusOne[lastMember] = index;
            }
            role.members.pop();
            role.indexPlusOne[account] = 0;
        }

        role.isMember[account] = false;

        emit RoleRevoked(roleId, account, msg.sender);
    }

    function _authorizeUpgrade(address) internal view override {
        if (!hasRole(ROLE_UPGRADER, msg.sender)) {
            revert UnauthorizedRole(ROLE_UPGRADER, msg.sender);
        }
    }

    function _createCanonicalRoles(address initialSuperAdmin) private {
        _createRole(ROLE_PROTOCOL_ADMIN, initialSuperAdmin, false);
        _grantRole(ROLE_PROTOCOL_ADMIN, initialSuperAdmin);

        _createRole(ROLE_STRATEGY_ADMIN, initialSuperAdmin, false);
        _grantRole(ROLE_STRATEGY_ADMIN, initialSuperAdmin);

        _createRole(ROLE_CAMPAIGN_ADMIN, initialSuperAdmin, false);
        _grantRole(ROLE_CAMPAIGN_ADMIN, initialSuperAdmin);

        _createRole(ROLE_CAMPAIGN_CREATOR, initialSuperAdmin, false);
        _grantRole(ROLE_CAMPAIGN_CREATOR, initialSuperAdmin);

        _createRole(ROLE_CAMPAIGN_CURATOR, initialSuperAdmin, false);
        _grantRole(ROLE_CAMPAIGN_CURATOR, initialSuperAdmin);

        _createRole(ROLE_CHECKPOINT_COUNCIL, initialSuperAdmin, false);
        _grantRole(ROLE_CHECKPOINT_COUNCIL, initialSuperAdmin);
    }
}
