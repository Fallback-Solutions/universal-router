// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

interface IV2PairReserves {
    function getReserves() external view returns (uint256 reserve0, uint256 reserve1, uint256 blockTimestampLast);
}
