// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

interface IMetadexPool {
    function getAmountOutWithTotalFee(uint256 amountIn, address tokenIn) external view returns (uint256);
}
