// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {ActionConstants} from '@uniswap/v4-periphery/src/libraries/ActionConstants.sol';
import {Actions} from '@uniswap/v4-periphery/src/libraries/Actions.sol';
import {BalanceDelta} from '@uniswap/v4-core/src/types/BalanceDelta.sol';
import {BaseV4Quoter} from '@uniswap/v4-periphery/src/base/BaseV4Quoter.sol';
import {BipsLibrary} from '@uniswap/v4-periphery/src/libraries/BipsLibrary.sol';
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {CalldataDecoder} from '@uniswap/v4-periphery/src/libraries/CalldataDecoder.sol';
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {IV4Quoter} from '@uniswap/v4-periphery/src/interfaces/IV4Quoter.sol';
import {IV4Router} from '@uniswap/v4-periphery/src/interfaces/IV4Router.sol';
import {PathKey} from '@uniswap/v4-periphery/src/libraries/PathKey.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import {QuoterRevert} from '@uniswap/v4-periphery/src/libraries/QuoterRevert.sol';
import {QuoterStateLib, State} from '../../../libraries/QuoterState.sol';
import {SafeCast} from '@uniswap/v4-core/src/libraries/SafeCast.sol';

/// @title Router for Uniswap v4 Trades
abstract contract V4SwapQuoter is BaseV4Quoter {
    using BipsLibrary for uint256;
    using CalldataDecoder for bytes;
    using QuoterRevert for *;
    using QuoterStateLib for State;
    using SafeCast for *;

    /// @notice emitted when different numbers of parameters and actions are provided
    error InputLengthMismatch();

    /// @notice emitted when an inheriting contract does not support an action
    error UnsupportedAction(uint256 action);

    constructor(address _poolManager) BaseV4Quoter(IPoolManager(_poolManager)) {}

    function _quoteActions(State memory routerState, bytes calldata data) internal returns (uint256 gasEstimate) {
        // abi.decode(data, (bytes, bytes[]));
        (bytes calldata actions, bytes[] calldata params) = data.decodeActionsRouterParams();

        State memory poolManagerState;
        poolManagerState.msgSender = routerState.msgSender;

        uint256 numActions = actions.length;
        if (numActions != params.length) revert InputLengthMismatch();

        for (uint256 actionIndex = 0; actionIndex < numActions; actionIndex++) {
            uint256 action = uint8(actions[actionIndex]);

            gasEstimate += _handleAction(routerState, poolManagerState, action, params[actionIndex]);
        }

        // Check that no balances remain on the poolManager at the end of the actions.
        poolManagerState.validateEndState();
    }

    /// @dev Corresponding quoter logic for V4Router.sol
    function _handleAction(
        State memory routerState,
        State memory poolManagerState,
        uint256 action,
        bytes calldata params
    ) internal returns (uint256 gasEstimate) {
        // swap actions and payment actions in different blocks for gas efficiency
        if (action < Actions.SETTLE) {
            if (action == Actions.SWAP_EXACT_IN) {
                IV4Router.ExactInputParams calldata swapParams = params.decodeSwapExactInParams();
                gasEstimate = v4QuoteExactInput(
                    poolManagerState,
                    IV4Quoter.QuoteExactParams({
                        exactCurrency: swapParams.currencyIn, path: swapParams.path, exactAmount: swapParams.amountIn
                    })
                );
                return gasEstimate;
            } else if (action == Actions.SWAP_EXACT_IN_SINGLE) {
                IV4Router.ExactInputSingleParams calldata swapParams = params.decodeSwapExactInSingleParams();
                gasEstimate = v4QuoteExactInputSingle(
                    poolManagerState,
                    IV4Quoter.QuoteExactSingleParams({
                        poolKey: swapParams.poolKey,
                        zeroForOne: swapParams.zeroForOne,
                        exactAmount: swapParams.amountIn,
                        hookData: swapParams.hookData
                    })
                );
                return gasEstimate;
            } else if (action == Actions.SWAP_EXACT_OUT) {
                IV4Router.ExactOutputParams calldata swapParams = params.decodeSwapExactOutParams();
                gasEstimate = v4QuoteExactOutput(
                    poolManagerState,
                    IV4Quoter.QuoteExactParams({
                        exactCurrency: swapParams.currencyOut, path: swapParams.path, exactAmount: swapParams.amountOut
                    })
                );
                return gasEstimate;
            } else if (action == Actions.SWAP_EXACT_OUT_SINGLE) {
                IV4Router.ExactOutputSingleParams calldata swapParams = params.decodeSwapExactOutSingleParams();
                gasEstimate = v4QuoteExactOutputSingle(
                    poolManagerState,
                    IV4Quoter.QuoteExactSingleParams({
                        poolKey: swapParams.poolKey,
                        zeroForOne: swapParams.zeroForOne,
                        exactAmount: swapParams.amountOut,
                        hookData: swapParams.hookData
                    })
                );
                return gasEstimate;
            }
        } else {
            if (action == Actions.SETTLE_ALL) {
                // We currently can't track debt of the poolManager in the quoter.
                revert UnsupportedAction(Actions.SETTLE_ALL);
            } else if (action == Actions.TAKE_ALL) {
                (Currency currency,) = params.decodeCurrencyAndUint256();
                uint256 amount = poolManagerState.debitTokenOutBalance(Currency.unwrap(currency));
                poolManagerState.creditTokenEnd(Currency.unwrap(currency), amount);
                routerState.creditTokenEnd(Currency.unwrap(currency), amount);
                // Gas estimate is the worst case erc20-transfer cost (cold sstore).
                gasEstimate = 20_000;
                return gasEstimate;
            } else if (action == Actions.SETTLE) {
                (Currency currency, uint256 amount, bool payerIsUser) = params.decodeCurrencyUint256AndBool();
                // We currently can't track debt of the poolManager in the quoter.
                if (amount == ActionConstants.OPEN_DELTA) revert UnsupportedAction(ActionConstants.OPEN_DELTA);
                // Payer is Router Contract, we have to debit the amount from the routerState.
                if (!payerIsUser) {
                    if (amount == ActionConstants.CONTRACT_BALANCE) {
                        amount = routerState.getTokenInBalance(Currency.unwrap(currency));
                        (Currency.unwrap(currency));
                    }
                    routerState.debitTokenIn(Currency.unwrap(currency), amount);
                }
                poolManagerState.creditTokenIn(Currency.unwrap(currency), amount);
                // Gas estimate is the worst case erc20-transfer cost (cold sstore).
                gasEstimate = 20_000;
                return gasEstimate;
            } else if (action == Actions.TAKE) {
                (Currency currency, address recipient, uint256 amount) = params.decodeCurrencyAddressAndUint256();
                if (amount == ActionConstants.OPEN_DELTA) {
                    amount = poolManagerState.getTokenOutBalance(Currency.unwrap(currency));
                }
                poolManagerState.debitTokenOut(Currency.unwrap(currency), amount);
                poolManagerState.creditTokenEnd(Currency.unwrap(currency), amount);
                routerState.creditRecipient(Currency.unwrap(currency), amount, _mapRecipient(recipient));
                // Gas estimate is the worst case erc20-transfer cost (cold sstore).
                return gasEstimate;
            } else if (action == Actions.TAKE_PORTION) {
                (Currency currency, address recipient, uint256 bips) = params.decodeCurrencyAddressAndUint256();
                uint256 balance = poolManagerState.getTokenOutBalance(Currency.unwrap(currency));
                uint256 amount = balance.calculatePortion(bips);
                poolManagerState.debitTokenOut(Currency.unwrap(currency), amount);
                poolManagerState.creditTokenEnd(Currency.unwrap(currency), amount);
                routerState.creditRecipient(Currency.unwrap(currency), amount, _mapRecipient(recipient));
                // Gas estimate is the worst case erc20-transfer cost (cold sstore).
                gasEstimate = 20_000;
                return gasEstimate;
            }
        }
        revert UnsupportedAction(action);
    }

    function v4QuoteExactInputSingle(State memory poolManagerState, IV4Quoter.QuoteExactSingleParams memory params)
        internal
        returns (uint256 gasEstimate)
    {
        // Debit tokenIn.
        (address tokenIn, address tokenOut) = params.zeroForOne
            ? (Currency.unwrap(params.poolKey.currency0), Currency.unwrap(params.poolKey.currency1))
            : (Currency.unwrap(params.poolKey.currency1), Currency.unwrap(params.poolKey.currency0));
        if (params.exactAmount == ActionConstants.OPEN_DELTA) {
            params.exactAmount = poolManagerState.getTokenInBalance(tokenIn).toUint128();
        }
        poolManagerState.debitTokenIn(tokenIn, params.exactAmount);

        // Do the swap.
        uint256 gasBefore = gasleft();
        try poolManager.unlock(abi.encodeCall(this._quoteExactInputSingle, (params))) {}
        catch (bytes memory reason) {
            gasEstimate = gasBefore - gasleft();
            // Extract the quote from QuoteSwap error, or throw if the quote failed
            uint256 amountOut = reason.parseQuoteAmount();

            // Credit tokenOut.
            poolManagerState.creditTokenOut(tokenOut, amountOut);
        }
    }

    function v4QuoteExactInput(State memory poolManagerState, IV4Quoter.QuoteExactParams memory params)
        internal
        returns (uint256 gasEstimate)
    {
        // Debit tokenIn.
        address tokenIn = Currency.unwrap(params.exactCurrency);
        if (params.exactAmount == ActionConstants.OPEN_DELTA) {
            params.exactAmount = poolManagerState.getTokenInBalance(tokenIn).toUint128();
        }
        poolManagerState.debitTokenIn(tokenIn, params.exactAmount);

        // Do the swap.
        uint256 gasBefore = gasleft();
        try poolManager.unlock(abi.encodeCall(this._quoteExactInput, (params))) {}
        catch (bytes memory reason) {
            gasEstimate = gasBefore - gasleft();
            // Extract the quote from QuoteSwap error, or throw if the quote failed
            uint256 amountOut = reason.parseQuoteAmount();

            // Credit tokenOut.
            address tokenOut = Currency.unwrap(params.path[params.path.length - 1].intermediateCurrency);
            poolManagerState.creditTokenOut(tokenOut, amountOut);
        }
    }

    function v4QuoteExactOutputSingle(State memory poolManagerState, IV4Quoter.QuoteExactSingleParams memory params)
        internal
        returns (uint256 gasEstimate)
    {
        // Credit tokenOut.
        (address tokenIn, address tokenOut) = params.zeroForOne
            ? (Currency.unwrap(params.poolKey.currency0), Currency.unwrap(params.poolKey.currency1))
            : (Currency.unwrap(params.poolKey.currency1), Currency.unwrap(params.poolKey.currency0));
        poolManagerState.creditTokenOut(tokenOut, params.exactAmount);

        // Do the swap.
        uint256 gasBefore = gasleft();
        try poolManager.unlock(abi.encodeCall(this._quoteExactOutputSingle, (params))) {}
        catch (bytes memory reason) {
            gasEstimate = gasBefore - gasleft();
            // Extract the quote from QuoteSwap error, or throw if the quote failed
            uint256 amountIn = reason.parseQuoteAmount();

            // Debit tokenIn.
            poolManagerState.debitTokenIn(tokenIn, amountIn);
        }
    }

    function v4QuoteExactOutput(State memory poolManagerState, IV4Quoter.QuoteExactParams memory params)
        internal
        returns (uint256 gasEstimate)
    {
        // Credit tokenOut.
        address tokenOut = Currency.unwrap(params.exactCurrency);
        poolManagerState.creditTokenOut(tokenOut, params.exactAmount);

        // Do the swap.
        uint256 gasBefore = gasleft();
        try poolManager.unlock(abi.encodeCall(this._quoteExactOutput, (params))) {}
        catch (bytes memory reason) {
            gasEstimate = gasBefore - gasleft();
            // Extract the quote from QuoteSwap error, or throw if the quote failed
            uint256 amountIn = reason.parseQuoteAmount();

            // Debit tokenIn.
            address tokenIn = Currency.unwrap(params.path[params.path.length - 1].intermediateCurrency);
            poolManagerState.debitTokenIn(tokenIn, amountIn);
        }
    }

    /// @dev external function called within the _unlockCallback, to simulate an exact input swap, then revert with the result
    function _quoteExactInput(IV4Quoter.QuoteExactParams calldata params) external selfOnly returns (bytes memory) {
        uint256 pathLength = params.path.length;
        BalanceDelta swapDelta;
        uint128 amountIn = params.exactAmount;
        Currency inputCurrency = params.exactCurrency;
        PathKey calldata pathKey;

        for (uint256 i = 0; i < pathLength; i++) {
            pathKey = params.path[i];
            (PoolKey memory poolKey, bool zeroForOne) = pathKey.getPoolAndSwapDirection(inputCurrency);

            swapDelta = _swap(poolKey, zeroForOne, -int256(int128(amountIn)), pathKey.hookData);

            amountIn = zeroForOne ? uint128(swapDelta.amount1()) : uint128(swapDelta.amount0());
            inputCurrency = pathKey.intermediateCurrency;
        }
        // amountIn after the loop actually holds the amountOut of the trade
        amountIn.revertQuote();
    }

    /// @dev external function called within the _unlockCallback, to simulate a single-hop exact input swap, then revert with the result
    function _quoteExactInputSingle(IV4Quoter.QuoteExactSingleParams calldata params)
        external
        selfOnly
        returns (bytes memory)
    {
        BalanceDelta swapDelta =
            _swap(params.poolKey, params.zeroForOne, -int256(int128(params.exactAmount)), params.hookData);

        // the output delta of a swap is positive
        uint256 amountOut = params.zeroForOne ? uint128(swapDelta.amount1()) : uint128(swapDelta.amount0());
        amountOut.revertQuote();
    }

    /// @dev external function called within the _unlockCallback, to simulate an exact output swap, then revert with the result
    function _quoteExactOutput(IV4Quoter.QuoteExactParams calldata params) external selfOnly returns (bytes memory) {
        uint256 pathLength = params.path.length;
        BalanceDelta swapDelta;
        uint128 amountOut = params.exactAmount;
        Currency outputCurrency = params.exactCurrency;
        PathKey calldata pathKey;

        for (uint256 i = pathLength; i > 0; i--) {
            pathKey = params.path[i - 1];
            (PoolKey memory poolKey, bool oneForZero) = pathKey.getPoolAndSwapDirection(outputCurrency);

            swapDelta = _swap(poolKey, !oneForZero, int256(uint256(amountOut)), pathKey.hookData);

            amountOut = oneForZero ? uint128(-swapDelta.amount1()) : uint128(-swapDelta.amount0());

            outputCurrency = pathKey.intermediateCurrency;
        }
        // amountOut after the loop exits actually holds the amountIn of the trade
        amountOut.revertQuote();
    }

    /// @dev external function called within the _unlockCallback, to simulate a single-hop exact output swap, then revert with the result
    function _quoteExactOutputSingle(IV4Quoter.QuoteExactSingleParams calldata params)
        external
        selfOnly
        returns (bytes memory)
    {
        BalanceDelta swapDelta =
            _swap(params.poolKey, params.zeroForOne, int256(uint256(params.exactAmount)), params.hookData);

        // the input delta of a swap is negative so we must flip it
        uint256 amountIn = params.zeroForOne ? uint128(-swapDelta.amount0()) : uint128(-swapDelta.amount1());
        amountIn.revertQuote();
    }

    /// @notice function that returns address considered executor of the actions
    /// @dev The other context functions, _msgData and _msgValue, are not supported by this contract
    /// In many contracts this will be the address that calls the initial entry point that calls `_executeActions`
    /// `msg.sender` shouldn't be used, as this will be the v4 pool manager contract that calls `unlockCallback`
    /// If using ReentrancyLock.sol, this function can return _getLocker()
    /// @dev Corresponding quoter logic for BaseActionsRouter.sol
    function msgSender() public view virtual returns (address);

    /// @notice Calculates the address for a action
    /// @dev Corresponding quoter logic for BaseActionsRouter.sol
    function _mapRecipient(address recipient) internal view returns (address) {
        if (recipient == ActionConstants.MSG_SENDER) {
            return msgSender();
        } else if (recipient == ActionConstants.ADDRESS_THIS) {
            return address(this);
        } else {
            return recipient;
        }
    }
}
