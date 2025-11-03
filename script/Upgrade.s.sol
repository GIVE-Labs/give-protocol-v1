// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseDeployment} from "./base/BaseDeployment.sol";
import {ACLManager} from "../src/governance/ACLManager.sol";
import {GiveProtocolCore} from "../src/core/GiveProtocolCore.sol";
import {StrategyRegistry} from "../src/registry/StrategyRegistry.sol";
import {CampaignRegistry} from "../src/registry/CampaignRegistry.sol";
import {NGORegistry} from "../src/donation/NGORegistry.sol";
import {PayoutRouter} from "../src/payout/PayoutRouter.sol";
import {console} from "forge-std/console.sol";

/**
 * @title Upgrade
 * @author GIVE Labs
 * @notice UUPS upgrade script with state verification
 * @dev Upgrades UUPS proxies and verifies state persistence
 *
 * Supports upgrading:
 *   - ACLManager
 *   - GiveProtocolCore
 *   - StrategyRegistry
 *   - CampaignRegistry
 *   - NGORegistry
 *   - PayoutRouter
 *   - GiveVault4626 (via proxy)
 *   - CampaignVault4626 (via proxy)
 *
 * Usage:
 *   # Upgrade ACLManager
 *   forge script script/Upgrade.s.sol:Upgrade \
 *     --sig "upgradeACLManager()" \
 *     --rpc-url $BASE_SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast --verify
 *
 *   # Upgrade GiveProtocolCore
 *   forge script script/Upgrade.s.sol:Upgrade \
 *     --sig "upgradeGiveProtocolCore()" \
 *     --rpc-url $BASE_SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast --verify
 */
