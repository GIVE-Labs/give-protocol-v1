// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title StorageKeys
 * @author GIVE Labs
 * @notice Standard key derivations for the generic registry buckets in StorageLib
 * @dev Provides consistent, collision-resistant key generation for dynamic storage lookups.
 *      All keys use keccak256 hashing with namespace prefixes to prevent collisions.
 *      These keys are used with StorageLib's generic registries (addressRegistry,
 *      uintRegistry, bytes32Registry, boolRegistry).
 */
library StorageKeys {
    /**
     * @notice Derives a storage key for vault-related data
     * @dev Uses "give.vault." prefix to namespace vault keys
     * @param vaultId The unique vault identifier
     * @return Storage key for vault data
     */
    function vaultKey(bytes32 vaultId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("give.vault.", vaultId));
    }

    /**
     * @notice Derives a storage key for adapter-related data
     * @dev Uses "give.adapter." prefix to namespace adapter keys
     * @param adapterId The unique adapter identifier
     * @return Storage key for adapter data
     */
    function adapterKey(bytes32 adapterId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("give.adapter.", adapterId));
    }

    /**
     * @notice Derives a storage key for role-related data
     * @dev Uses "give.role." prefix to namespace role keys
     * @param roleId The unique role identifier
     * @return Storage key for role data
     */
    function roleKey(bytes32 roleId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("give.role.", roleId));
    }

    /**
     * @notice Derives a storage key for synthetic asset data
     * @dev Uses "give.synthetic." prefix to namespace synthetic asset keys
     * @param assetId The unique synthetic asset identifier
     * @return Storage key for synthetic asset data
     */
    function syntheticKey(bytes32 assetId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("give.synthetic.", assetId));
    }

    /**
     * @notice Derives a storage key for risk configuration data
     * @dev Uses "give.risk." prefix to namespace risk keys
     * @param riskId The unique risk configuration identifier
     * @return Storage key for risk data
     */
    function riskKey(bytes32 riskId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("give.risk.", riskId));
    }

    /**
     * @notice Derives a storage key for bootstrap configuration
     * @dev Uses "give.bootstrap." prefix to namespace bootstrap keys.
     *      Used for storing deployment-time configuration values.
     * @param label Human-readable label for the bootstrap value (e.g., "aclManager", "core")
     * @return Storage key for bootstrap data
     */
    function bootstrapKey(string memory label) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("give.bootstrap.", label));
    }
}
