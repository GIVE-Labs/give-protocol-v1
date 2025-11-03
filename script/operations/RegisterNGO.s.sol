// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseDeployment} from "../base/BaseDeployment.sol";
import {NGORegistry} from "../../src/donation/NGORegistry.sol";
import {console} from "forge-std/console.sol";

/**
 * @title RegisterNGO
 * @author GIVE Labs
 * @notice Standalone script to register an NGO
 * @dev Usage:
 *   1. Set NGO parameters in .env
 *   2. Run script to register NGO
 *
 * Example:
 *   forge script script/operations/RegisterNGO.s.sol:RegisterNGO \
 *     --rpc-url $BASE_SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast
 */
contract RegisterNGO is BaseDeployment {
    NGORegistry public ngoRegistry;

    // NGO parameters
    address public ngoAddress;
    string public metadataCid;
    bytes32 public kycHash;
    address public attestor;

    function setUp() public override {
        super.setUp();

        // Load contract
        ngoRegistry = NGORegistry(loadDeployment("NGORegistry"));

        // Load NGO parameters from env
        ngoAddress = requireEnvAddress("NGO_ADDRESS");
        metadataCid = requireEnv("NGO_METADATA_CID"); // IPFS CID
        kycHash = keccak256(bytes(requireEnv("NGO_KYC_ATTESTATION")));
        attestor = requireEnvAddress("NGO_ATTESTOR");

        console.log("NGO Address:", ngoAddress);
        console.log("Metadata CID:", metadataCid);
        console.log("Attestor:", attestor);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        startBroadcastWith(deployerPrivateKey);

        console.log("\nRegistering NGO...");

        // Register NGO
        ngoRegistry.addNGO(ngoAddress, metadataCid, kycHash, attestor);

        console.log("NGO registered successfully");

        // Save NGO info
        saveDeployment(string.concat("NGO_", metadataCid), ngoAddress);

        finalizeDeployment();

        stopBroadcastIf();

        console.log("\n========================================");
        console.log("NGO Successfully Registered");
        console.log("========================================");
        console.log("NGO Address:", ngoAddress);
        console.log("Metadata CID:", metadataCid);
        console.log("Attestor:", attestor);
    }
}
