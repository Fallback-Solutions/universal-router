// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

struct MetaDexParameters {
    address velodromeFactory;
    bytes32 velodromeInitCodeHash;
    address slipstreamV1Factory;
    bytes32 slipstreamV1InitCodeHash;
    address slipstreamV2Factory;
    bytes32 slipstreamV2InitCodeHash;
    address slipstreamV3Factory;
    bytes32 slipstreamV3InitCodeHash;
    address metadexV1StableFactory;
    bytes32 metadexV1StableInitCodeHash;
    address metadexV1VolatileFactory;
    bytes32 metadexV1VolatileInitCodeHash;
    address metadexCLV1Factory;
    bytes32 metadexCLV1InitCodeHash;
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

    /// @notice The address of slipstreamV3 Factory
    address internal immutable SLIPSTREAM_V3_FACTORY;

    /// @notice The slipstreamV3 Pool initcodehash
    bytes32 internal immutable SLIPSTREAM_V3_POOL_INIT_CODE_HASH;

    /// @notice The address of the Metadex V1 stable Pool Factory
    address internal immutable METADEX_V1_STABLE_FACTORY;

    /// @notice The Metadex V1 stable Pool initcodehash
    bytes32 internal immutable METADEX_V1_STABLE_POOL_INIT_CODE_HASH;

    /// @notice The address of the Metadex V1 volatile Pool Factory
    address internal immutable METADEX_V1_VOLATILE_FACTORY;

    /// @notice The Metadex V1 volatile Pool initcodehash
    bytes32 internal immutable METADEX_V1_VOLATILE_POOL_INIT_CODE_HASH;

    /// @notice The address of the MetadexCL V1 Factory
    address internal immutable METADEX_CL_V1_FACTORY;

    /// @notice The MetadexCL V1 Pool initcodehash
    bytes32 internal immutable METADEX_CL_V1_POOL_INIT_CODE_HASH;

    constructor(MetaDexParameters memory params) {
        VELODROME_FACTORY = params.velodromeFactory;
        VELODROME_PAIR_INIT_CODE_HASH = params.velodromeInitCodeHash;
        SLIPSTREAM_V1_FACTORY = params.slipstreamV1Factory;
        SLIPSTREAM_V1_POOL_INIT_CODE_HASH = params.slipstreamV1InitCodeHash;
        SLIPSTREAM_V2_FACTORY = params.slipstreamV2Factory;
        SLIPSTREAM_V2_POOL_INIT_CODE_HASH = params.slipstreamV2InitCodeHash;
        SLIPSTREAM_V3_FACTORY = params.slipstreamV3Factory;
        SLIPSTREAM_V3_POOL_INIT_CODE_HASH = params.slipstreamV3InitCodeHash;
        METADEX_V1_STABLE_FACTORY = params.metadexV1StableFactory;
        METADEX_V1_STABLE_POOL_INIT_CODE_HASH = params.metadexV1StableInitCodeHash;
        METADEX_V1_VOLATILE_FACTORY = params.metadexV1VolatileFactory;
        METADEX_V1_VOLATILE_POOL_INIT_CODE_HASH = params.metadexV1VolatileInitCodeHash;
        METADEX_CL_V1_FACTORY = params.metadexCLV1Factory;
        METADEX_CL_V1_POOL_INIT_CODE_HASH = params.metadexCLV1InitCodeHash;
    }
}
