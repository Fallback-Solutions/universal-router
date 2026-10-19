// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {ActionConstants} from '@uniswap/v4-periphery/src/libraries/ActionConstants.sol';
import {IUniswapV2Pair} from '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import {QuoterStateLib, State} from '../../../libraries/QuoterState.sol';
import {V2ForkLibrary} from './V2ForkLibrary.sol';

/// @title Quoter for constant-product v2 forks
abstract contract V2ForkSwapQuoter {
    using QuoterStateLib for State;

    /// @notice Quotes an exact-input swap against a constant-product fork pair
    /// @param state The simulated state of the Universal Router
    /// @param recipient The recipient of the output tokens
    /// @param amountIn The input amount, or CONTRACT_BALANCE
    /// @param pair The pair to swap against
    /// @param tokenIn The token being sold
    /// @param tokenOut The token being bought
    /// @param feePips The pair's swap fee, in pips
    function v2ForkQuoteExactInput(
        State memory state,
        address recipient,
        uint256 amountIn,
        address pair,
        address tokenIn,
        address tokenOut,
        uint256 feePips
    ) internal view {
        if (amountIn == ActionConstants.CONTRACT_BALANCE) {
            amountIn = state.debitTokenInBalance(tokenIn);
        } else {
            state.debitTokenIn(tokenIn, amountIn);
        }

        uint256 gasBefore = gasleft();
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(pair).getReserves();
        (uint256 reserveIn, uint256 reserveOut) = tokenIn < tokenOut ? (reserve0, reserve1) : (reserve1, reserve0);
        uint256 amountOut = V2ForkLibrary.amountOut(amountIn, reserveIn, reserveOut, feePips);
        state.addGas(gasBefore - gasleft());
        state.addGasERC20Transfer();

        state.creditRecipient(tokenOut, amountOut, recipient);
    }
}
