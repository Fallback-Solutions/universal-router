// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

/// @title V3ForkCallback
/// @notice The pool mid-swap and the amount it may collect, held transiently
library V3ForkCallback {
    // The slot holding the pool mid-swap, transiently. bytes32(uint256(keccak256('V3ForkCallback.pool')) - 1)
    bytes32 constant POOL_SLOT = 0x712607ba41259a31a78ec9b314ec0fa45c9b2ab661d656fe082114e93d145688;
    // The slot holding the payer, transiently. bytes32(uint256(keccak256('V3ForkCallback.payer')) - 1)
    bytes32 constant PAYER_SLOT = 0xc2e7d13e3dae818dba73798f17b859c143fc30861adebb7165d95530a3df52d5;
    // The slot holding the token owed, transiently. bytes32(uint256(keccak256('V3ForkCallback.tokenIn')) - 1)
    bytes32 constant TOKEN_IN_SLOT = 0xf2afdb844acc5df25a3729ad94ed512d58bf157e1edf9cc9f0c3e32ebc668899;
    // The slot holding the most the pool may collect, transiently. bytes32(uint256(keccak256('V3ForkCallback.amountIn')) - 1)
    bytes32 constant AMOUNT_IN_SLOT = 0x053d7eae89e2d7a9b8ff15fe4e7d36147155b8a538ff1d38721bd4d73c2ac8c8;

    function set(address pool, address payer, address tokenIn, uint256 amountIn) internal {
        assembly ('memory-safe') {
            tstore(POOL_SLOT, pool)
            tstore(PAYER_SLOT, payer)
            tstore(TOKEN_IN_SLOT, tokenIn)
            tstore(AMOUNT_IN_SLOT, amountIn)
        }
    }

    function get() internal view returns (address pool, address payer, address tokenIn, uint256 amountIn) {
        assembly ('memory-safe') {
            pool := tload(POOL_SLOT)
            payer := tload(PAYER_SLOT)
            tokenIn := tload(TOKEN_IN_SLOT)
            amountIn := tload(AMOUNT_IN_SLOT)
        }
    }

    function clear() internal {
        set(address(0), address(0), address(0), 0);
    }
}
