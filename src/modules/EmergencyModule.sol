// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../storage/StorageLib.sol";
import "../types/GiveTypes.sol";
import "../vault/GiveVault4626.sol";

/**
 * @title EmergencyModule
 * @author GIVE Labs
 * @notice Library module for emergency vault operations
 * @dev Provides functions to handle vault emergency scenarios (pause, resume, emergency withdrawal).
 *      Used by GiveProtocolCore to execute critical operations during protocol emergencies.
 *
 *      Key Responsibilities:
 *      - Pause vaults during emergencies (stops deposits/withdrawals)
 *      - Resume vaults after emergencies are resolved
 *      - Execute emergency withdrawal from adapters
 *      - Optionally clear adapter bindings during severe issues
 *
 *      Architecture:
 *      - Pure library (no state, called via delegatecall from GiveProtocolCore)
 *      - Calls external vault functions (emergencyPause, resumeFromEmergency)
 *      - Updates vault config in diamond storage
 *      - Emits events from GiveProtocolCore context
 *
 *      Emergency Workflow:
 *      1. Pause: Sets vault to emergency mode, prevents all operations
 *      2. Withdraw: Pulls all assets from adapter back to vault
 *      3. (Optional) Clear adapter binding if adapter is compromised
 *      4. Unpause: Resumes normal vault operations
 *
 *      Security Model:
 *      - Only GiveProtocolCore should call these functions
 *      - MANAGER_ROLE required in calling contract (typically EMERGENCY_ROLE holders)
 *      - State validation enforced (can't pause if already paused, etc.)
 *
 *      Use Cases:
 *      - Adapter protocol exploit → pause + withdraw + clear adapter
 *      - Vault bug discovered → pause until fixed
 *      - Network congestion → temporary pause
 *      - Post-emergency → resume operations
 */
