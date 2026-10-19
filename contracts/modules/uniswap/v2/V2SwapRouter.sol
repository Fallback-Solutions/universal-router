// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {IUniswapV2Pair} from '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import {UniswapV2Library} from './UniswapV2Library.sol';
import {UniswapImmutables} from '../UniswapImmutables.sol';
import {Permit2Payments} from '../../Permit2Payments.sol';
import {Constants} from '../../../libraries/Constants.sol';
import {ERC20} from 'solmate/src/tokens/ERC20.sol';
import {MetaDexImmutables} from '../../meta-dex/MetaDexImmutables.sol';
import {Protocols} from '../../../libraries/Protocols.sol';
import {V2Path} from './V2Path.sol';

/// @title Router for Uniswap v2 Trades
abstract contract V2SwapRouter is UniswapImmutables, Permit2Payments, MetaDexImmutables {
    using V2Path for bytes;

    error V2TooLittleReceived();
    error V2TooMuchRequested();
    error V2InvalidPath();
    error V2InvalidProtocol(uint256 protocol);

    function _v2Swap(bytes memory path, address recipient, address pair, uint256 protocol) private {
        unchecked {
            uint256 pools = path.numPools();
            if (pools == 0) revert V2InvalidPath();

            uint256 finalPairIndex = pools - 1;
            for (uint256 i; i < pools; i++) {
                (address input,, address output) = path.decodePool(i);
                (uint256 reserveInput, uint256 reserveOutput) = UniswapV2Library.getReserves(pair, input, output);
                uint256 amountInput = ERC20(input).balanceOf(pair) - reserveInput;
                uint256 amountOutput =
                    UniswapV2Library.getAmountOut(protocol, pair, amountInput, reserveInput, reserveOutput, input);
                (uint256 amount0Out, uint256 amount1Out) =
                    input < output ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
                address nextPair = i < finalPairIndex ? pairFor(protocol, path, i + 1) : recipient;
                IUniswapV2Pair(pair).swap(amount0Out, amount1Out, nextPair, new bytes(0));
                pair = nextPair;
            }
        }
    }

    /// @notice Performs a Uniswap v2 type exact input swap
    /// @param recipient The recipient of the output tokens
    /// @param amountIn The amount of input tokens for the trade
    /// @param amountOutMinimum The minimum desired amount of output tokens
    /// @param path The packed path of the trade
    /// @param payer The address that will be paying the input
    /// @param protocol The Uniswap V2 type protocol
    function v2SwapExactInput(
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes memory path,
        address payer,
        uint256 protocol
    ) internal {
        uint256 pools = path.numPools();
        if (pools == 0) revert V2InvalidPath();

        address firstPair = pairFor(protocol, path, 0);
        if (
            amountIn != Constants.ALREADY_PAID // amountIn of 0 to signal that the pair already has the tokens
        ) {
            (address tokenIn,,) = path.decodePool(0);
            payOrPermit2Transfer(tokenIn, payer, firstPair, amountIn);
        }

        (,, address tokenOutAddress) = path.decodePool(pools - 1);
        ERC20 tokenOut = ERC20(tokenOutAddress);
        uint256 balanceBefore = tokenOut.balanceOf(recipient);

        _v2Swap(path, recipient, firstPair, protocol);

        uint256 amountOut = tokenOut.balanceOf(recipient) - balanceBefore;
        if (amountOut < amountOutMinimum) revert V2TooLittleReceived();
    }

    /// @notice Performs a Uniswap v2 type exact output swap
    /// @param recipient The recipient of the output tokens
    /// @param amountOut The amount of output tokens to receive for the trade
    /// @param amountInMaximum The maximum desired amount of input tokens
    /// @param path The packed path of the trade
    /// @param payer The address that will be paying the input
    /// @param protocol The Uniswap V2 type protocol
    function v2SwapExactOutput(
        address recipient,
        uint256 amountOut,
        uint256 amountInMaximum,
        bytes memory path,
        address payer,
        uint256 protocol
    ) internal {
        (address factory, bytes32 initCodeHash) = getFactoryAndInitCodeHash(protocol, false);
        (uint256 amountIn, address firstPair) =
            UniswapV2Library.getAmountInMultihop(protocol, factory, initCodeHash, amountOut, path);
        if (amountIn > amountInMaximum) revert V2TooMuchRequested();

        (address tokenIn,,) = path.decodePool(0);
        payOrPermit2Transfer(tokenIn, payer, firstPair, amountIn);
        _v2Swap(path, recipient, firstPair, protocol);
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
