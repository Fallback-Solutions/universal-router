// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {Constants} from '../../../libraries/Constants.sol';

/// @title Functions for manipulating packed v2 path data
/// @notice A path is token (20) followed by stable (1) + token (20) per pool
library V2Path {
    /// @notice Packs a token array into a path of non-stable pools
    /// @param tokens The path as an array of token addresses
    /// @return path The packed path
    function fromTokens(address[] calldata tokens) internal pure returns (bytes memory path) {
        uint256 length = tokens.length;
        uint256 step = Constants.NEXT_V2_POOL_OFFSET;
        path = new bytes(Constants.ADDR_SIZE + (length - 1) * step);
        assembly ('memory-safe') {
            let ptr := add(path, 0x20)
            for { let i := 0 } lt(i, length) { i := add(i, 1) } {
                mstore(add(ptr, mul(i, step)), shl(96, calldataload(add(tokens.offset, shl(5, i)))))
            }
        }
    }

    /// @notice Returns the number of pools in a path, or 0 if it is malformed
    /// @param path The packed path
    /// @return The number of pools
    function numPools(bytes memory path) internal pure returns (uint256) {
        if (path.length < Constants.V2_POP_OFFSET) return 0;
        if ((path.length - Constants.ADDR_SIZE) % Constants.NEXT_V2_POOL_OFFSET != 0) return 0;
        return (path.length - Constants.ADDR_SIZE) / Constants.NEXT_V2_POOL_OFFSET;
    }

    /// @notice Decodes the pool at `index`
    /// @param path The packed path, validated by numPools
    /// @param index The index of the pool
    /// @return tokenIn The token sold into the pool
    /// @return stable Whether the pool is stable
    /// @return tokenOut The token bought from the pool
    function decodePool(bytes memory path, uint256 index)
        internal
        pure
        returns (address tokenIn, bool stable, address tokenOut)
    {
        uint256 offset = index * Constants.NEXT_V2_POOL_OFFSET;
        assembly ('memory-safe') {
            let ptr := add(add(path, 0x20), offset)
            tokenIn := shr(96, mload(ptr))
            stable := iszero(iszero(byte(20, mload(ptr))))
            tokenOut := and(mload(add(ptr, 9)), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }
}
