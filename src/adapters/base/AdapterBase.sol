// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../interfaces/IYieldAdapter.sol";
import "../../utils/GiveErrors.sol";

/**
 * @title AdapterBase
 * @author GIVE Labs
 * @notice Base contract for all yield adapters in the GIVE protocol
 * @dev Abstract contract providing common functionality for yield generation adapters.
 *      All concrete adapters must inherit from this base and implement IYieldAdapter.
 *
 *      Key Features:
 *      - Immutable adapter identification and binding
 *      - Vault-only access control
 *      - Asset management interface
 *
 *      Security Model:
 *      - Only the designated vault can call adapter functions
 *      - Adapter-vault binding is permanent (immutable)
 *      - Each adapter is bound to a single asset and vault
 */
abstract contract AdapterBase is IYieldAdapter {
    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Unique identifier for this adapter instance
    bytes32 public immutable adapterId;

    /// @notice The underlying asset this adapter manages
    address public immutable adapterAsset;

    /// @notice The vault authorized to call this adapter
    address public immutable adapterVault;

    // ============================================
    // ERRORS
    // ============================================

    // Uses GiveErrors.OnlyVault() for unauthorized access

    // ============================================
    // MODIFIERS
    // ============================================

    /**
     * @notice Restricts function access to the designated vault only
     * @dev Reverts with OnlyVault() if caller is not the authorized vault
     */
    modifier onlyVault() {
        if (msg.sender != adapterVault) revert GiveErrors.OnlyVault();
        _;
    }

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /**
     * @notice Initializes the adapter with immutable bindings
     * @dev Sets permanent adapter-vault-asset relationship that cannot be changed.
     *      Called by concrete adapter constructors.
     * @param id Unique identifier for this adapter instance
     * @param asset_ Address of the underlying ERC20 asset
     * @param vault_ Address of the vault authorized to use this adapter
     */
    constructor(bytes32 id, address asset_, address vault_) {
        adapterId = id;
        adapterAsset = asset_;
        adapterVault = vault_;
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Returns the underlying asset managed by this adapter
     * @dev Implements IYieldAdapter.asset()
     * @return IERC20 interface of the underlying asset
     */
    function asset() public view override returns (IERC20) {
        return IERC20(adapterAsset);
    }

    /**
     * @notice Returns the vault authorized to use this adapter
     * @dev Implements IYieldAdapter.vault()
     * @return Address of the authorized vault
     */
    function vault() public view override returns (address) {
        return adapterVault;
    }
}
