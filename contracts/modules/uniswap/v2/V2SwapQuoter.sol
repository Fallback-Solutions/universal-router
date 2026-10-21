// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {ActionConstants} from '@uniswap/v4-periphery/src/libraries/ActionConstants.sol';
import {MetaDexImmutables} from '../../meta-dex/MetaDexImmutables.sol';
import {Protocols} from '../../../libraries/Protocols.sol';
import {QuoterStateLib, State} from '../../../libraries/QuoterState.sol';
import {UniswapImmutables} from '../UniswapImmutables.sol';
import {UniswapV2Library} from './UniswapV2Library.sol';
import {V2Path} from './V2Path.sol';

/// @title Quoter for Uniswap v2 Trades
abstract contract V2SwapQuoter is UniswapImmutables, MetaDexImmutables {
    using QuoterStateLib for State;
    using V2Path for bytes;

    error V2InvalidPath();
    error V2NoOutput();
    error V2InvalidProtocol(uint256 protocol);

    /// @notice Quotes a Uniswap v2 type exact input swap
    /// @param state The simulated state of the Universal Router
    /// @param recipient The recipient of the output tokens
    /// @param amountIn The amount of input tokens, or CONTRACT_BALANCE
    /// @param path The packed path of the trade
    /// @param protocol The Uniswap V2 type protocol
    function v2QuoteExactInput(
        State memory state,
        address recipient,
        uint256 amountIn,
        bytes memory path,
        uint256 protocol
    ) internal view {
        uint256 pools = path.numPools();
        if (pools == 0) revert V2InvalidPath();

        (address tokenIn,,) = path.decodePool(0);
        if (amountIn == ActionConstants.CONTRACT_BALANCE) {
            amountIn = state.debitTokenInBalance(tokenIn);
        } else {
            state.debitTokenIn(tokenIn, amountIn);
        }

        for (uint256 i; i < pools; i++) {
            uint256 gasBefore = gasleft();
            (address input,, address output) = path.decodePool(i);
            address pair = pairFor(protocol, path, i);
            (uint256 reserveIn, uint256 reserveOut) = UniswapV2Library.getReserves(pair, input, output);
            amountIn = UniswapV2Library.getAmountOut(protocol, pair, amountIn, reserveIn, reserveOut, input);
            if (amountIn == 0) revert V2NoOutput();
            state.addGas(gasBefore - gasleft());
            state.addGasERC20Transfer();
        }

        (,, address tokenOut) = path.decodePool(pools - 1);
        state.creditRecipient(tokenOut, amountIn, recipient);
    }

    /// @notice Quotes a Uniswap v2 type exact output swap
    /// @param state The simulated state of the Universal Router
    /// @param recipient The recipient of the output tokens
    /// @param amountOut The amount of output tokens to receive
    /// @param path The packed path of the trade
    /// @param protocol The Uniswap V2 type protocol
    function v2QuoteExactOutput(
        State memory state,
        address recipient,
        uint256 amountOut,
        bytes memory path,
        uint256 protocol
    ) internal view {
        uint256 pools = path.numPools();
        if (pools == 0) revert V2InvalidPath();

        (,, address tokenOut) = path.decodePool(pools - 1);
        state.creditRecipient(tokenOut, amountOut, recipient);

        uint256 gasBefore = gasleft();
        (address factory, bytes32 initCodeHash) = getFactoryAndInitCodeHash(protocol, false);
        (uint256 amountIn,) = UniswapV2Library.getAmountInMultihop(protocol, factory, initCodeHash, amountOut, path);
        state.addGas(gasBefore - gasleft());
        for (uint256 i; i < pools; i++) {
            state.addGasERC20Transfer();
        }

        (address tokenIn,,) = path.decodePool(0);
        state.debitTokenIn(tokenIn, amountIn);
    }

    function pairFor(uint256 protocol, bytes memory path, uint256 index) private view returns (address) {
        (address tokenA, bool stable, address tokenB) = path.decodePool(index);
        (address factory, bytes32 initCodeHash) = getFactoryAndInitCodeHash(protocol, stable);
        return UniswapV2Library.pairFor(protocol, factory, initCodeHash, tokenA, tokenB, stable);
    }

    /// @dev Reverts on an unrecognised or unconfigured id instead of defaulting to one
    function getFactoryAndInitCodeHash(uint256 protocol, bool stable)
        private
        view
        returns (address factory, bytes32 initCodeHash)
    {
        if (protocol == Protocols.UNISWAP_V2) {
            (factory, initCodeHash) = (UNISWAP_V2_FACTORY, UNISWAP_V2_PAIR_INIT_CODE_HASH);
        } else if (protocol == Protocols.VELODROME) {
            (factory, initCodeHash) = (VELODROME_FACTORY, VELODROME_PAIR_INIT_CODE_HASH);
        } else if (protocol == Protocols.METADEX_V1) {
            (factory, initCodeHash) = stable
                ? (METADEX_V1_STABLE_FACTORY, METADEX_V1_STABLE_POOL_INIT_CODE_HASH)
                : (METADEX_V1_VOLATILE_FACTORY, METADEX_V1_VOLATILE_POOL_INIT_CODE_HASH);
        } else {
            revert V2InvalidProtocol(protocol);
        }

        if (factory == address(0)) revert V2InvalidProtocol(protocol);
    }
}
