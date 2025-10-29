// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IYieldAdapter.sol";
import "../utils/ACLShim.sol";

/**
 * @title MockYieldAdapter
 * @author GIVE Labs
 * @notice Mock yield adapter for testing and development
 * @dev Simulates yield generation with configurable rates and loss scenarios.
 *      Enables testing without external protocol dependencies.
 *
 *      Mock Features:
 *      - Configurable yield rate (basis points per harvest)
 *      - Simulated loss scenarios for negative testing
 *      - Manual yield injection for controlled testing
 *      - No external protocol dependencies
 *
 *      Use Cases:
 *      - Unit testing vault harvest logic
 *      - Integration testing without mainnet forks
 *      - Simulating various yield scenarios (high/low/negative)
 *      - Gas estimation without protocol overhead
 *      - Development and debugging
 *
 *      Test Scenarios Supported:
 *      1. Normal yield: Set yieldRate > 0, call addYield to inject profit
 *      2. Loss scenario: Enable simulateLoss with lossRate
 *      3. Zero yield: Default state with no yield added
 *      4. High yield: Set high yieldRate and inject large amounts
 *
 *      Security Notes:
 *      - For testing only - not for production use
 *      - Admin controls allow manipulation of balances for testing
 *      - ACL-protected to prevent unauthorized modifications
 */
