// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Base02_DeployVaultsAndAdapters} from "./Base02_DeployVaultsAndAdapters.t.sol";
import {GiveTypes} from "../../src/types/GiveTypes.sol";
import {CampaignRegistry} from "../../src/registry/CampaignRegistry.sol";
import {StrategyRegistry} from "../../src/registry/StrategyRegistry.sol";
import {CampaignVault4626} from "../../src/vault/CampaignVault4626.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/**
 * @title Base03_DeployComprehensiveEnvironment
 * @author GIVE Labs
 * @notice Comprehensive test environment with campaigns, NGOs, strategies, and funding
 * @dev Inherits Base02 and adds:
 *      - Multiple registered strategies (Aave USDC, Compounding DAI)
 *      - Multiple approved NGOs (Red Cross, UNICEF, Save the Children)
 *      - Multiple campaign proposals (Climate Action, Education Fund, Medical Aid)
 *      - Properly funded scenarios (donated amounts, staked amounts)
 *      - Ready-to-use checkpoint governance
 *
 *      This provides a fully operational protocol environment for integration testing.
 */
contract Base03_DeployComprehensiveEnvironment is Base02_DeployVaultsAndAdapters {
    // ============================================================
    // STRATEGIES
    // ============================================================

    bytes32 public aaveUsdcStrategyId;
    bytes32 public compoundingDaiStrategyId;

    // ============================================================
    // CAMPAIGNS
    // ============================================================

    bytes32 public campaignClimateId;
    bytes32 public campaignEducationId;
    bytes32 public campaignMedicalId;

    // Campaign vaults
    address public climateVault;
    address public educationVault;
    address public medicalVault;

    // ============================================================
    // TEST SCENARIOS
    // ============================================================

    // Donation amounts
    uint256 public constant DONATION_SMALL = 1000e6; // $1,000 USDC
    uint256 public constant DONATION_MEDIUM = 10_000e6; // $10,000 USDC
    uint256 public constant DONATION_LARGE = 100_000e6; // $100,000 USDC

    // Stake amounts for governance
    uint256 public constant STAKE_SMALL = 100e6; // $100 USDC
    uint256 public constant STAKE_MEDIUM = 1000e6; // $1,000 USDC
    uint256 public constant STAKE_LARGE = 10_000e6; // $10,000 USDC

    // ============================================================
    // SETUP
    // ============================================================

    function setUp() public virtual override {
        super.setUp(); // Deploy vaults and adapters from Base02

        // ========================================
        // STEP 1: Register Strategies
        // ========================================

        aaveUsdcStrategyId = keccak256("strategy.aave.usdc");
        compoundingDaiStrategyId = keccak256("strategy.compounding.dai");

        vm.startPrank(strategyAdmin);

        strategyRegistry.registerStrategy(
            StrategyRegistry.StrategyInput({
                id: aaveUsdcStrategyId,
                adapter: address(aaveUsdcAdapter),
                riskTier: keccak256("LOW"),
                maxTvl: 10_000_000e6, // $10M max TVL
                metadataHash: keccak256("ipfs://QmAaveUSDC")
            })
        );

        strategyRegistry.registerStrategy(
            StrategyRegistry.StrategyInput({
                id: compoundingDaiStrategyId,
                adapter: address(compoundingDaiAdapter),
                riskTier: keccak256("MEDIUM"),
                maxTvl: 5_000_000e18, // $5M max TVL
                metadataHash: keccak256("ipfs://QmCompoundingDAI")
            })
        );

        vm.stopPrank();

        emit log_string("Strategies registered");

        // ========================================
        // STEP 2: Register NGOs
        // ========================================

        // Grant NGO_MANAGER_ROLE to campaignAdmin
        bytes32 NGO_MANAGER_ROLE = ngoRegistry.NGO_MANAGER_ROLE();
        vm.startPrank(admin);
        aclManager.createRole(NGO_MANAGER_ROLE, admin);
        aclManager.grantRole(NGO_MANAGER_ROLE, campaignAdmin);
        vm.stopPrank();

        vm.startPrank(campaignAdmin);

        // Red Cross
        ngoRegistry.addNGO(
            ngo1, // NGO address
            "QmRedCross", // metadataCid
            keccak256("verified-attestation-redcross"), // kycHash
            campaignAdmin // attestor
        );

        // UNICEF
        ngoRegistry.addNGO(
            ngo2, // NGO address
            "QmUNICEF", // metadataCid
            keccak256("verified-attestation-unicef"), // kycHash
            campaignAdmin // attestor
        );

        // Save the Children
        ngoRegistry.addNGO(
            donor1, // Using donor1 as NGO for testing
            "QmSaveChildren", // metadataCid
            keccak256("verified-attestation-savechildren"), // kycHash
            campaignAdmin // attestor
        );

        vm.stopPrank();

        emit log_string("NGOs registered");

        // ========================================
        // STEP 3: Propose Campaigns
        // ========================================

        campaignClimateId = keccak256("campaign.climate");
        campaignEducationId = keccak256("campaign.education");
        campaignMedicalId = keccak256("campaign.medical");

        vm.startPrank(campaignCreator);

        // Climate Action Campaign
        campaignRegistry.submitCampaign{
            value: 0.005 ether
        }(
            CampaignRegistry.CampaignInput({
                id: campaignClimateId,
                payoutRecipient: ngo1, // Red Cross payout address
                strategyId: aaveUsdcStrategyId,
                metadataHash: keccak256("Climate Action 2025"),
                metadataCID: "QmClimateActionCampaign",
                targetStake: 100_000e6, // $100k target
                minStake: 1000e6, // $1k minimum
                fundraisingStart: uint64(block.timestamp),
                fundraisingEnd: uint64(block.timestamp + 30 days)
            })
        );

        // Education Fund Campaign
        campaignRegistry.submitCampaign{
            value: 0.005 ether
        }(
            CampaignRegistry.CampaignInput({
                id: campaignEducationId,
                payoutRecipient: ngo2, // UNICEF payout address
                strategyId: aaveUsdcStrategyId,
                metadataHash: keccak256("Global Education Fund"),
                metadataCID: "QmEducationCampaign",
                targetStake: 250_000e6, // $250k target
                minStake: 5000e6, // $5k minimum
                fundraisingStart: uint64(block.timestamp),
                fundraisingEnd: uint64(block.timestamp + 60 days)
            })
        );

        // Medical Aid Campaign
        campaignRegistry.submitCampaign{
            value: 0.005 ether
        }(
            CampaignRegistry.CampaignInput({
                id: campaignMedicalId,
                payoutRecipient: donor1, // Save the Children payout address
                strategyId: compoundingDaiStrategyId,
                metadataHash: keccak256("Emergency Medical Aid"),
                metadataCID: "QmMedicalCampaign",
                targetStake: 150_000e18, // $150k target (DAI)
                minStake: 2000e18, // $2k minimum (DAI)
                fundraisingStart: uint64(block.timestamp),
                fundraisingEnd: uint64(block.timestamp + 45 days)
            })
        );

        vm.stopPrank();

        emit log_string("Campaigns proposed");

        // ========================================
        // STEP 4: Approve Campaigns
        // ========================================

        vm.startPrank(campaignAdmin);

        // Approve Climate campaign
        campaignRegistry.approveCampaign(campaignClimateId, campaignAdmin); // curator
        climateVault = campaignRegistry.getCampaign(campaignClimateId).vault;
        assertTrue(climateVault != address(0), "Climate vault should be deployed");

        // Approve Education campaign
        campaignRegistry.approveCampaign(campaignEducationId, campaignAdmin); // curator
        educationVault = campaignRegistry.getCampaign(campaignEducationId).vault;
        assertTrue(educationVault != address(0), "Education vault should be deployed");

        // Approve Medical campaign
        campaignRegistry.approveCampaign(campaignMedicalId, campaignAdmin); // curator
        medicalVault = campaignRegistry.getCampaign(campaignMedicalId).vault;
        assertTrue(medicalVault != address(0), "Medical vault should be deployed");

        vm.stopPrank();

        emit log_named_address("Climate campaign vault at", climateVault);
        emit log_named_address("Education campaign vault at", educationVault);
        emit log_named_address("Medical campaign vault at", medicalVault);

        // ========================================
        // STEP 5: Register Campaign Vaults with PayoutRouter
        // ========================================

        // Grant VAULT_MANAGER_ROLE to campaignAdmin
        bytes32 VAULT_MANAGER_ROLE = payoutRouter.VAULT_MANAGER_ROLE();
        vm.startPrank(admin);
        aclManager.createRole(VAULT_MANAGER_ROLE, admin);
        aclManager.grantRole(VAULT_MANAGER_ROLE, campaignAdmin);
        vm.stopPrank();

        vm.startPrank(campaignAdmin);

        // Register vaults with PayoutRouter (requires campaignId)
        payoutRouter.registerCampaignVault(climateVault, campaignClimateId);
        payoutRouter.registerCampaignVault(educationVault, campaignEducationId);
        payoutRouter.registerCampaignVault(medicalVault, campaignMedicalId);

        // Note: Valid allocations [50%, 75%, 100%] are set during PayoutRouter initialization

        vm.stopPrank();

        emit log_string("Campaign vaults registered with PayoutRouter");

        // ========================================
        // STEP 6: Fund Adapters with Initial Liquidity
        // ========================================

        // Fund Aave pool with USDC liquidity for lending
        usdc.mint(address(aavePool), 1_000_000e6);

        // Simulate yield generation in adapters
        usdc.mint(address(aaveUsdcAdapter), 10_000e6); // $10k yield
        dai.mint(address(compoundingDaiAdapter), 10_000e18); // $10k yield

        emit log_string("Adapters funded with initial liquidity");

        // ========================================
        // STEP 7: Set Up Initial Stakes for Governance
        // ========================================

        // NOTE: Staking is done by depositing into campaign vaults (donating)
        // Voting power is proportional to vault shares held
        // Individual TestAction tests will demonstrate full donation → staking → voting flow

        emit log_string("Base environment setup complete - ready for integration tests");
    }

    // ============================================================
    // VALIDATION HELPERS (INTERNAL TO AVOID AUTO-RUN)
    // ============================================================

    /**
     * @notice Validates strategy registrations
     * @dev Internal to avoid running as standalone test
     */
    function _validateStrategies() internal view {
        GiveTypes.StrategyConfig memory aaveStrategy = strategyRegistry.getStrategy(aaveUsdcStrategyId);
        assertEq(aaveStrategy.adapter, address(aaveUsdcAdapter), "Aave strategy adapter mismatch");
        assertTrue(aaveStrategy.exists, "Aave strategy should exist");
        assertEq(uint8(aaveStrategy.status), uint8(GiveTypes.StrategyStatus.Active), "Aave strategy should be active");

        GiveTypes.StrategyConfig memory compoundingStrategy = strategyRegistry.getStrategy(compoundingDaiStrategyId);
        assertEq(compoundingStrategy.adapter, address(compoundingDaiAdapter), "Compounding strategy adapter mismatch");
        assertTrue(compoundingStrategy.exists, "Compounding strategy should exist");
    }

    /**
     * @notice Validates NGO registrations
     * @dev Internal to avoid running as standalone test
     */
    function _validateNGOs() internal view {
        assertTrue(ngoRegistry.isApproved(ngo1), "Red Cross should be approved");
        assertTrue(ngoRegistry.isApproved(ngo2), "UNICEF should be approved");
        assertTrue(ngoRegistry.isApproved(donor1), "Save the Children should be approved");
    }

    /**
     * @notice Validates campaign proposals and approvals
     * @dev Internal to avoid running as standalone test
     */
    function _validateCampaigns() internal view {
        // Climate campaign
        GiveTypes.CampaignConfig memory climate = campaignRegistry.getCampaign(campaignClimateId);
        assertEq(uint8(climate.status), uint8(GiveTypes.CampaignStatus.Active), "Climate campaign should be active");
        assertEq(climate.vault, climateVault, "Climate vault mismatch");

        // Education campaign
        GiveTypes.CampaignConfig memory education = campaignRegistry.getCampaign(campaignEducationId);
        assertEq(uint8(education.status), uint8(GiveTypes.CampaignStatus.Active), "Education campaign should be active");
        assertEq(education.vault, educationVault, "Education vault mismatch");

        // Medical campaign
        GiveTypes.CampaignConfig memory medical = campaignRegistry.getCampaign(campaignMedicalId);
        assertEq(uint8(medical.status), uint8(GiveTypes.CampaignStatus.Active), "Medical campaign should be active");
        assertEq(medical.vault, medicalVault, "Medical vault mismatch");
    }

    /**
     * @notice Validates PayoutRouter vault registrations
     * @dev Internal to avoid running as standalone test
     */
    function _validatePayoutRouter() internal view override {
        // Verify vaults are registered by checking they have associated campaigns
        assertEq(payoutRouter.getVaultCampaign(climateVault), campaignClimateId, "Climate vault campaign mismatch");
        assertEq(
            payoutRouter.getVaultCampaign(educationVault), campaignEducationId, "Education vault campaign mismatch"
        );
        assertEq(payoutRouter.getVaultCampaign(medicalVault), campaignMedicalId, "Medical vault campaign mismatch");
    }

    /**
     * @notice Validates initial governance stakes
     * @dev Internal to avoid running as standalone test
     * @dev NOTE: Staking is performed through campaign vault deposits in actual tests
     */
    function _validateGovernanceStakes() internal view {
        // This validation will be used in TestAction tests after donations
        // For now, just verify campaigns are set up correctly
        assertTrue(climateVault != address(0), "Climate vault should exist");
        assertTrue(educationVault != address(0), "Education vault should exist");
        assertTrue(medicalVault != address(0), "Medical vault should exist");
    }

    // ============================================================
    // HELPER FUNCTIONS FOR TEST ACTIONS
    // ============================================================

    /**
     * @notice Helper to donate to a campaign vault
     * @param donor Address of the donor
     * @param vault Campaign vault address
     * @param asset Asset to donate
     * @param amount Amount to donate
     * @return shares Shares received
     */
    function _donateToVault(address donor, address vault, address asset, uint256 amount)
        internal
        returns (uint256 shares)
    {
        vm.startPrank(donor);
        MockERC20(asset).approve(vault, amount);
        shares = CampaignVault4626(payable(vault)).deposit(amount, donor);
        vm.stopPrank();
    }

    /**
     * @notice Helper to schedule a checkpoint for a campaign
     * @param campaign Campaign ID
     * @param windowStart Voting window start timestamp
     * @param windowEnd Voting window end timestamp
     * @param quorumBps Quorum requirement in basis points
     * @return checkpointIndex Index of the scheduled checkpoint
     */
    function _scheduleCheckpoint(bytes32 campaign, uint64 windowStart, uint64 windowEnd, uint16 quorumBps)
        internal
        returns (uint256 checkpointIndex)
    {
        vm.prank(campaignCreator);
        CampaignRegistry.CheckpointInput memory input = CampaignRegistry.CheckpointInput({
            windowStart: windowStart, windowEnd: windowEnd, executionDeadline: windowEnd + 7 days, quorumBps: quorumBps
        });
        return campaignRegistry.scheduleCheckpoint(campaign, input);
    }

    /**
     * @notice Helper to vote on a checkpoint
     * @param voter Address of the voter
     * @param campaign Campaign ID
     * @param checkpointIndex Checkpoint index
     * @param support Vote in favor (true) or against (false)
     */
    function _voteOnCheckpoint(address voter, bytes32 campaign, uint256 checkpointIndex, bool support) internal {
        vm.prank(voter);
        campaignRegistry.voteOnCheckpoint(campaign, checkpointIndex, support);
    }

    /**
     * @notice Helper to finalize a checkpoint
     * @param campaign Campaign ID
     * @param checkpointIndex Checkpoint index
     */
    function _finalizeCheckpoint(bytes32 campaign, uint256 checkpointIndex) internal {
        vm.prank(checkpointCouncil);
        campaignRegistry.finalizeCheckpoint(campaign, checkpointIndex);
    }
}
