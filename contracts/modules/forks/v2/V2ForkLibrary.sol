// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {FullMath} from '@uniswap/v4-core/src/libraries/FullMath.sol';

/// @title V2ForkLibrary
/// @notice Constant-product swap math with the fee supplied per call
library V2ForkLibrary {
    error EmptyReserves();
    error FeeTooHigh();
    error NoOutput();

    /// @notice Fee denominator, so a 0.3% pair is 3000 and a PancakeSwap v2 pair is 2500
    uint256 internal constant PIPS = 1_000_000;

    /// @notice Prices an exact-input leg against a constant-product pair
    /// @param amountIn The input amount, before the fee is applied
    /// @param reserveIn The pair's reserve of the input token
    /// @param reserveOut The pair's reserve of the output token
    /// @param feePips The pair's swap fee, in pips
    /// @return amountOut_ The output amount, rounded down
    /// @dev Rounds down, so a stale fee under-quotes and the pair's K check rejects it
    function amountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, uint256 feePips)
        internal
        pure
        returns (uint256 amountOut_)
    {
        if (reserveIn == 0 || reserveOut == 0) revert EmptyReserves();
        if (feePips >= PIPS) revert FeeTooHigh();

        uint256 amountInAfterFee = amountIn * (PIPS - feePips);
        // amountInAfterFee * reserveOut exceeds 256 bits well before the result does.
        amountOut_ = FullMath.mulDiv(amountInAfterFee, reserveOut, reserveIn * PIPS + amountInAfterFee);
        if (amountOut_ == 0) revert NoOutput();
    }
}