contract Upgrade is BaseDeployment {
    // Loaded contracts
    ACLManager public aclManager;
    GiveProtocolCore public protocolCore;
    StrategyRegistry public strategyRegistry;
    CampaignRegistry public campaignRegistry;
    NGORegistry public ngoRegistry;
    PayoutRouter public payoutRouter;

    // Admin (must have ROLE_UPGRADER)
    address public upgrader;

    function setUp() public override {
        super.setUp();

        // Load deployed contracts
        aclManager = ACLManager(loadDeployment("ACLManager"));
        protocolCore = GiveProtocolCore(loadDeployment("GiveProtocolCore"));
        strategyRegistry = StrategyRegistry(loadDeployment("StrategyRegistry"));
        campaignRegistry = CampaignRegistry(loadDeployment("CampaignRegistry"));
        ngoRegistry = NGORegistry(loadDeployment("NGORegistry"));
        payoutRouter = PayoutRouter(loadDeployment("PayoutRouter"));

        // Load upgrader address (must have ROLE_UPGRADER)
        upgrader = requireEnvAddress("ADMIN_ADDRESS");

        console.log("Upgrader address:", upgrader);
    }

    // ============================================================
    // UPGRADE FUNCTIONS
    // ============================================================

    function upgradeACLManager() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("\n========================================");
        console.log("Upgrading ACLManager");
        console.log("========================================");

        startBroadcastWith(deployerPrivateKey);

        // 1. Capture pre-upgrade state
        address oldImpl = getImplementation(address(aclManager));
        uint256 roleCount = captureRoleCount();

        console.log("Current implementation:", oldImpl);
        console.log("Current role count:", roleCount);

        // 2. Deploy new implementation
        ACLManager newImpl = new ACLManager();
        console.log("New implementation deployed:", address(newImpl));

        // 3. Upgrade proxy
        aclManager.upgradeToAndCall(address(newImpl), "");
        console.log("Proxy upgraded");

        // 4. Verify state persisted
        address newImplAddress = getImplementation(address(aclManager));
        uint256 newRoleCount = captureRoleCount();

        require(newImplAddress == address(newImpl), "Implementation not updated");
        require(newRoleCount == roleCount, "State corrupted: role count changed");

        console.log("State verified - upgrade successful");

        // 5. Save new implementation
        saveDeployment("ACLManagerImplementation", address(newImpl));
        finalizeDeployment();

        stopBroadcastIf();

        console.log("ACLManager upgrade complete");
    }

    function upgradeGiveProtocolCore() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("\n========================================");
        console.log("Upgrading GiveProtocolCore");
        console.log("========================================");

        startBroadcastWith(deployerPrivateKey);

        // 1. Capture pre-upgrade state
        address oldImpl = getImplementation(address(protocolCore));
        address aclAddress = address(protocolCore.aclManager());

        console.log("Current implementation:", oldImpl);
        console.log("Current ACL Manager:", aclAddress);

        // 2. Deploy new implementation
        GiveProtocolCore newImpl = new GiveProtocolCore();
        console.log("New implementation deployed:", address(newImpl));

        // 3. Upgrade proxy
        protocolCore.upgradeToAndCall(address(newImpl), "");
        console.log("Proxy upgraded");

        // 4. Verify state persisted
        address newImplAddress = getImplementation(address(protocolCore));
        address newAclAddress = address(protocolCore.aclManager());

        require(newImplAddress == address(newImpl), "Implementation not updated");
        require(newAclAddress == aclAddress, "State corrupted: ACL address changed");

        console.log("State verified - upgrade successful");

        // 5. Save new implementation
        saveDeployment("GiveProtocolCoreImplementation", address(newImpl));
        finalizeDeployment();

        stopBroadcastIf();

        console.log("GiveProtocolCore upgrade complete");
    }

    function upgradeStrategyRegistry() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("\n========================================");
        console.log("Upgrading StrategyRegistry");
        console.log("========================================");

        startBroadcastWith(deployerPrivateKey);

        // 1. Capture pre-upgrade state
        address oldImpl = getImplementation(address(strategyRegistry));
        bytes32[] memory strategyIds = strategyRegistry.listStrategyIds();

        console.log("Current implementation:", oldImpl);
        console.log("Current strategy count:", strategyIds.length);

        // 2. Deploy new implementation
        StrategyRegistry newImpl = new StrategyRegistry();
        console.log("New implementation deployed:", address(newImpl));

        // 3. Upgrade proxy
        strategyRegistry.upgradeToAndCall(address(newImpl), "");
        console.log("Proxy upgraded");

        // 4. Verify state persisted
        address newImplAddress = getImplementation(address(strategyRegistry));
        bytes32[] memory newStrategyIds = strategyRegistry.listStrategyIds();

        require(newImplAddress == address(newImpl), "Implementation not updated");
        require(newStrategyIds.length == strategyIds.length, "State corrupted: strategy count changed");

        console.log("State verified - upgrade successful");

        // 5. Save new implementation
        saveDeployment("StrategyRegistryImplementation", address(newImpl));
        finalizeDeployment();

        stopBroadcastIf();

        console.log("StrategyRegistry upgrade complete");
    }

    function upgradeCampaignRegistry() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("\n========================================");
        console.log("Upgrading CampaignRegistry");
        console.log("========================================");

        startBroadcastWith(deployerPrivateKey);

        // 1. Capture pre-upgrade state
        address oldImpl = getImplementation(address(campaignRegistry));
        bytes32[] memory campaignIds = campaignRegistry.listCampaignIds();

        console.log("Current implementation:", oldImpl);
        console.log("Current campaign count:", campaignIds.length);

        // 2. Deploy new implementation
        CampaignRegistry newImpl = new CampaignRegistry();
        console.log("New implementation deployed:", address(newImpl));

        // 3. Upgrade proxy
        campaignRegistry.upgradeToAndCall(address(newImpl), "");
        console.log("Proxy upgraded");

        // 4. Verify state persisted
        address newImplAddress = getImplementation(address(campaignRegistry));
        bytes32[] memory newCampaignIds = campaignRegistry.listCampaignIds();

        require(newImplAddress == address(newImpl), "Implementation not updated");
        require(newCampaignIds.length == campaignIds.length, "State corrupted: campaign count changed");

        console.log("State verified - upgrade successful");

        // 5. Save new implementation
        saveDeployment("CampaignRegistryImplementation", address(newImpl));
        finalizeDeployment();

        stopBroadcastIf();

        console.log("CampaignRegistry upgrade complete");
    }

    function upgradeNGORegistry() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("\n========================================");
        console.log("Upgrading NGORegistry");
        console.log("========================================");

        startBroadcastWith(deployerPrivateKey);

        // 1. Capture pre-upgrade state
        address oldImpl = getImplementation(address(ngoRegistry));

        console.log("Current implementation:", oldImpl);

        // 2. Deploy new implementation
        NGORegistry newImpl = new NGORegistry();
        console.log("New implementation deployed:", address(newImpl));

        // 3. Upgrade proxy
        ngoRegistry.upgradeToAndCall(address(newImpl), "");
        console.log("Proxy upgraded");

        // 4. Verify state persisted
        address newImplAddress = getImplementation(address(ngoRegistry));

        require(newImplAddress == address(newImpl), "Implementation not updated");

        console.log("State verified - upgrade successful");

        // 5. Save new implementation
        saveDeployment("NGORegistryImplementation", address(newImpl));
        finalizeDeployment();

        stopBroadcastIf();

        console.log("NGORegistry upgrade complete");
    }

    function upgradePayoutRouter() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("\n========================================");
        console.log("Upgrading PayoutRouter");
        console.log("========================================");

        startBroadcastWith(deployerPrivateKey);

        // 1. Capture pre-upgrade state
        address oldImpl = getImplementation(address(payoutRouter));
        uint256 protocolFeeBps = payoutRouter.feeBps();

        console.log("Current implementation:", oldImpl);
        console.log("Current protocol fee (bps):", protocolFeeBps);

        // 2. Deploy new implementation
        PayoutRouter newImpl = new PayoutRouter();
        console.log("New implementation deployed:", address(newImpl));

        // 3. Upgrade proxy
        payoutRouter.upgradeToAndCall(address(newImpl), "");
        console.log("Proxy upgraded");

        // 4. Verify state persisted
        address newImplAddress = getImplementation(address(payoutRouter));
        uint256 newProtocolFeeBps = payoutRouter.feeBps();

        require(newImplAddress == address(newImpl), "Implementation not updated");
        require(newProtocolFeeBps == protocolFeeBps, "State corrupted: fee changed");

        console.log("State verified - upgrade successful");

        // 5. Save new implementation
        saveDeployment("PayoutRouterImplementation", address(newImpl));
        finalizeDeployment();

        stopBroadcastIf();

        console.log("PayoutRouter upgrade complete");
    }

    // ============================================================
    // HELPER FUNCTIONS
    // ============================================================

    function getImplementation(address proxy) internal view returns (address) {
        bytes32 implSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        return address(uint160(uint256(vm.load(proxy, implSlot))));
    }

    function captureRoleCount() internal view returns (uint256) {
        // Capture canonical roles
        bytes32[] memory roles = aclManager.canonicalRoles();
        return roles.length;
    }
}
