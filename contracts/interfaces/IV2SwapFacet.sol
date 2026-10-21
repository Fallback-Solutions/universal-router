// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

interface IV2SwapFacet {
    /// @notice Performs a Uniswap v2 type exact input swap
    /// @param recipient The recipient of the output tokens
    /// @param amountIn The amount of input tokens for the trade
    /// @param amountOutMinimum The minimum desired amount of output tokens
    /// @param path The packed path of the trade
    /// @param payer The address that will be paying the input
    /// @param protocol The Uniswap V2 type protocol
    function v2SwapExactIn(
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata path,
        address payer,
        uint256 protocol
    ) external payable;

    /// @notice Performs a Uniswap v2 type exact output swap
    /// @param recipient The recipient of the output tokens
    /// @param amountOut The amount of output tokens to receive for the trade
    /// @param amountInMaximum The maximum desired amount of input tokens
    /// @param path The packed path of the trade
    /// @param payer The address that will be paying the input
    /// @param protocol The Uniswap V2 type protocol
    function v2SwapExactOut(
        address recipient,
        uint256 amountOut,
        uint256 amountInMaximum,
        bytes calldata path,
        address payer,
        uint256 protocol
    ) external payable;

    /// @notice Performs an exact-input swap against a constant-product fork pair
    /// @param recipient The recipient of the output tokens
    /// @param amountIn The input amount, or CONTRACT_BALANCE to spend the whole balance
    /// @param amountOutMinimum The minimum desired amount of output tokens
    /// @param pair The pair to swap against
    /// @param tokenIn The token being sold
    /// @param tokenOut The token being bought
    /// @param feePips The pair's swap fee, in pips
    /// @param payer The address that will be paying the input
    function v2ForkSwapExactIn(
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address pair,
        address tokenIn,
        address tokenOut,
        uint256 feePips,
        address payer
    ) external payable;
}
