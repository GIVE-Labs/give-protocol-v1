// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/IACLManager.sol";

/**
 * @title ACLShim
 * @author GIVE Labs
 * @notice Backwards-compatible AccessControl extension that defers role checks to an external ACL manager
 * @dev Extends OpenZeppelin's AccessControl to support delegation to a centralized ACLManager.
 *      This allows for:
 *      1. Centralized role management across multiple contracts
 *      2. Dynamic role creation and modification without redeployment
 *      3. Fallback to local AccessControl if ACLManager is not set
 *
 *      Role Check Priority:
 *      - First checks external ACLManager (if set)
 *      - Falls back to local AccessControl roles
 *      - This ensures backwards compatibility and allows phased migration
 */
abstract contract ACLShim is AccessControl {
    // ============================================
    // STATE VARIABLES
    // ============================================

    /**
     * @notice External ACL manager for centralized role management
     * @dev If set, role checks are delegated to this manager first
     */
    IACLManager public aclManager;

    // ============================================
    // EVENTS
    // ============================================

    /**
     * @notice Emitted when the ACL manager is updated
     * @param previousManager Address of the previous ACL manager (zero if none)
     * @param newManager Address of the new ACL manager
     */
    event ACLManagerUpdated(address indexed previousManager, address indexed newManager);

    // ============================================
    // EXTERNAL FUNCTIONS
    // ============================================

    /**
     * @notice Sets the ACL manager that this contract defers to
     * @dev Only callable by the contract's DEFAULT_ADMIN_ROLE.
     *      Setting to address(0) disables external ACL delegation.
     * @param manager Address of the new ACL manager contract
     */
    function setACLManager(address manager) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _setACLManager(manager);
    }

    // ============================================
    // INTERNAL FUNCTIONS
    // ============================================

    /**
     * @notice Internal setter for ACL manager
     * @dev Allows constructor or initializer to set the ACL manager.
     *      Emits ACLManagerUpdated event.
     * @param manager Address of the ACL manager contract
     */
    function _setACLManager(address manager) internal {
        address previous = address(aclManager);
        aclManager = IACLManager(manager);
        emit ACLManagerUpdated(previous, manager);
    }

    /**
     * @notice Override of AccessControl role checking to support external delegation
     * @dev Checks roles in the following order:
     *      1. If ACLManager is set and account has role there, return (pass)
     *      2. Otherwise, fall back to parent AccessControl._checkRole (local roles)
     *
     *      This allows contracts to:
     *      - Use centralized ACL management when available
     *      - Fall back to local role management for backwards compatibility
     *      - Support gradual migration from local to centralized roles
     * @param role The role identifier to check
     * @param account The address to check for role membership
     */
    function _checkRole(bytes32 role, address account) internal view override {
        // Check external ACL manager first (if set)
        if (address(aclManager) != address(0) && aclManager.hasRole(role, account)) {
            return; // Role found in ACL manager, check passes
        }
        // Fallback to local AccessControl roles
        super._checkRole(role, account);
    }
}
