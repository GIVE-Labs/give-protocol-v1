// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockAavePool
 * @author GIVE Labs
 * @notice Mock Aave V3 pool for testing AaveAdapter
 * @dev Simulates basic Aave lending pool operations:
 *      - supply() - Deposit assets and receive aTokens (1:1 initially)
 *      - withdraw() - Burn aTokens and receive underlying assets
 *      - Simple rebasing aToken that increases balance over time
 *
 *      This is a minimal mock for testing only, not production-ready.
 */
contract MockAavePool {
    using SafeERC20 for IERC20;

    // ============================================
    // STORAGE
    // ============================================

    /// @notice Maps asset address to aToken address
    mapping(address => address) public aTokens;

    /// @notice Maps asset address to reserve data
    mapping(address => ReserveData) public reserves;

    /// @notice Reserve configuration data
    struct ReserveData {
        bool initialized;
        uint8 decimals;
        uint256 liquidityIndex; // Scaled by 1e27 (ray)
        uint256 lastUpdateTimestamp;
    }

    // ============================================
    // CONSTANTS
    // ============================================

    uint256 private constant RAY = 1e27;
    uint256 private constant SECONDS_PER_YEAR = 365 days;
    uint256 private constant DEFAULT_RATE = 5e25; // 5% APY in ray units

    // ============================================
    // EVENTS
    // ============================================

    event Supply(address indexed reserve, address user, uint256 amount);
    event Withdraw(address indexed reserve, address user, uint256 amount);
    event ReserveInitialized(address indexed reserve, address indexed aToken);

    // ============================================
    // INITIALIZATION
    // ============================================

    /**
     * @notice Initialize a reserve with its aToken
     * @param asset Underlying asset address
     * @param decimals Asset decimals
     */
    function initReserve(address asset, uint8 decimals) external {
        require(!reserves[asset].initialized, "Reserve already initialized");

        // Deploy mock aToken
        MockAToken aToken = new MockAToken(asset, decimals, address(this));

        aTokens[asset] = address(aToken);
        reserves[asset] = ReserveData({
            initialized: true,
            decimals: decimals,
            liquidityIndex: RAY, // Start at 1.0
            lastUpdateTimestamp: block.timestamp
        });

        emit ReserveInitialized(asset, address(aToken));
    }

    // ============================================
    // LENDING OPERATIONS
    // ============================================

    /**
     * @notice Supply assets to the pool
     * @param asset Asset to supply
     * @param amount Amount to supply
     * @param onBehalfOf Address to receive aTokens
     * @param referralCode Referral code (unused)
     */
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external {
        referralCode; // Silence unused warning

        ReserveData storage reserve = reserves[asset];
        require(reserve.initialized, "Reserve not initialized");

        // Update liquidity index (simulate interest accrual)
        _updateLiquidityIndex(asset);

        // Transfer assets from user
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Mint aTokens 1:1 (scaled by liquidity index internally)
        MockAToken(aTokens[asset]).mint(onBehalfOf, amount);

        emit Supply(asset, onBehalfOf, amount);
    }

    /**
     * @notice Withdraw assets from the pool
     * @param asset Asset to withdraw
     * @param amount Amount to withdraw (uint256 max = withdraw all)
     * @param to Address to receive assets
     * @return Actual amount withdrawn
     */
    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        ReserveData storage reserve = reserves[asset];
        require(reserve.initialized, "Reserve not initialized");

        // Update liquidity index
        _updateLiquidityIndex(asset);

        MockAToken aToken = MockAToken(aTokens[asset]);

        // Handle max withdrawal
        uint256 userBalance = aToken.balanceOf(msg.sender);
        uint256 amountToWithdraw = (amount == type(uint256).max) ? userBalance : amount;

        require(amountToWithdraw <= userBalance, "Insufficient aToken balance");

        // Burn aTokens
        aToken.burn(msg.sender, amountToWithdraw);

        // Transfer underlying assets
        IERC20(asset).safeTransfer(to, amountToWithdraw);

        emit Withdraw(asset, to, amountToWithdraw);

        return amountToWithdraw;
    }

    // ============================================
    // INTERNAL HELPERS
    // ============================================

    /**
     * @notice Update liquidity index to simulate interest accrual
     * @param asset Asset to update
     */
    function _updateLiquidityIndex(address asset) internal {
        ReserveData storage reserve = reserves[asset];

        if (reserve.lastUpdateTimestamp == block.timestamp) {
            return; // Already updated this block
        }

        uint256 timeDelta = block.timestamp - reserve.lastUpdateTimestamp;

        // Simple linear interest: index increases by DEFAULT_RATE per second
        uint256 interest = (reserve.liquidityIndex * DEFAULT_RATE * timeDelta) / (RAY * SECONDS_PER_YEAR);
        reserve.liquidityIndex += interest;
        reserve.lastUpdateTimestamp = block.timestamp;
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get reserve normalized income (liquidity index)
     * @param asset Asset address
     * @return Liquidity index scaled by 1e27
     */
    function getReserveNormalizedIncome(address asset) external view returns (uint256) {
        return reserves[asset].liquidityIndex;
    }
}

/**
 * @title MockAToken
 * @notice Mock rebasing aToken that represents supplied assets
 * @dev Simplified version of Aave's aToken with basic rebasing logic
 */
contract MockAToken {
    using SafeERC20 for IERC20;

    // ============================================
    // STORAGE
    // ============================================

    string public name;
    string public symbol;
    uint8 public decimals;

    address public immutable UNDERLYING_ASSET;
    address public immutable POOL;

    mapping(address => uint256) private _balances;
    uint256 private _totalSupply;

    // ============================================
    // EVENTS
    // ============================================

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Mint(address indexed account, uint256 amount);
    event Burn(address indexed account, uint256 amount);

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(address asset, uint8 assetDecimals, address pool) {
        UNDERLYING_ASSET = asset;
        POOL = pool;
        decimals = assetDecimals;

        string memory assetSymbol = _getSymbol(asset);
        name = string(abi.encodePacked("Aave ", assetSymbol));
        symbol = string(abi.encodePacked("a", assetSymbol));
    }

    // ============================================
    // ERC20 INTERFACE
    // ============================================

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    // ============================================
    // ATOKEN OPERATIONS
    // ============================================

    /**
     * @notice Mint aTokens (only callable by pool)
     * @param account Account to mint to
     * @param amount Amount to mint
     */
    function mint(address account, uint256 amount) external {
        require(msg.sender == POOL, "Only pool can mint");
        _balances[account] += amount;
        _totalSupply += amount;
        emit Mint(account, amount);
        emit Transfer(address(0), account, amount);
    }

    /**
     * @notice Burn aTokens (only callable by pool)
     * @param account Account to burn from
     * @param amount Amount to burn
     */
    function burn(address account, uint256 amount) external {
        require(msg.sender == POOL, "Only pool can burn");
        require(_balances[account] >= amount, "Insufficient balance");
        _balances[account] -= amount;
        _totalSupply -= amount;
        emit Burn(account, amount);
        emit Transfer(account, address(0), amount);
    }

    // ============================================
    // INTERNAL HELPERS
    // ============================================

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");
        require(_balances[from] >= amount, "Insufficient balance");

        _balances[from] -= amount;
        _balances[to] += amount;

        emit Transfer(from, to, amount);
    }

    function _getSymbol(address asset) internal view returns (string memory) {
        // Try calling symbol() via low-level call
        (bool success, bytes memory data) = asset.staticcall(abi.encodeWithSignature("symbol()"));
        if (success && data.length > 0) {
            return abi.decode(data, (string));
        }
        return "TOKEN";
    }
}
