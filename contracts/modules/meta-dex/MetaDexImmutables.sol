// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

struct MetaDexParameters {
    address velodromeFactory;
    bytes32 velodromeInitCodeHash;
    address slipstreamV1Factory;
    bytes32 slipstreamV1InitCodeHash;
    address slipstreamV2Factory;
    bytes32 slipstreamV2InitCodeHash;
}

contract MetaDexImmutables {
    /// @notice The address of Velodrome Factory
    address internal immutable VELODROME_FACTORY;

    /// @notice The Velodrome Pair initcodehash
    bytes32 internal immutable VELODROME_PAIR_INIT_CODE_HASH;

    /// @notice The address of slipstreamV1 Factory
    address internal immutable SLIPSTREAM_V1_FACTORY;

    /// @notice The slipstreamV1 Pool initcodehash
    bytes32 internal immutable SLIPSTREAM_V1_POOL_INIT_CODE_HASH;

    /// @notice The address of slipstreamV2 Factory
    address internal immutable SLIPSTREAM_V2_FACTORY;

    /// @notice The slipstreamV2 Pool initcodehash
    bytes32 internal immutable SLIPSTREAM_V2_POOL_INIT_CODE_HASH;

    constructor(MetaDexParameters memory params) {
        VELODROME_FACTORY = params.velodromeFactory;
        VELODROME_PAIR_INIT_CODE_HASH = params.velodromeInitCodeHash;
        SLIPSTREAM_V1_FACTORY = params.slipstreamV1Factory;
        SLIPSTREAM_V1_POOL_INIT_CODE_HASH = params.slipstreamV1InitCodeHash;
        SLIPSTREAM_V2_FACTORY = params.slipstreamV2Factory;
        SLIPSTREAM_V2_POOL_INIT_CODE_HASH = params.slipstreamV2InitCodeHash;
    }
}
