// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseDeployment} from "../base/BaseDeployment.sol";
import {StrategyRegistry} from "../../src/registry/StrategyRegistry.sol";
import {console} from "forge-std/console.sol";

/**
 * @title RegisterStrategy
 * @author GIVE Labs
 * @notice Standalone script to register a new yield strategy
 * @dev Usage:
 *   1. Deploy adapter contract first
 *   2. Set strategy parameters in .env
 *   3. Run script to register strategy
 *
 * Example:
 *   forge script script/operations/RegisterStrategy.s.sol:RegisterStrategy \
 *     --rpc-url $BASE_SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast
 */
contract RegisterStrategy is BaseDeployment {
    StrategyRegistry public strategyRegistry;

    // Strategy parameters
    string public strategyName;
    bytes32 public strategyId;
    address public adapterAddress;
    bytes32 public riskTier;
    uint256 public maxTvl;
    string public metadataHash;

    address public strategyAdmin;

    function setUp() public override {
        super.setUp();

        // Load contract
        strategyRegistry = StrategyRegistry(loadDeployment("StrategyRegistry"));

        // Load admin
        strategyAdmin = requireEnvAddress("STRATEGY_ADMIN_ADDRESS");

        // Load strategy parameters from env
        strategyName = requireEnv("STRATEGY_NAME");
        strategyId = keccak256(bytes(strategyName));
        adapterAddress = requireEnvAddress("STRATEGY_ADAPTER_ADDRESS");

        string memory riskTierStr = requireEnv("STRATEGY_RISK_TIER"); // "LOW", "MEDIUM", "HIGH"
        riskTier = keccak256(bytes(riskTierStr));

        maxTvl = requireEnvUint("STRATEGY_MAX_TVL");
        metadataHash = requireEnv("STRATEGY_METADATA_HASH"); // IPFS hash

        console.log("Strategy Name:", strategyName);
        console.log("Strategy ID:", vm.toString(strategyId));
        console.log("Adapter:", adapterAddress);
        console.log("Risk Tier:", riskTierStr);
        console.log("Max TVL:", maxTvl);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        startBroadcastWith(deployerPrivateKey);

        console.log("\nRegistering Strategy...");

        // Register strategy
        strategyRegistry.registerStrategy(
            StrategyRegistry.StrategyInput({
                id: strategyId,
                adapter: adapterAddress,
                riskTier: riskTier,
                maxTvl: maxTvl,
                metadataHash: keccak256(bytes(metadataHash))
            })
        );

        console.log("Strategy registered successfully");

        // Save strategy info
        saveDeploymentBytes32(string.concat("Strategy_", strategyName, "_Id"), strategyId);
        saveDeployment(string.concat("Strategy_", strategyName, "_Adapter"), adapterAddress);

        finalizeDeployment();

        stopBroadcastIf();

        console.log("\n========================================");
        console.log("Strategy Successfully Registered");
        console.log("========================================");
        console.log("Strategy ID:", vm.toString(strategyId));
        console.log("Adapter:", adapterAddress);
        console.log("Risk Tier:", vm.toString(riskTier));
        console.log("Max TVL:", maxTvl);
    }
}
