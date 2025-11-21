// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {V3Path} from './V3Path.sol';
import {BytesLib} from './BytesLib.sol';
import {SafeCast} from '@uniswap/v3-core/contracts/libraries/SafeCast.sol';
import {IUniswapV3Pool} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {IUniswapV3SwapCallback} from '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';
import {ActionConstants} from '@uniswap/v4-periphery/src/libraries/ActionConstants.sol';
import {CalldataDecoder} from '@uniswap/v4-periphery/src/libraries/CalldataDecoder.sol';
import {UniswapImmutables} from '../UniswapImmutables.sol';
import {ERC20} from 'solmate/src/tokens/ERC20.sol';
import {MetaDexImmutables} from '../../meta-dex/MetaDexImmutables.sol';
import {Protocols} from '../../../libraries/Protocols.sol';
import {QuoterStateLib, State} from '../../../libraries/QuoterState.sol';

/// @title Router for Uniswap v3 Trades
abstract contract V3SwapQuoter is UniswapImmutables, IUniswapV3SwapCallback, MetaDexImmutables {
    using V3Path for bytes;
    using BytesLib for bytes;
    using CalldataDecoder for bytes;
    using SafeCast for uint256;
    using QuoterStateLib for State;

    /// @dev Transient storage variable used to check a safety condition in exact output swaps.
    uint256 private amountOutCached;

    error V3InvalidCaller();

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;

    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data)
        external
        view
        override
    {
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported
        (, uint256 protocol) = abi.decode(data, (bytes, uint256));
        bytes calldata path = data.toBytes(0);

        (address tokenIn, uint24 fee, address tokenOut) = path.decodeFirstPool();

        if (computePoolAddress(tokenIn, tokenOut, fee, protocol) != msg.sender) revert V3InvalidCaller();

        (bool isExactInput, uint256 amountToPay, uint256 amountReceived) = amount0Delta > 0
            ? (tokenIn < tokenOut, uint256(amount0Delta), uint256(-amount1Delta))
            : (tokenOut < tokenIn, uint256(amount1Delta), uint256(-amount0Delta));

        if (isExactInput) {
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, amountReceived)
                revert(ptr, 32)
            }
        } else {
            // if the cache has been populated, ensure that the full output amount has been received
            if (amountOutCached != 0) require(amountReceived == amountOutCached);
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, amountToPay)
                revert(ptr, 32)
            }
        }
    }

    /// @dev Parses a revert reason that should contain the numeric quote
    function parseRevertReason(bytes memory reason) private pure returns (uint256 amount) {
        if (reason.length != 32) {
            if (reason.length < 68) revert('Unexpected error');
            assembly {
                reason := add(reason, 0x04)
            }
            revert(abi.decode(reason, (string)));
        }
        amount = abi.decode(reason, (uint256));
    }

    function v3QuoteExactInput(
        State memory state,
        address recipient,
        uint256 amountIn,
        bytes calldata path,
        uint256 protocol
    ) internal returns (uint256 gasEstimate) {
        address tokenIn = path.decodeFirstToken();
        if (amountIn == ActionConstants.CONTRACT_BALANCE) {
            amountIn = state.debitTokenInBalance(tokenIn);
        } else {
            state.debitTokenIn(tokenIn, amountIn);
        }

        uint256 amountOut;
        while (true) {
            (uint256 amountOut_, uint256 gasEstimate_) =
                _quote(amountIn.toInt256(), path.getFirstPool(), true, protocol);

            // the outputs of prior swaps become the inputs to subsequent ones
            amountIn = amountOut_;
            gasEstimate += gasEstimate_;

            // decide whether to continue or terminate
            if (path.hasMultiplePools()) {
                path = path.skipToken();
            } else {
                amountOut = amountOut_;
                break;
            }
        }
        (,, address tokenOut) = path.decodeFirstPool();

        state.creditRecipient(tokenOut, amountOut, recipient);
    }

    function v3QuoteExactOutput(
        State memory state,
        address recipient,
        uint256 amountOut,
        bytes calldata path,
        uint256 protocol
    ) public returns (uint256 gasEstimate) {
        address tokenOut = path.decodeFirstToken();
        state.creditRecipient(tokenOut, amountOut, recipient);

        uint256 amountIn;
        while (true) {
            // Cache the output amount for comparison in the swap callback
            amountOutCached = amountOut;
            (uint256 amountIn_, uint256 gasEstimate_) =
                _quote(-amountOut.toInt256(), path.getFirstPool(), false, protocol);
            // clear cache
            delete amountOutCached;

            // the inputs of prior swaps become the outputs of subsequent ones
            amountOut = amountIn_;
            gasEstimate += gasEstimate_;

            // decide whether to continue or terminate
            if (path.hasMultiplePools()) {
                path = path.skipToken();
            } else {
                amountIn = amountIn_;
                break;
            }
        }

        (,, address tokenIn) = path.decodeFirstPool();
        state.debitTokenIn(tokenIn, amountIn);
    }

    /// @dev Performs a single quote for both exactIn and exactOut
    /// For exactIn, `amount` is `amountIn`. For exactOut, `amount` is `-amountOut`
    /// For exactIn, `amount_` is `amountOut`. For exactOut, `amount_` is `amountIn`
    function _quote(int256 amount, bytes calldata path, bool isExactIn, uint256 protocol)
        private
        returns (uint256 amount_, uint256 gasEstimate)
    {
        (address tokenIn, uint24 fee, address tokenOut) = path.decodeFirstPool();

        bool zeroForOne = isExactIn ? tokenIn < tokenOut : tokenOut < tokenIn;

        uint256 gasBefore = gasleft();
        try IUniswapV3Pool(computePoolAddress(tokenIn, tokenOut, fee, protocol))
            .swap(
                address(this), // address(0) might cause issues with some tokens
                zeroForOne,
                amount,
                (zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1),
                abi.encode(path, protocol)
            ) {}
        catch (bytes memory reason) {
            gasEstimate = gasBefore - gasleft();
            amount_ = parseRevertReason(reason);
        }
    }

    function computePoolAddress(address tokenA, address tokenB, uint24 fee, uint256 protocol)
        private
        view
        returns (address pool)
    {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);

        (address factory, bytes32 initCodeHash) = getFactoryAndInitCodeHash(protocol);

        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(hex'ff', factory, keccak256(abi.encode(tokenA, tokenB, fee)), initCodeHash)
                    )
                )
            )
        );
    }

    function getFactoryAndInitCodeHash(uint256 protocol) private view returns (address factory, bytes32 initCodeHash) {
        if (protocol == Protocols.UNISWAP_V3) return (UNISWAP_V3_FACTORY, UNISWAP_V3_POOL_INIT_CODE_HASH);
        else if (protocol == Protocols.SLIPSTREAM_V1) return (SLIPSTREAM_V1_FACTORY, SLIPSTREAM_V1_POOL_INIT_CODE_HASH);
        else return (SLIPSTREAM_V2_FACTORY, SLIPSTREAM_V2_POOL_INIT_CODE_HASH);
    }
}
