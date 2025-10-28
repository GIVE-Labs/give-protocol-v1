// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title GiveErrors
 * @author GIVE Labs
 * @notice Custom errors for the GIVE Protocol contracts
 * @dev Organized by functional area for better clarity. Using custom errors
 *      instead of strings saves gas and provides type-safe error handling.
 */
library GiveErrors {
    // ============================================
    // VAULT ERRORS
    // ============================================

    /// @notice Vault operations are paused
    error VaultPaused();

    /// @notice New investments into yield adapters are paused
    error InvestPaused();

    /// @notice Yield harvesting operations are paused
    error HarvestPaused();

    /// @notice Vault does not have sufficient cash reserves for operation
    error InsufficientCash();

    /// @notice Adapter address is invalid or not approved
    error InvalidAdapter();

    /// @notice No adapter has been configured for this vault
    error AdapterNotSet();

    /// @notice Cash buffer percentage is too high (exceeds maximum)
    error CashBufferTooHigh();

    /// @notice Cash buffer configuration is invalid
    error InvalidCashBuffer();

    /// @notice Operation requires non-zero assets
    error ZeroAssets();

    /// @notice Operation requires non-zero shares
    error ZeroShares();

    /**
     * @notice Loss from operation exceeds maximum acceptable loss
     * @param actual Actual loss amount in basis points
     * @param max Maximum allowed loss in basis points
     */
    error ExcessiveLoss(uint256 actual, uint256 max);

    /**
     * @notice Slippage from operation exceeds tolerance
     * @param actual Actual slippage in basis points
     * @param max Maximum allowed slippage in basis points
     */
    error SlippageExceeded(uint256 actual, uint256 max);

    /// @notice Receiver address is invalid (e.g., zero address)
    error InvalidReceiver();

    /// @notice Owner address is invalid (e.g., zero address)
    error InvalidOwner();

    /// @notice Caller does not have sufficient allowance
    error InsufficientAllowance();

    /// @notice Account does not have sufficient balance
    error InsufficientBalance();

    /// @notice Emergency mode is not active
    error NotInEmergency();

    /// @notice Grace period for emergency withdrawals is still active
    error GracePeriodActive();

    /// @notice Grace period for operation has expired
    error GracePeriodExpired();

    /// @notice Operation cannot proceed while contract is paused
    error EnforcedPause();

    // ============================================
    // ADAPTER ERRORS
    // ============================================

    /// @notice Caller is not the vault
    error OnlyVault();

    /// @notice Adapter is paused and cannot process operations
    error AdapterPaused();

    /// @notice External protocol has insufficient liquidity for operation
    error InsufficientLiquidity();

    /// @notice Investment amount is invalid (e.g., zero or exceeds limits)
    error InvalidInvestAmount();

    /// @notice Divest amount is invalid (e.g., zero or exceeds available)
    error InvalidDivestAmount();

    /// @notice External protocol is paused
    error ProtocolPaused();

    /// @notice Oracle price data is stale
    error OracleStale();

    /// @notice Price deviation exceeds acceptable threshold
    error PriceDeviation();

    /// @notice Asset is invalid or not supported
    error InvalidAsset();

    /// @notice Adapter has not been initialized
    error AdapterNotInitialized();

    // ============================================
    // NGO REGISTRY ERRORS
    // ============================================

    /// @notice NGO is not approved in the registry
    error NGONotApproved();

    /// @notice NGO is already approved
    error NGOAlreadyApproved();

    /// @notice NGO is not registered in the system
    error NGONotRegistered();

    /// @notice NGO is already registered
    error NGOAlreadyRegistered();

    /// @notice NGO address is invalid (e.g., zero address)
    error InvalidNGOAddress();

    /// @notice NGO removal operation failed
    error NGORemovalFailed();

    /// @notice Caller is not authorized to manage NGOs
    error UnauthorizedNGOManager();

    /// @notice Metadata CID is invalid or empty
    error InvalidMetadataCid();

    /// @notice KYC hash is invalid
    error InvalidKycHash();

    /// @notice Attestor address is invalid
    error InvalidAttestor();

    /// @notice Timelock period has not yet elapsed
    error TimelockNotReady();

    /// @notice No timelock operation is pending
    error NoTimelockPending();

    /// @notice Timelock is already set for this operation
    error TimelockAlreadySet();

    // ============================================
    // DONATION & PAYOUT ROUTER ERRORS
    // ============================================

    /// @notice Donation amount is invalid (e.g., zero or negative)
    error InvalidDonationAmount();

    /// @notice Donation transfer failed
    error DonationFailed();

    /// @notice No NGO has been configured for donations
    error NoNGOConfigured();

    /// @notice Fee recipient address is invalid
    error InvalidFeeRecipient();

    /// @notice Fee exceeds maximum allowed percentage
    error FeeTooHigh();

    /// @notice Fee in basis points is invalid
    error InvalidFeeBps();

    /// @notice No funds available to distribute
    error NoFundsToDistribute();

    /// @notice NGO selection is invalid
    error InvalidNGO();

    /// @notice Donation router is paused
    error DonationRouterPaused();

    /**
     * @notice Fee increase exceeds maximum allowed increment
     * @param increase Proposed fee increase in basis points
     * @param maxAllowed Maximum allowed increase in basis points
     */
    error FeeIncreaseTooLarge(uint256 increase, uint256 maxAllowed);

    /**
     * @notice Fee change with specified nonce not found
     * @param nonce The fee change nonce that was not found
     */
    error FeeChangeNotFound(uint256 nonce);

    // ============================================
    // STRATEGY MANAGER ERRORS
    // ============================================

    /// @notice Slippage tolerance in basis points is invalid
    error InvalidSlippageBps();

    /// @notice Maximum loss in basis points is invalid
    error InvalidMaxLossBps();

    /// @notice Parameter value is out of acceptable range
    error ParameterOutOfRange();

    /// @notice Caller is not authorized as strategy manager
    error UnauthorizedManager();

    /// @notice No strategy has been configured
    error StrategyNotSet();

    /// @notice Strategy configuration is invalid
    error InvalidStrategy();

    // ============================================
    // ACCESS CONTROL ERRORS
    // ============================================

    /// @notice Role identifier is invalid
    error InvalidRole();

    /// @notice Role has already been granted to address
    error RoleAlreadyGranted();

    /// @notice Role has not been granted to address
    error RoleNotGranted();

    /// @notice Cannot renounce role if you are the last admin
    error CannotRenounceLastAdmin();

    // ============================================
    // GENERAL ERRORS
    // ============================================

    /// @notice Address is zero address
    error ZeroAddress();

    /// @notice Amount is invalid for operation
    error InvalidAmount();

    /// @notice Amount is zero but must be non-zero
    error ZeroAmount();

    /// @notice Token transfer failed
    error TransferFailed();

    /// @notice Contract is paused
    error ContractPaused();

    /// @notice Reentrancy attack detected
    error ReentrancyDetected();

    /// @notice Configuration is invalid
    error InvalidConfiguration();

    /// @notice Operation is not allowed in current state
    error OperationNotAllowed();

    /**
     * @notice Timelock has not expired yet
     * @param currentTime Current block timestamp
     * @param effectiveTime Time when operation becomes effective
     */
    error TimelockNotExpired(uint256 currentTime, uint256 effectiveTime);

    /// @notice Timestamp value is invalid
    error InvalidTimestamp();

    /// @notice Array lengths do not match
    error ArrayLengthMismatch();

    /// @notice Index is out of bounds
    error IndexOutOfBounds();

    /// @notice Mathematical operation would overflow
    error MathOverflow();

    /// @notice Mathematical operation would underflow
    error MathUnderflow();

    /// @notice Division by zero attempted
    error DivisionByZero();

    // ============================================
    // USER PREFERENCE ERRORS
    // ============================================

    /**
     * @notice Allocation percentage is invalid (must be 0-100)
     * @param percentage The invalid percentage value provided
     */
    error InvalidAllocationPercentage(uint8 percentage);

    /**
     * @notice Caller is not authorized for this operation
     * @param caller Address of the unauthorized caller
     */
    error UnauthorizedCaller(address caller);
}
