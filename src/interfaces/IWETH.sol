// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IWETH
 * @author GIVE Labs
 * @notice Interface for Wrapped ETH (WETH) contract
 * @dev Minimal interface for wrapping and unwrapping native ETH to/from WETH.
 *      WETH is an ERC20-compliant token representing native ETH, allowing ETH
 *      to be used in protocols that require ERC20 tokens.
 */
interface IWETH {
    /**
     * @notice Wraps native ETH into WETH
     * @dev Mints WETH tokens equal to msg.value and credits them to msg.sender.
     *      Emits a Transfer event from address(0) to msg.sender.
     */
    function deposit() external payable;

    /**
     * @notice Unwraps WETH back to native ETH
     * @dev Burns the specified amount of WETH tokens from msg.sender and
     *      transfers equivalent native ETH back to msg.sender.
     *      Emits a Transfer event from msg.sender to address(0).
     * @param amount The amount of WETH to unwrap
     */
    function withdraw(uint256 amount) external;
}
