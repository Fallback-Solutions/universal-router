// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {IV2QuoteFacet} from '../interfaces/IV2QuoteFacet.sol';
import {MetaDexImmutables, MetaDexParameters} from '../modules/meta-dex/MetaDexImmutables.sol';
import {RouterParameters} from '../types/RouterParameters.sol';
import {State} from '../libraries/QuoterState.sol';
import {UniswapImmutables, UniswapParameters} from '../modules/uniswap/UniswapImmutables.sol';
import {V2ForkSwapQuoter} from '../modules/forks/v2/V2ForkSwapQuoter.sol';
import {V2SwapQuoter} from '../modules/uniswap/v2/V2SwapQuoter.sol';

/// @title V2-style quotes, delegatecalled by the UniversalQuoter
contract V2QuoteFacet is IV2QuoteFacet, V2SwapQuoter, V2ForkSwapQuoter {
    constructor(RouterParameters memory params)
        UniswapImmutables(UniswapParameters(
                params.v2Factory, params.v3Factory, params.pairInitCodeHash, params.poolInitCodeHash
            ))
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

    /// @inheritdoc IV2QuoteFacet
    function v2QuoteExactIn(
        State memory state,
        address recipient,
        uint256 amountIn,
        bytes calldata path,
        uint256 protocol
    ) external view returns (State memory) {
        v2QuoteExactInput(state, recipient, amountIn, path, protocol);
        return state;
    }

    /// @inheritdoc IV2QuoteFacet
    function v2QuoteExactOut(
        State memory state,
        address recipient,
        uint256 amountOut,
        bytes calldata path,
        uint256 protocol
    ) external view returns (State memory) {
        v2QuoteExactOutput(state, recipient, amountOut, path, protocol);
        return state;
    }

    /// @inheritdoc IV2QuoteFacet
    function v2ForkQuoteExactIn(
        State memory state,
        address recipient,
        uint256 amountIn,
        address pair,
        address tokenIn,
        address tokenOut,
        uint256 feePips
    ) external view returns (State memory) {
        v2ForkQuoteExactInput(state, recipient, amountIn, pair, tokenIn, tokenOut, feePips);
        return state;
    }
}
