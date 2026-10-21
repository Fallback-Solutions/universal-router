// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {IV2SwapFacet} from '../interfaces/IV2SwapFacet.sol';
import {MetaDexImmutables, MetaDexParameters} from '../modules/meta-dex/MetaDexImmutables.sol';
import {PaymentsImmutables, PaymentsParameters} from '../modules/PaymentsImmutables.sol';
import {RouterParameters} from '../types/RouterParameters.sol';
import {UniswapImmutables, UniswapParameters} from '../modules/uniswap/UniswapImmutables.sol';
import {V2ForkSwapRouter} from '../modules/forks/v2/V2ForkSwapRouter.sol';
import {V2SwapRouter} from '../modules/uniswap/v2/V2SwapRouter.sol';

/// @title V2-style swaps, delegatecalled by the UniversalRouter
contract V2SwapFacet is IV2SwapFacet, V2SwapRouter, V2ForkSwapRouter {
    constructor(RouterParameters memory params)
        UniswapImmutables(UniswapParameters(
                params.v2Factory, params.v3Factory, params.pairInitCodeHash, params.poolInitCodeHash
            ))
        PaymentsImmutables(PaymentsParameters(params.permit2, params.weth9))
        MetaDexImmutables(MetaDexParameters(
                params.velodromeFactory,
                params.velodromeInitCodeHash,
                params.slipstreamV1Factory,
                params.slipstreamV1InitCodeHash,
                params.slipstreamV2Factory,
                params.slipstreamV2InitCodeHash,
                params.slipstreamV3Factory,
                params.slipstreamV3InitCodeHash,
                params.metadexV1StableFactory,
                params.metadexV1StableInitCodeHash,
                params.metadexV1VolatileFactory,
                params.metadexV1VolatileInitCodeHash,
                params.metadexCLV1Factory,
                params.metadexCLV1InitCodeHash
            ))
    {}

    /// @inheritdoc IV2SwapFacet
    function v2SwapExactIn(
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata path,
        address payer,
        uint256 protocol
    ) external payable {
        v2SwapExactInput(recipient, amountIn, amountOutMinimum, path, payer, protocol);
    }

    /// @inheritdoc IV2SwapFacet
    function v2SwapExactOut(
        address recipient,
        uint256 amountOut,
        uint256 amountInMaximum,
        bytes calldata path,
        address payer,
        uint256 protocol
    ) external payable {
        v2SwapExactOutput(recipient, amountOut, amountInMaximum, path, payer, protocol);
    }

    /// @inheritdoc IV2SwapFacet
    function v2ForkSwapExactIn(
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address pair,
        address tokenIn,
        address tokenOut,
        uint256 feePips,
        address payer
    ) external payable {
        v2ForkSwapExactInput(recipient, amountIn, amountOutMinimum, pair, tokenIn, tokenOut, feePips, payer);
    }
}
