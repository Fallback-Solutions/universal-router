// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

/// @title V3ForkCallback
/// @notice The pool currently mid-swap and the amount it may collect, held transiently so
/// its pay callback can be authenticated without deriving the pool from a factory
library V3ForkCallback {
    // Slots are precomputed literals, not keccak expressions: inline assembly only accepts
    // direct number constants. Locker.sol uses the same form for the same reason.
    // bytes32(uint256(keccak256('V3ForkCallback.pool')) - 1)
    bytes32 constant POOL_SLOT = 0x712607ba41259a31a78ec9b314ec0fa45c9b2ab661d656fe082114e93d145688;
    // bytes32(uint256(keccak256('V3ForkCallback.payer')) - 1)
    bytes32 constant PAYER_SLOT = 0xc2e7d13e3dae818dba73798f17b859c143fc30861adebb7165d95530a3df52d5;
    // bytes32(uint256(keccak256('V3ForkCallback.tokenIn')) - 1)
    bytes32 constant TOKEN_IN_SLOT = 0xf2afdb844acc5df25a3729ad94ed512d58bf157e1edf9cc9f0c3e32ebc668899;
    // bytes32(uint256(keccak256('V3ForkCallback.amountIn')) - 1)
    bytes32 constant AMOUNT_IN_SLOT = 0x053d7eae89e2d7a9b8ff15fe4e7d36147155b8a538ff1d38721bd4d73c2ac8c8;

    /// @notice Opens the callback window for one swap
    /// @param pool The pool about to be called
    /// @param payer The address that will pay the input
    /// @param tokenIn The token the pool will be paid in
    /// @param amountIn The most the pool may collect
    function set(address pool, address payer, address tokenIn, uint256 amountIn) internal {
        assembly ('memory-safe') {
            tstore(POOL_SLOT, pool)
            tstore(PAYER_SLOT, payer)
            tstore(TOKEN_IN_SLOT, tokenIn)
            tstore(AMOUNT_IN_SLOT, amountIn)
        }
    }

    /// @notice Reads the open callback window
    /// @return pool The pool mid-swap, or the zero address when no swap is open
    /// @return payer The address paying the input
    /// @return tokenIn The token the pool is paid in
    /// @return amountIn The most the pool may collect
    function get() internal view returns (address pool, address payer, address tokenIn, uint256 amountIn) {
        assembly ('memory-safe') {
            pool := tload(POOL_SLOT)
            payer := tload(PAYER_SLOT)
            tokenIn := tload(TOKEN_IN_SLOT)
            amountIn := tload(AMOUNT_IN_SLOT)
        }
    }

    /// @notice Closes the callback window
    function clear() internal {
        set(address(0), address(0), address(0), 0);
    }
}