contract MockYieldAdapter is IYieldAdapter, ACLShim {
    using SafeERC20 for IERC20;

    // ============================================
    // CONSTANTS
    // ============================================

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // ============================================
    // IMMUTABLE STATE
    // ============================================

    IERC20 private immutable _asset;
    address private immutable _vault;

    // ============================================
    // MUTABLE STATE
    // ============================================

    uint256 private _totalAssets;
    uint256 private _yieldRate; // Basis points per harvest (e.g., 100 = 1%)
    uint256 private _lastHarvestTime;
    bool private _simulateLoss;
    uint256 private _lossRate; // Basis points for simulated loss

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /**
     * @notice Initializes the mock yield adapter
     * @dev Sets up ACL roles and default yield rate.
     *      Default yield rate is 2.5% (250 bps) per harvest.
     * @param asset_ The underlying asset token
     * @param vault_ The vault address authorized to call this adapter
     * @param admin The admin address to receive DEFAULT_ADMIN_ROLE
     */
    constructor(address asset_, address vault_, address admin) {
        _asset = IERC20(asset_);
        _vault = vault_;
        _yieldRate = 250; // Default 2.5% yield per harvest
        _lastHarvestTime = block.timestamp;
        _simulateLoss = false;
        _lossRate = 0;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(VAULT_ROLE, vault_);
        _grantRole(EMERGENCY_ROLE, admin);
    }

    // ============================================
    // IYIELDADAPTER IMPLEMENTATION
    // ============================================

    /**
     * @notice Returns the underlying asset
     * @return IERC20 interface of the underlying asset
     */
    function asset() external view override returns (IERC20) {
        return _asset;
    }

    /**
     * @notice Returns total assets under management
     * @return Total assets tracked by adapter
     */
    function totalAssets() external view override returns (uint256) {
        return _totalAssets;
    }

    /**
     * @notice Returns the vault address
     * @return Address of the authorized vault
     */
    function vault() external view override returns (address) {
        return _vault;
    }

    /**
     * @notice Invests assets into the mock adapter
     * @dev Transfers tokens from vault to adapter and updates accounting.
     *      Validates sufficient balance after transfer.
     * @param assets Amount to invest
     */
    function invest(uint256 assets) external override onlyRole(VAULT_ROLE) {
        require(assets > 0, "MockYieldAdapter: Cannot invest zero assets");

        uint256 requiredBalance = _totalAssets + assets;
        uint256 preBalance = _asset.balanceOf(address(this));

        if (preBalance < requiredBalance) {
            _asset.safeTransferFrom(_vault, address(this), assets);
            preBalance = _asset.balanceOf(address(this));
        }

        require(preBalance >= requiredBalance, "MockYieldAdapter: Insufficient deposit");

        _totalAssets += assets;

        emit Invested(assets);
    }

    /**
     * @notice Divests assets from the mock adapter
     * @dev Transfers tokens back to vault and updates accounting.
     *      Caps withdrawal at available assets.
     * @param assets Amount to divest
     * @return returned Actual amount returned (capped at available)
     */
    function divest(uint256 assets) external override onlyRole(VAULT_ROLE) returns (uint256 returned) {
        require(assets > 0, "MockYieldAdapter: Cannot divest zero assets");
        require(assets <= _totalAssets, "MockYieldAdapter: Insufficient assets");

        returned = assets;
        _totalAssets -= assets;

        _asset.safeTransfer(_vault, returned);

        emit Divested(assets, returned);
    }

    /**
     * @notice Harvests yield and realizes profit/loss
     * @dev Calculates profit/loss based on actual balance vs tracked assets.
     *      Supports both profit distribution and loss simulation.
     * @return profit Amount of profit realized
     * @return loss Amount of loss realized
     */
    function harvest() external override onlyRole(VAULT_ROLE) returns (uint256 profit, uint256 loss) {
        if (_totalAssets == 0) {
            return (0, 0);
        }

        uint256 balance = _asset.balanceOf(address(this));

        if (_simulateLoss) {
            // Loss simulation mode
            loss = (balance * _lossRate) / 10_000;
            if (loss > balance) {
                loss = balance;
            }
            _totalAssets = balance - loss;
            profit = 0;
        } else {
            // Normal profit mode
            loss = 0;
            if (balance > _totalAssets) {
                profit = balance - _totalAssets;
                _totalAssets = balance - profit;
                if (profit > 0) {
                    _asset.safeTransfer(_vault, profit);
                }
            } else {
                _totalAssets = balance;
                profit = 0;
            }
        }

        _lastHarvestTime = block.timestamp;
        emit Harvested(profit, loss);
    }

    /**
     * @notice Emergency withdrawal of all assets
     * @dev Returns full tracked assets to vault, resets accounting.
     * @return returned Amount of assets returned to vault
     */
    function emergencyWithdraw() external override onlyRole(EMERGENCY_ROLE) returns (uint256 returned) {
        returned = _totalAssets;
        _totalAssets = 0;

        if (returned > 0) {
            _asset.safeTransfer(_vault, returned);
        }

        emit EmergencyWithdraw(returned);
    }

    // ============================================
    // TEST CONFIGURATION FUNCTIONS
    // ============================================

    /**
     * @notice Sets the yield rate for testing
     * @dev Configures simulated yield generation rate. Max 100% (10000 bps).
     * @param yieldRate_ Yield rate in basis points (100 = 1%)
     */
    function setYieldRate(uint256 yieldRate_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(yieldRate_ <= 10000, "MockYieldAdapter: Yield rate too high");
        _yieldRate = yieldRate_;
    }

    /**
     * @notice Configures loss simulation for negative testing
     * @dev Enables testing of loss scenarios and vault loss handling.
     *      When enabled, harvest() will report losses instead of profits.
     * @param simulateLoss_ Whether to simulate loss
     * @param lossRate_ Loss rate in basis points (100 = 1% loss per harvest)
     */
    function setLossSimulation(bool simulateLoss_, uint256 lossRate_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(lossRate_ <= 10000, "MockYieldAdapter: Loss rate too high");
        _simulateLoss = simulateLoss_;
        _lossRate = lossRate_;
    }

    /**
     * @notice Sets the total assets directly for testing
     * @dev Useful for testing rebalancing logic without actual deposits.
     * @param totalAssets_ The total assets amount to set
     */
    function setTotalAssets(uint256 totalAssets_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _totalAssets = totalAssets_;
    }

    /**
     * @notice Manually adds yield tokens for controlled testing
     * @dev Simulates external yield generation by accepting token transfers.
     *      Tokens are added to adapter balance but not to _totalAssets,
     *      creating a profit that will be harvested next call.
     * @param amount Amount of yield to add (creates harvestable profit)
     */
    function addYield(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (amount > 0) {
            _asset.safeTransferFrom(msg.sender, address(this), amount);
            // Don't add to _totalAssets - this represents external yield
        }
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Returns current yield rate configuration
     * @return Yield rate in basis points
     */
    function getYieldRate() external view returns (uint256) {
        return _yieldRate;
    }

    /**
     * @notice Returns loss simulation configuration
     * @return simulateLoss_ Whether loss simulation is enabled
     * @return lossRate_ Loss rate in basis points
     */
    function getLossSimulation() external view returns (bool simulateLoss_, uint256 lossRate_) {
        return (_simulateLoss, _lossRate);
    }
}
