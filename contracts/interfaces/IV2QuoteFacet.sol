// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {State} from '../libraries/QuoterState.sol';

interface IV2QuoteFacet {
    /// @notice Quotes a Uniswap v2 type exact input swap
    /// @param state The simulated state of the Universal Router
    /// @param recipient The recipient of the output tokens
    /// @param amountIn The amount of input tokens, or CONTRACT_BALANCE
    /// @param path The packed path of the trade
    /// @param protocol The Uniswap V2 type protocol
    /// @return The simulated state after the swap
    function v2QuoteExactIn(
        State memory state,
        address recipient,
        uint256 amountIn,
        bytes calldata path,
        uint256 protocol
    ) external view returns (State memory);

    /// @notice Quotes a Uniswap v2 type exact output swap
    /// @param state The simulated state of the Universal Router
    /// @param recipient The recipient of the output tokens
    /// @param amountOut The amount of output tokens to receive
    /// @param path The packed path of the trade
    /// @param protocol The Uniswap V2 type protocol
    /// @return The simulated state after the swap
    function v2QuoteExactOut(
        State memory state,
        address recipient,
        uint256 amountOut,
        bytes calldata path,
        uint256 protocol
    ) external view returns (State memory);

    /// @notice Quotes an exact-input swap against a constant-product fork pair
    /// @param state The simulated state of the Universal Router
    /// @param recipient The recipient of the output tokens
    /// @param amountIn The input amount, or CONTRACT_BALANCE
    /// @param pair The pair to swap against
    /// @param tokenIn The token being sold
    /// @param tokenOut The token being bought
    /// @param feePips The pair's swap fee, in pips
    /// @return The simulated state after the swap
    function v2ForkQuoteExactIn(
        State memory state,
        address recipient,
        uint256 amountIn,
        address pair,
        address tokenIn,
        address tokenOut,
        uint256 feePips
    ) external view returns (State memory);
}
