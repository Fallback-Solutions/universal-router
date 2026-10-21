// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {IMetadexPool} from '../../../interfaces/external/IMetadexPool.sol';
import {IV2PairReserves} from '../../../interfaces/external/IV2PairReserves.sol';
import {IVelodromePool} from '../../../interfaces/external/IVelodromePool.sol';
import {IVelodromePoolFactory} from '../../../interfaces/external/IVelodromePoolFactory.sol';
import {Protocols} from '../../../libraries/Protocols.sol';
import {V2Path} from './V2Path.sol';

/// @title Uniswap v2 Helper Library
/// @notice Calculates the recipient address for a command
library UniswapV2Library {
    using V2Path for bytes;

    error InvalidReserves();
    error InvalidPath();
    error V2InvalidProtocol(uint256 protocol);
    error StableExactOutputUnsupported();

    /// @notice Calculates the v2 address for a pair without making any external calls
    /// @param protocol The Uniswap V2 type protocol
    /// @param factory The address of the v2 factory
    /// @param initCodeHash The hash of the pair initcode
    /// @param tokenA One of the tokens in the pair
    /// @param tokenB The other token in the pair
    /// @param stable Whether the pair is stable
    /// @return pair The resultant v2 pair address
    function pairFor(
        uint256 protocol,
        address factory,
        bytes32 initCodeHash,
        address tokenA,
        address tokenB,
        bool stable
    ) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        bytes32 salt = protocol == Protocols.VELODROME
            ? keccak256(abi.encodePacked(token0, token1, stable))
            : keccak256(abi.encodePacked(token0, token1));
        pair = address(uint160(uint256(keccak256(abi.encodePacked(hex'ff', factory, salt, initCodeHash)))));
    }

    /// @notice Fetches the reserves of a pair, ordered by trade direction
    /// @param pair The v2 pair
    /// @param tokenIn The token being sold
    /// @param tokenOut The token being bought
    /// @return reserveIn The reserves of the input token
    /// @return reserveOut The reserves of the output token
    function getReserves(address pair, address tokenIn, address tokenOut)
        internal
        view
        returns (uint256 reserveIn, uint256 reserveOut)
    {
        (uint256 reserve0, uint256 reserve1,) = IV2PairReserves(pair).getReserves();
        (reserveIn, reserveOut) = tokenIn < tokenOut ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /// @notice Given an input asset amount returns the maximum output amount of the other asset
    /// @param amountIn The token input amount
    /// @param reserveIn The reserves available of the input token
    /// @param reserveOut The reserves available of the output token
    /// @return amountOut The output amount of the output token
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        if (reserveIn == 0 || reserveOut == 0) revert InvalidReserves();
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /// @notice Given an input asset amount returns the maximum output amount of the other asset
    /// @param protocol The Uniswap V2 type protocol
    /// @param pair The v2 pair
    /// @param amountIn The token input amount
    /// @param reserveIn The reserves available of the input token
    /// @param reserveOut The reserves available of the output token
    /// @param tokenIn The token being sold
    /// @return amountOut The output amount of the output token
    function getAmountOut(
        uint256 protocol,
        address pair,
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        address tokenIn
    ) internal view returns (uint256 amountOut) {
        if (protocol == Protocols.UNISWAP_V2) {
            amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        } else if (protocol == Protocols.VELODROME) {
            amountOut = IVelodromePool(pair).getAmountOut(amountIn, tokenIn);
        } else if (protocol == Protocols.METADEX_V1) {
            amountOut = IMetadexPool(pair).getAmountOutWithTotalFee(amountIn, tokenIn);
        } else {
            revert V2InvalidProtocol(protocol);
        }
    }

    /// @notice Returns the input amount needed for a desired output amount in a single-hop trade
    /// @param amountOut The desired output amount
    /// @param reserveIn The reserves available of the input token
    /// @param reserveOut The reserves available of the output token
    /// @return amountIn The input amount of the input token
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        if (reserveIn == 0 || reserveOut == 0) revert InvalidReserves();
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    /// @notice Returns the input amount needed for a desired output amount in a single-hop trade
    /// @param protocol The Uniswap V2 type protocol
    /// @param factory The address of the v2 factory
    /// @param pair The v2 pair
    /// @param amountOut The desired output amount
    /// @param reserveIn The reserves available of the input token
    /// @param reserveOut The reserves available of the output token
    /// @param stable Whether the pair is stable
    /// @return amountIn The input amount of the input token
    function getAmountIn(
        uint256 protocol,
        address factory,
        address pair,
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut,
        bool stable
    ) internal view returns (uint256 amountIn) {
        if (protocol == Protocols.UNISWAP_V2) {
            amountIn = getAmountIn(amountOut, reserveIn, reserveOut);
        } else if (protocol == Protocols.VELODROME) {
            if (stable) revert StableExactOutputUnsupported();
            if (reserveIn == 0 || reserveOut == 0) revert InvalidReserves();
            uint256 fee = IVelodromePoolFactory(factory).getFee(pair, stable);
            amountIn = (amountOut * reserveIn) / (reserveOut - amountOut);
            // forge-lint: disable-next-item(divide-before-multiply)
            amountIn = amountIn * 10_000 / (10_000 - fee) + 1;
        } else {
            revert V2InvalidProtocol(protocol);
        }
    }

    /// @notice Returns the input amount needed for a desired output amount in a multi-hop trade
    /// @param protocol The Uniswap V2 type protocol
    /// @param factory The address of the v2 factory
    /// @param initCodeHash The hash of the pair initcode
    /// @param amountOut The desired output amount
    /// @param path The packed path of the multi-hop trade
    /// @return amount The input amount of the input token
    /// @return pair The first pair in the trade
    function getAmountInMultihop(
        uint256 protocol,
        address factory,
        bytes32 initCodeHash,
        uint256 amountOut,
        bytes memory path
    ) internal view returns (uint256 amount, address pair) {
        uint256 pools = path.numPools();
        if (pools == 0) revert InvalidPath();
        amount = amountOut;
        for (uint256 i = pools; i > 0; i--) {
            (address tokenIn, bool stable, address tokenOut) = path.decodePool(i - 1);
            pair = pairFor(protocol, factory, initCodeHash, tokenIn, tokenOut, stable);
            (uint256 reserveIn, uint256 reserveOut) = getReserves(pair, tokenIn, tokenOut);
            amount = getAmountIn(protocol, factory, pair, amount, reserveIn, reserveOut, stable);
        }
    }

    /// @notice Sorts two tokens to return token0 and token1
    /// @param tokenA The first token to sort
    /// @param tokenB The other token to sort
    /// @return token0 The smaller token by address value
    /// @return token1 The larger token by address value
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }
}