library EmergencyModule {
    // ============================================
    // CONSTANTS
    // ============================================

    /// @notice Role required to execute emergency operations
    bytes32 public constant MANAGER_ROLE = keccak256("EMERGENCY_MODULE_MANAGER_ROLE");

    // ============================================
    // ENUMS
    // ============================================

    /**
     * @notice Types of emergency actions that can be executed
     * @param Pause Halts all vault operations
     * @param Unpause Resumes normal vault operations
     * @param Withdraw Pulls all assets from adapter to vault
     */
    enum EmergencyAction {
        Pause,
        Unpause,
        Withdraw
    }

    // ============================================
    // STRUCTS
    // ============================================

    /**
     * @notice Parameters for emergency withdrawal
     * @param clearAdapter Whether to unbind adapter after withdrawal
     */
    struct EmergencyWithdrawParams {
        bool clearAdapter;
    }

    // ============================================
    // EVENTS
    // ============================================

    /**
     * @notice Emitted when vault emergency state changes
     * @param vaultId Unique vault identifier
     * @param active Whether emergency mode is active (true) or inactive (false)
     * @param caller Address that triggered the state change
     */
    event EmergencyStateChanged(bytes32 indexed vaultId, bool active, address indexed caller);

    /**
     * @notice Emitted when emergency withdrawal is executed
     * @param vaultId Unique vault identifier
     * @param adapter Address of the adapter withdrawn from
     * @param amount Amount of assets withdrawn
     * @param adapterCleared Whether adapter binding was cleared
     */
    event EmergencyWithdrawal(bytes32 indexed vaultId, address indexed adapter, uint256 amount, bool adapterCleared);

    // ============================================
    // ERRORS
    // ============================================

    error EmergencyAlreadyActive(bytes32 vaultId);
    error EmergencyNotActive(bytes32 vaultId);
    error NoActiveAdapter(bytes32 vaultId);

    // ============================================
    // FUNCTIONS
    // ============================================

    /**
     * @notice Executes an emergency action on a vault
     * @dev Validates vault exists and is active, then routes to appropriate action handler.
     *      Pause/Unpause affect vault state, Withdraw pulls assets from adapter.
     * @param vaultId Unique identifier of the vault
     * @param action Type of emergency action to execute
     * @param data ABI-encoded parameters for the action (empty for Pause/Unpause)
     */
    function execute(bytes32 vaultId, EmergencyAction action, bytes calldata data) internal {
        GiveTypes.VaultConfig storage cfg = StorageLib.ensureVaultActive(vaultId);
        address vaultProxy = cfg.proxy;

        if (action == EmergencyAction.Pause) {
            _pauseVault(cfg, vaultId, vaultProxy);
        } else if (action == EmergencyAction.Unpause) {
            _resumeVault(cfg, vaultId, vaultProxy);
        } else if (action == EmergencyAction.Withdraw) {
            _emergencyWithdraw(cfg, vaultId, vaultProxy, data);
        }
    }

    /**
     * @notice Pauses a vault, enabling emergency mode
     * @dev Calls vault's emergencyPause(), updates config, records timestamp.
     *      Reverts if vault is already in emergency mode.
     * @param cfg Storage reference to vault configuration
     * @param vaultId Unique vault identifier
     * @param vaultProxy Address of the vault proxy
     */
    function _pauseVault(GiveTypes.VaultConfig storage cfg, bytes32 vaultId, address vaultProxy) private {
        if (cfg.emergencyShutdown) revert EmergencyAlreadyActive(vaultId);

        GiveVault4626(payable(vaultProxy)).emergencyPause();
        cfg.emergencyShutdown = true;
        cfg.emergencyActivatedAt = uint64(block.timestamp);
        emit EmergencyStateChanged(vaultId, true, msg.sender);
    }

    /**
     * @notice Resumes a vault from emergency mode
     * @dev Calls vault's resumeFromEmergency(), resets config flags.
     *      Reverts if vault is not in emergency mode.
     * @param cfg Storage reference to vault configuration
     * @param vaultId Unique vault identifier
     * @param vaultProxy Address of the vault proxy
     */
    function _resumeVault(GiveTypes.VaultConfig storage cfg, bytes32 vaultId, address vaultProxy) private {
        if (!cfg.emergencyShutdown) revert EmergencyNotActive(vaultId);

        GiveVault4626(payable(vaultProxy)).resumeFromEmergency();
        cfg.emergencyShutdown = false;
        cfg.emergencyActivatedAt = 0;

        emit EmergencyStateChanged(vaultId, false, msg.sender);
    }

    /**
     * @notice Executes emergency withdrawal from vault's adapter
     * @dev Requires vault to be in emergency mode. Pulls all assets from adapter.
     *      Optionally clears adapter binding if clearAdapter param is true.
     * @param cfg Storage reference to vault configuration
     * @param vaultId Unique vault identifier
     * @param vaultProxy Address of the vault proxy
     * @param data ABI-encoded EmergencyWithdrawParams
     */
    function _emergencyWithdraw(
        GiveTypes.VaultConfig storage cfg,
        bytes32 vaultId,
        address vaultProxy,
        bytes calldata data
    ) private {
        if (!cfg.emergencyShutdown) revert EmergencyNotActive(vaultId);
        address adapter = address(GiveVault4626(payable(vaultProxy)).activeAdapter());
        if (adapter == address(0)) revert NoActiveAdapter(vaultId);

        EmergencyWithdrawParams memory params;
        if (data.length > 0) {
            params = abi.decode(data, (EmergencyWithdrawParams));
        }

        uint256 withdrawn = GiveVault4626(payable(vaultProxy)).emergencyWithdrawFromAdapter();
        if (params.clearAdapter) {
            GiveVault4626(payable(vaultProxy)).forceClearAdapter();
            cfg.activeAdapter = address(0);
            cfg.adapterId = bytes32(0);
        }

        emit EmergencyWithdrawal(vaultId, adapter, withdrawn, params.clearAdapter);
    }
}
