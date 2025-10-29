// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../storage/StorageLib.sol";

/**
 * @title DonationModule
 * @author GIVE Labs
 * @notice Library module for donation routing configuration
 * @dev Provides functions to configure donation-related settings in protocol storage.
 *      Used by GiveProtocolCore to manage donation flow parameters.
 *
 *      Key Responsibilities:
 *      - Register PayoutRouter proxy address
 *      - Register NGORegistry proxy address
 *      - Configure fee recipient for protocol fees
 *      - Set fee basis points for donation routing
 *
 *      Architecture:
 *      - Pure library (no state, called via delegatecall from GiveProtocolCore)
 *      - Writes to diamond storage via StorageLib using custom keys
 *      - Emits events from GiveProtocolCore context
 *
 *      Storage Pattern:
 *      Uses namespaced keys: keccak256(abi.encodePacked("donation", id, field))
 *      - "router": PayoutRouter proxy address
 *      - "registry": NGORegistry proxy address
 *      - "feeRecipient": Address receiving protocol fees
 *      - "feeBps": Fee percentage in basis points (100 = 1%)
 *
 *      Security Model:
 *      - Only GiveProtocolCore should call these functions
 *      - MANAGER_ROLE required in calling contract
 *      - Donation ID must be unique (handled by caller)
 *
 *      Use Cases:
 *      - Initial protocol deployment → configure donation routing
 *      - Query donation config → StorageLib.getAddress() with namespaced keys
 *      - Update parameters → call configure() again with new values
 */
library DonationModule {
    // ============================================
    // CONSTANTS
    // ============================================

    /// @notice Role required to manage donation configurations
    bytes32 public constant MANAGER_ROLE = keccak256("DONATION_MODULE_MANAGER_ROLE");

    // ============================================
    // STRUCTS
    // ============================================

    /**
     * @notice Input parameters for donation configuration
     * @param id Unique identifier for this donation configuration
     * @param routerProxy Address of the PayoutRouter proxy
     * @param registryProxy Address of the NGORegistry proxy
     * @param feeRecipient Address that receives protocol fees
     * @param feeBps Fee percentage in basis points (100 = 1%, max 10000 = 100%)
     */
    struct DonationConfigInput {
        bytes32 id;
        address routerProxy;
        address registryProxy;
        address feeRecipient;
        uint256 feeBps;
    }

    // ============================================
    // EVENTS
    // ============================================

    /**
     * @notice Emitted when donation configuration is set
     * @param id Unique donation configuration identifier
     * @param router PayoutRouter proxy address
     * @param registry NGORegistry proxy address
     * @param feeBps Fee percentage in basis points
     */
    event DonationConfigured(bytes32 indexed id, address router, address registry, uint256 feeBps);

    // ============================================
    // FUNCTIONS
    // ============================================

    /**
     * @notice Configures donation routing in protocol storage
     * @dev Writes donation configuration to diamond storage using namespaced keys.
     *      Stores router, registry, fee recipient, and fee basis points.
     *      Does not validate addresses or fee bounds - caller must ensure validity.
     * @param donationId Unique identifier for this donation configuration
     * @param cfg Donation configuration parameters
     */
    function configure(bytes32 donationId, DonationConfigInput memory cfg) internal {
        bytes32 baseKey = keccak256(abi.encodePacked("donation", cfg.id));
        StorageLib.setAddress(keccak256(abi.encodePacked(baseKey, "router")), cfg.routerProxy);
        StorageLib.setAddress(keccak256(abi.encodePacked(baseKey, "registry")), cfg.registryProxy);
        StorageLib.setAddress(keccak256(abi.encodePacked(baseKey, "feeRecipient")), cfg.feeRecipient);
        StorageLib.setUint(keccak256(abi.encodePacked(baseKey, "feeBps")), cfg.feeBps);

        emit DonationConfigured(donationId, cfg.routerProxy, cfg.registryProxy, cfg.feeBps);
    }
}
