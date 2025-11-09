// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

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

    /// @notice Maps asset address to reserve data
    mapping(address => ReserveData) public reserves;

    /// @notice Maps asset address to internal state
    mapping(address => ReserveState) internal _reserveStates;

    /// @notice Reserve configuration data (simplified from Aave V3)
    struct ReserveData {
        uint256 configuration;
        uint128 liquidityIndex;
        uint128 currentLiquidityRate;
        uint128 variableBorrowIndex;
        uint128 currentVariableBorrowRate;
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        uint16 id;
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint128 accruedToTreasury;
        uint128 unbacked;
        uint128 isolationModeTotalDebt;
    }

    /// @notice Internal reserve tracking
    struct ReserveState {
        bool initialized;
        uint8 decimals;
    }

    // ============================================
    // CONSTANTS
    // ============================================

    uint256 private constant RAY = 1e27;

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
        require(!_reserveStates[asset].initialized, "Reserve already initialized");

        // Deploy mock aToken
        MockAToken aToken = new MockAToken(asset, decimals, address(this));

        _reserveStates[asset] = ReserveState({initialized: true, decimals: decimals});

        reserves[asset] = ReserveData({
            configuration: 0,
            liquidityIndex: SafeCast.toUint128(RAY), // Start at 1.0
            currentLiquidityRate: 0, // No automatic accrual
            variableBorrowIndex: SafeCast.toUint128(RAY),
            currentVariableBorrowRate: 0,
            currentStableBorrowRate: 0,
            lastUpdateTimestamp: uint40(block.timestamp),
            id: 0,
            aTokenAddress: address(aToken),
            stableDebtTokenAddress: address(0),
            variableDebtTokenAddress: address(0),
            interestRateStrategyAddress: address(0),
            accruedToTreasury: 0,
            unbacked: 0,
            isolationModeTotalDebt: 0
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

        ReserveState storage state = _reserveStates[asset];
        require(state.initialized, "Reserve not initialized");

        // Update liquidity index (simulate interest accrual)
        _updateLiquidityIndex(asset);

        // Transfer assets from user
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Mint aTokens 1:1 (scaled by liquidity index internally)
        MockAToken(reserves[asset].aTokenAddress).mint(onBehalfOf, amount);

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
        ReserveState storage state = _reserveStates[asset];
        require(state.initialized, "Reserve not initialized");

        // Update liquidity index
        _updateLiquidityIndex(asset);

        MockAToken aToken = MockAToken(reserves[asset].aTokenAddress);

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
     * @notice Update liquidity index timestamp
     * @dev In this mock, index only grows via accrueYield (which deposits real assets)
     *      Automatic interest accrual would cause withdrawals to fail due to insufficient backing
     * @param asset Asset to update
     */
    function _updateLiquidityIndex(address asset) internal {
        ReserveData storage reserve = reserves[asset];

        // Just update timestamp - index only grows when yield is manually injected via accrueYield
        if (reserve.lastUpdateTimestamp != block.timestamp) {
            reserve.lastUpdateTimestamp = uint40(block.timestamp);
        }
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get reserve data (Aave V3 interface)
     * @param asset Asset address
     * @return Reserve data struct
     */
    function getReserveData(address asset) external view returns (ReserveData memory) {
        return reserves[asset];
    }

    /**
     * @notice Get reserve normalized income (liquidity index)
     * @param asset Asset address
     * @return Liquidity index scaled by 1e27
     */
    function getReserveNormalizedIncome(address asset) external view returns (uint256) {
        return uint256(reserves[asset].liquidityIndex);
    }

    /**
     * @notice Helper to manually inject yield for testing
     * @dev Simulates Aave interest accrual by increasing the liquidity index
     * @param asset Asset address
     * @param yieldAmount Amount of yield to inject (caller must approve pool first)
     */
    function accrueYield(address asset, uint256 yieldAmount) external {
        ReserveState storage state = _reserveStates[asset];
        require(state.initialized, "Reserve not initialized");
        require(yieldAmount > 0, "Zero yield");

        // Transfer actual underlying tokens into the pool
        IERC20(asset).safeTransferFrom(msg.sender, address(this), yieldAmount);

        MockAToken aToken = MockAToken(reserves[asset].aTokenAddress);
        uint256 scaledSupply = aToken.scaledTotalSupply();
        if (scaledSupply == 0) return;

        // Increase liquidity index proportionally to yield
        // All holders' balances grow proportionally via: balance = scaledBalance * index / RAY
        uint256 oldIndex = uint256(reserves[asset].liquidityIndex);
        uint256 deltaIndex = (yieldAmount * RAY) / scaledSupply;
        reserves[asset].liquidityIndex = SafeCast.toUint128(oldIndex + deltaIndex);
        reserves[asset].lastUpdateTimestamp = uint40(block.timestamp);
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

    mapping(address => uint256) private _scaledBalances;
    uint256 private _scaledTotalSupply;
    uint256 private constant RAY = 1e27;

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
        uint256 index = MockAavePool(POOL).getReserveNormalizedIncome(UNDERLYING_ASSET);
        return (_scaledTotalSupply * index) / RAY;
    }

    function balanceOf(address account) external view returns (uint256) {
        uint256 index = MockAavePool(POOL).getReserveNormalizedIncome(UNDERLYING_ASSET);
        return (_scaledBalances[account] * index) / RAY;
    }

    function scaledBalanceOf(address account) external view returns (uint256) {
        return _scaledBalances[account];
    }

    function scaledTotalSupply() external view returns (uint256) {
        return _scaledTotalSupply;
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
     * @param amount Amount to mint (in asset terms)
     */
    function mint(address account, uint256 amount) external {
        require(msg.sender == POOL, "Only pool can mint");

        // Convert amount to scaled balance using current index
        uint256 index = MockAavePool(POOL).getReserveNormalizedIncome(UNDERLYING_ASSET);
        uint256 scaledAmount = (amount * RAY) / index;

        _scaledBalances[account] += scaledAmount;
        _scaledTotalSupply += scaledAmount;

        emit Mint(account, amount);
        emit Transfer(address(0), account, amount);
    }

    /**
     * @notice Burn aTokens (only callable by pool)
     * @param account Account to burn from
     * @param amount Amount to burn (in asset terms)
     */
    function burn(address account, uint256 amount) external {
        require(msg.sender == POOL, "Only pool can burn");

        // Convert amount to scaled balance using current index
        uint256 index = MockAavePool(POOL).getReserveNormalizedIncome(UNDERLYING_ASSET);
        uint256 scaledAmount = (amount * RAY) / index;

        require(_scaledBalances[account] >= scaledAmount, "Insufficient balance");

        _scaledBalances[account] -= scaledAmount;
        _scaledTotalSupply -= scaledAmount;

        emit Burn(account, amount);
        emit Transfer(account, address(0), amount);
    }

    // ============================================
    // INTERNAL HELPERS
    // ============================================

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");

        // Convert amount to scaled balance
        uint256 index = MockAavePool(POOL).getReserveNormalizedIncome(UNDERLYING_ASSET);
        uint256 scaledAmount = (amount * RAY) / index;

        require(_scaledBalances[from] >= scaledAmount, "Insufficient balance");

        _scaledBalances[from] -= scaledAmount;
        _scaledBalances[to] += scaledAmount;

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
