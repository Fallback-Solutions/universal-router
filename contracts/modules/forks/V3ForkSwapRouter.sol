// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {ActionConstants} from '@uniswap/v4-periphery/src/libraries/ActionConstants.sol';
import {ERC20} from 'solmate/src/tokens/ERC20.sol';
import {IUniswapV3Pool} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {Permit2Payments} from '../Permit2Payments.sol';
import {SafeCast} from '@uniswap/v3-core/contracts/libraries/SafeCast.sol';
import {V3ForkCallback} from '../../libraries/V3ForkCallback.sol';

/// @title Router for CLAMM forks
/// @notice The pool arrives per call rather than derived from a configured factory, so an
/// unwired fork is still reachable
abstract contract V3ForkSwapRouter is Permit2Payments {
    using SafeCast for uint256;

    error V3ForkInvalidCaller();
    error V3ForkOverCharged(uint256 authorised, uint256 requested);
    error V3ForkTooLittleReceived(uint256 amountOutMinimum, uint256 amountOut);
    error V3ForkWrongDirection();

    uint160 internal constant FORK_MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant FORK_MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    /// @notice Performs an exact-input swap against a CLAMM fork pool
    /// @param recipient The recipient of the output tokens
    /// @param amountIn The input amount, or CONTRACT_BALANCE to spend the whole balance
    /// @param amountOutMinimum The minimum acceptable output
    /// @param pool The pool to swap against
    /// @param tokenIn The token being sold
    /// @param tokenOut The token being bought
    /// @param payer The address that will be paying the input
    /// @dev The output is measured from the recipient's balance, because a fork pool's
    /// returned deltas cannot be trusted to follow Uniswap's sign convention
    function v3ForkSwapExactInput(
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address pool,
        address tokenIn,
        address tokenOut,
        address payer
    ) internal {
        if (amountIn == ActionConstants.CONTRACT_BALANCE) {
            amountIn = ERC20(tokenIn).balanceOf(address(this));
        }

        bool zeroForOne = tokenIn < tokenOut;
        uint256 balanceBefore = ERC20(tokenOut).balanceOf(recipient);

        V3ForkCallback.set(pool, payer, tokenIn, amountIn);
        IUniswapV3Pool(pool)
            .swap(
                recipient,
                zeroForOne,
                amountIn.toInt256(),
                zeroForOne ? FORK_MIN_SQRT_RATIO + 1 : FORK_MAX_SQRT_RATIO - 1,
                ''
            );
        V3ForkCallback.clear();

        // Deliberately unguarded: a recipient whose balance went backwards is not a supported
        // state, so checked arithmetic reverting is the right outcome rather than reporting a
        // substituted zero.
        uint256 amountOut = ERC20(tokenOut).balanceOf(recipient) - balanceBefore;
        if (amountOut < amountOutMinimum) revert V3ForkTooLittleReceived(amountOutMinimum, amountOut);
    }

    /// @notice Pays a fork pool from the open callback window
    /// @param amount0Delta The amount of token0 owed to the pool, when positive
    /// @param amount1Delta The amount of token1 owed to the pool, when positive
    /// @return handled False when no fork swap is open, so the caller falls through to the
    /// derivation-based path used by the configured-protocol commands
    /// @dev The window is cleared before paying, so a pool that calls back twice inside one
    /// swap finds it closed on the second call. The amount is capped at what the leg
    /// authorised, because it arrives from the pool: uncapped, and with payerIsUser, it would
    /// be bounded only by the payer's Permit2 allowance rather than by amountIn.
    function _payV3ForkPool(int256 amount0Delta, int256 amount1Delta) internal returns (bool handled) {
        (address pool, address payer, address tokenIn, uint256 authorised) = V3ForkCallback.get();
        if (pool == address(0)) return false;
        if (msg.sender != pool) revert V3ForkInvalidCaller();

        V3ForkCallback.clear();

        bool zeroIsInput = amount0Delta > 0;
        if (zeroIsInput == (amount1Delta > 0)) revert V3ForkWrongDirection();
        uint256 owed = zeroIsInput ? uint256(amount0Delta) : uint256(amount1Delta);
        if (owed > authorised) revert V3ForkOverCharged(authorised, owed);

        payOrPermit2Transfer(tokenIn, payer, pool, owed);
        handled = true;
    }
}
