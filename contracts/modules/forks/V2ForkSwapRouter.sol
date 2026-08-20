// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {ActionConstants} from '@uniswap/v4-periphery/src/libraries/ActionConstants.sol';
import {ERC20} from 'solmate/src/tokens/ERC20.sol';
import {IUniswapV2Pair} from '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import {Permit2Payments} from '../Permit2Payments.sol';
import {V2ForkLibrary} from '../../libraries/V2ForkLibrary.sol';

/// @title Router for constant-product v2 forks
/// @notice The pair and the fee arrive per call, so a fork this router was never configured
/// for is still reachable and is priced correctly
abstract contract V2ForkSwapRouter is Permit2Payments {
    error V2ForkTooLittleReceived(uint256 amountOutMinimum, uint256 amountOut);

    /// @notice Performs an exact-input swap against a constant-product fork pair
    /// @param recipient The recipient of the output tokens
    /// @param amountIn The input amount, or CONTRACT_BALANCE to spend the whole balance
    /// @param amountOutMinimum The minimum acceptable output
    /// @param pair The pair to swap against
    /// @param tokenIn The token being sold
    /// @param tokenOut The token being bought
    /// @param feePips The pair's swap fee, in pips
    /// @param payer The address that will be paying the input
    /// @dev Reserves are read before the input is transferred, because the pair prices off
    /// its pre-transfer reserves
    /// @dev `pair` is not checked to actually hold `tokenIn` and `tokenOut`. A mistyped pair
    /// prices against unrelated reserves and then fails the pair's own K check, and the loss
    /// is bounded by the caller's own `amountIn`, so the `token0()` call is not worth its gas
    /// on the fire path
    function v2ForkSwapExactInput(
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address pair,
        address tokenIn,
        address tokenOut,
        uint256 feePips,
        address payer
    ) internal {
        if (amountIn == ActionConstants.CONTRACT_BALANCE) {
            amountIn = ERC20(tokenIn).balanceOf(address(this));
        }

        bool zeroForOne = tokenIn < tokenOut;
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(pair).getReserves();
        (uint256 reserveIn, uint256 reserveOut) = zeroForOne ? (reserve0, reserve1) : (reserve1, reserve0);

        uint256 amountOut = V2ForkLibrary.amountOut(amountIn, reserveIn, reserveOut, feePips);
        if (amountOut < amountOutMinimum) revert V2ForkTooLittleReceived(amountOutMinimum, amountOut);

        payOrPermit2Transfer(tokenIn, payer, pair, amountIn);
        IUniswapV2Pair(pair).swap(zeroForOne ? 0 : amountOut, zeroForOne ? amountOut : 0, recipient, new bytes(0));
    }
}
