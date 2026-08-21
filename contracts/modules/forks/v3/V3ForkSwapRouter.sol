// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {ActionConstants} from '@uniswap/v4-periphery/src/libraries/ActionConstants.sol';
import {ERC20} from 'solmate/src/tokens/ERC20.sol';
import {IUniswapV3Pool} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {Permit2Payments} from '../../Permit2Payments.sol';
import {SafeCast} from '@uniswap/v3-core/contracts/libraries/SafeCast.sol';
import {V3ForkCallback} from '../../../libraries/V3ForkCallback.sol';

/// @title Router for CLAMM forks
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
    /// @param amountOutMinimum The minimum desired amount of output tokens
    /// @param pool The pool to swap against
    /// @param tokenIn The token being sold
    /// @param tokenOut The token being bought
    /// @param payer The address that will be paying the input
    /// @dev Output is measured from balances, as fork deltas may not follow Uniswap's signs
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
        // empty `data` is deliberate: a re-entering token falls through to derivation and reverts decoding it
        IUniswapV3Pool(pool)
            .swap(
                recipient,
                zeroForOne,
                amountIn.toInt256(),
                zeroForOne ? FORK_MIN_SQRT_RATIO + 1 : FORK_MAX_SQRT_RATIO - 1,
                ''
            );
        V3ForkCallback.clear();

        // unguarded on purpose: a balance going backwards should revert, not report zero
        uint256 amountOut = ERC20(tokenOut).balanceOf(recipient) - balanceBefore;
        if (amountOut < amountOutMinimum) revert V3ForkTooLittleReceived(amountOutMinimum, amountOut);
    }

    /// @notice Pays a fork pool from the open callback window
    /// @param amount0Delta The amount of token0 owed to the pool, when positive
    /// @param amount1Delta The amount of token1 owed to the pool, when positive
    /// @return handled False when no fork swap is open, so the caller falls through
    /// @dev Cleared before paying, and `owed` is capped at the leg's amountIn
    function _payV3ForkPool(int256 amount0Delta, int256 amount1Delta) internal returns (bool handled) {
        (address pool, address payer, address tokenIn, uint256 authorised) = V3ForkCallback.get();
        if (pool == address(0)) return false;
        if (msg.sender != pool) revert V3ForkInvalidCaller();

        V3ForkCallback.clear();

        bool zeroIsInput = amount0Delta > 0;
        if (zeroIsInput == (amount1Delta > 0)) revert V3ForkWrongDirection();
        // casting to 'uint256' is safe because the check above leaves exactly one delta positive
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 owed = zeroIsInput ? uint256(amount0Delta) : uint256(amount1Delta);
        if (owed > authorised) revert V3ForkOverCharged(authorised, owed);

        payOrPermit2Transfer(tokenIn, payer, pool, owed);
        handled = true;
    }
}
