// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

/// @title Protocols
/// @notice Protocol Flags used to map contracts
library Protocols {
    // Command Types where value<=0x40
    uint256 constant UNISWAP_V2 = 0x00;
    uint256 constant UNISWAP_V3 = 0x01;
    uint256 constant UNISWAP_V4 = 0x02;
    uint256 constant V2_FORK = 0x03;
    uint256 constant V3_FORK = 0x04;
    // COMMAND_PLACEHOLDER = 0x05

    // Command Types where 0x40<=value<=0x5f
    // Reserved for 3rd party integrations
    uint256 constant VELODROME = 0x40;
    uint256 constant SLIPSTREAM_V1 = 0x41;
    uint256 constant SLIPSTREAM_V2 = 0x42;
    uint256 constant SLIPSTREAM_V3 = 0x43;
    uint256 constant METADEX_V1 = 0x44;
    uint256 constant METADEX_CL_V1 = 0x45;
    // COMMAND_PLACEHOLDER = 0x46
}
