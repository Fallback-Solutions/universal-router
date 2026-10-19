// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {ActionConstants} from '@uniswap/v4-periphery/src/libraries/ActionConstants.sol';
import {IUniswapV3Pool} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {QuoterRevert} from '@uniswap/v4-periphery/src/libraries/QuoterRevert.sol';
import {QuoterStateLib, State} from '../../../libraries/QuoterState.sol';
import {SafeCast} from '@uniswap/v3-core/contracts/libraries/SafeCast.sol';
import {V3ForkCallback} from '../../../libraries/V3ForkCallback.sol';

/// @title Quoter for CLAMM forks
abstract contract V3ForkSwapQuoter {
    using QuoterRevert for *;
    using QuoterStateLib for State;
    using SafeCast for uint256;

    error V3ForkInvalidCaller();
    error V3ForkOverCharged(uint256 authorised, uint256 requested);
    error V3ForkWrongDirection();

    uint160 internal constant FORK_MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant FORK_MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    /// @notice Quotes an exact-input swap against a CLAMM fork pool
    /// @param state The simulated state of the Universal Router
    /// @param recipient The recipient of the output tokens
    /// @param amountIn The input amount, or CONTRACT_BALANCE
    /// @param pool The pool to swap against
    /// @param tokenIn The token being sold
    /// @param tokenOut The token being bought
    function v3ForkQuoteExactInput(
        State memory state,
        address recipient,
        uint256 amountIn,
        address pool,
        address tokenIn,
        address tokenOut
    ) internal {
        if (amountIn == ActionConstants.CONTRACT_BALANCE) {
            amountIn = state.debitTokenInBalance(tokenIn);
        } else {
            state.debitTokenIn(tokenIn, amountIn);
        }

        bool zeroForOne = tokenIn < tokenOut;
        uint256 amountOut;

        V3ForkCallback.set(pool, address(this), tokenIn, amountIn);
        uint256 gasBefore = gasleft();
        try IUniswapV3Pool(pool)
            .swap(
                address(this),
                zeroForOne,
                amountIn.toInt256(),
                zeroForOne ? FORK_MIN_SQRT_RATIO + 1 : FORK_MAX_SQRT_RATIO - 1,
                ''
            ) {}
        catch (bytes memory reason) {
            state.addGas(gasBefore - gasleft());
            amountOut = reason.parseQuoteAmount();
        }
        V3ForkCallback.clear();

        state.creditRecipient(tokenOut, amountOut, recipient);
    }

    /// @notice Reverts with the amount a fork pool pays out, when a fork quote is open
    /// @param amount0Delta The amount of token0 owed to the pool, when positive
    /// @param amount1Delta The amount of token1 owed to the pool, when positive
    function _quoteV3ForkPool(int256 amount0Delta, int256 amount1Delta) internal view {
        (address pool,,, uint256 authorised) = V3ForkCallback.get();
        if (pool == address(0)) return;
        if (msg.sender != pool) revert V3ForkInvalidCaller();

        bool zeroIsInput = amount0Delta > 0;
        if (zeroIsInput == (amount1Delta > 0)) revert V3ForkWrongDirection();
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 owed = zeroIsInput ? uint256(amount0Delta) : uint256(amount1Delta);
        if (owed > authorised) revert V3ForkOverCharged(authorised, owed);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256(-(zeroIsInput ? amount1Delta : amount0Delta)).revertQuote();
    }
}
