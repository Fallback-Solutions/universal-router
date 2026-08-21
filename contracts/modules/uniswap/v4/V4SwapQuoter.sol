// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {ActionConstants} from '@uniswap/v4-periphery/src/libraries/ActionConstants.sol';
import {Actions} from '@uniswap/v4-periphery/src/libraries/Actions.sol';
import {BytesLib} from '../../uniswap/v3/BytesLib.sol';
import {V4RouterActions} from '../../../libraries/V4RouterActions.sol';
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
    using BytesLib for bytes;
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

    function _quoteActions(State memory routerState, bytes calldata data) internal {
        // abi.decode(data, (bytes, bytes[]));
        (bytes calldata actions, bytes[] calldata params) = data.decodeActionsRouterParams();

        State memory poolManagerState;
        poolManagerState.msgSender = routerState.msgSender;

        uint256 numActions = actions.length;
        if (numActions != params.length) revert InputLengthMismatch();

        for (uint256 actionIndex = 0; actionIndex < numActions; actionIndex++) {
            uint256 action = uint8(actions[actionIndex]);
            _handleAction(routerState, poolManagerState, action, params[actionIndex]);
        }

        // Check that no balances remain on the poolManager at the end of the actions.
        poolManagerState.validateVaultState();

        // Add gas usage during pool manager actions to the gas usage of the router.
        routerState.addGas(poolManagerState.gasUsage);
    }

    /// @notice Quotes a nested plan that continues the router's open state
    /// @param state The simulated router state to continue
    /// @param commands A set of concatenated commands, each 1 byte in length
    /// @param inputs An array of byte strings containing abi encoded inputs for each command
    /// @return state_ The simulated state after executing the commands
    /// @dev Implemented by QuoteDispatcher through a self-call, so isSubPlan() stays true
    function _quoteSubPlan(State memory state, bytes calldata commands, bytes[] calldata inputs)
        internal
        virtual
        returns (State memory state_);

    /// @dev Corresponding quoter logic for V4Router.sol
    function _handleAction(
        State memory routerState,
        State memory poolManagerState,
        uint256 action,
        bytes calldata params
    ) internal {
        if (action == V4RouterActions.EXECUTE_SUB_PLAN_ACTION) {
            (bytes calldata commands_, bytes[] calldata inputs_) = params.decodeCommandsAndInputs();
            routerState.updateSegment(_quoteSubPlan(routerState, commands_, inputs_));
            return;
        }

        // swap actions and payment actions in different blocks for gas efficiency
        if (action < Actions.SETTLE) {
            if (action == Actions.SWAP_EXACT_IN) {
                IV4Router.ExactInputParams calldata swapParams = params.decodeSwapExactInParams();
                v4QuoteExactInput(
                    poolManagerState,
                    IV4Quoter.QuoteExactParams({
                        exactCurrency: swapParams.currencyIn, path: swapParams.path, exactAmount: swapParams.amountIn
                    })
                );
                return;
            } else if (action == Actions.SWAP_EXACT_IN_SINGLE) {
                IV4Router.ExactInputSingleParams calldata swapParams = params.decodeSwapExactInSingleParams();
                v4QuoteExactInputSingle(
                    poolManagerState,
                    IV4Quoter.QuoteExactSingleParams({
                        poolKey: swapParams.poolKey,
                        zeroForOne: swapParams.zeroForOne,
                        exactAmount: swapParams.amountIn,
                        hookData: swapParams.hookData
                    })
                );
                return;
            } else if (action == Actions.SWAP_EXACT_OUT) {
                IV4Router.ExactOutputParams calldata swapParams = params.decodeSwapExactOutParams();
                v4QuoteExactOutput(
                    poolManagerState,
                    IV4Quoter.QuoteExactParams({
                        exactCurrency: swapParams.currencyOut, path: swapParams.path, exactAmount: swapParams.amountOut
                    })
                );
                return;
            } else if (action == Actions.SWAP_EXACT_OUT_SINGLE) {
                IV4Router.ExactOutputSingleParams calldata swapParams = params.decodeSwapExactOutSingleParams();
                v4QuoteExactOutputSingle(
                    poolManagerState,
                    IV4Quoter.QuoteExactSingleParams({
                        poolKey: swapParams.poolKey,
                        zeroForOne: swapParams.zeroForOne,
                        exactAmount: swapParams.amountOut,
                        hookData: swapParams.hookData
                    })
                );
                return;
            }
        } else {
            if (action == Actions.SETTLE_ALL) {
                (Currency currency, uint256 maxAmount) = params.decodeCurrencyAndUint256();
                uint256 amount = poolManagerState.flashLoanBalance(Currency.unwrap(currency));
                if (amount == 0 || amount > maxAmount) revert UnsupportedAction(Actions.SETTLE_ALL);
                routerState.debitTokenIn(Currency.unwrap(currency), amount);
                poolManagerState.creditTokenIn(Currency.unwrap(currency), amount);
                poolManagerState.addGasERC20Transfer();
                return;
            } else if (action == Actions.TAKE_ALL) {
                (Currency currency,) = params.decodeCurrencyAndUint256();
                uint256 amount = poolManagerState.debitTokenOutBalance(Currency.unwrap(currency));
                poolManagerState.creditTokenEnd(Currency.unwrap(currency), amount);
                poolManagerState.addGasERC20Transfer();

                routerState.creditTokenEnd(Currency.unwrap(currency), amount);
                return;
            } else if (action == Actions.SETTLE) {
                (Currency currency, uint256 amount, bool payerIsUser) = params.decodeCurrencyUint256AndBool();
                if (amount == ActionConstants.OPEN_DELTA) {
                    amount = poolManagerState.flashLoanBalance(Currency.unwrap(currency));
                    // OPEN_DELTA is itself zero, so an unrecorded loan would settle nothing.
                    if (amount == 0) revert UnsupportedAction(Actions.SETTLE);
                }
                // Payer is Router Contract, we have to debit the amount from the routerState.
                if (!payerIsUser) {
                    if (amount == ActionConstants.CONTRACT_BALANCE) {
                        amount = routerState.getTokenInBalance(Currency.unwrap(currency));
                        (Currency.unwrap(currency));
                    }
                    routerState.debitTokenIn(Currency.unwrap(currency), amount);
                }
                poolManagerState.creditTokenIn(Currency.unwrap(currency), amount);
                poolManagerState.addGasERC20Transfer();
                return;
            } else if (action == Actions.TAKE) {
                (Currency currency, address recipient, uint256 amount) = params.decodeCurrencyAddressAndUint256();
                if (amount == ActionConstants.OPEN_DELTA) {
                    amount = poolManagerState.getTokenOutBalance(Currency.unwrap(currency));
                }
                // Debit only: crediting back here would repay the borrow with its own credit.
                poolManagerState.debitTokenOutOrBorrow(Currency.unwrap(currency), amount);
                poolManagerState.addGasERC20Transfer();

                routerState.creditRecipient(Currency.unwrap(currency), amount, recipient);
                return;
            } else if (action == Actions.TAKE_PORTION) {
                (Currency currency, address recipient, uint256 bips) = params.decodeCurrencyAddressAndUint256();
                uint256 balance = poolManagerState.getTokenOutBalance(Currency.unwrap(currency));
                uint256 amount = balance.calculatePortion(bips);
                // Debit only: crediting back here would repay the borrow with its own credit.
                poolManagerState.debitTokenOutOrBorrow(Currency.unwrap(currency), amount);
                poolManagerState.addGasERC20Transfer();

                routerState.creditRecipient(Currency.unwrap(currency), amount, recipient);
                return;
            }
        }
        revert UnsupportedAction(action);
    }

    function v4QuoteExactInputSingle(State memory poolManagerState, IV4Quoter.QuoteExactSingleParams memory params)
        internal
    {
        // Debit tokenIn.
        (address tokenIn, address tokenOut) = params.zeroForOne
            ? (Currency.unwrap(params.poolKey.currency0), Currency.unwrap(params.poolKey.currency1))
            : (Currency.unwrap(params.poolKey.currency1), Currency.unwrap(params.poolKey.currency0));
        if (params.exactAmount == ActionConstants.OPEN_DELTA) {
            params.exactAmount = poolManagerState.getTokenInBalance(tokenIn).toUint128();
        }
        poolManagerState.debitTokenInOrBorrow(tokenIn, params.exactAmount);

        // Do the swap.
        uint256 gasBefore = gasleft();
        try poolManager.unlock(abi.encodeCall(this._quoteExactInputSingle, (params))) {}
        catch (bytes memory reason) {
            uint256 gasEstimate = gasBefore - gasleft();
            poolManagerState.addGas(gasEstimate);

            // Extract the quote from QuoteSwap error, or throw if the quote failed
            uint256 amountOut = reason.parseQuoteAmount();

            // Credit tokenOut.
            poolManagerState.creditTokenOut(tokenOut, amountOut);
        }
    }

    function v4QuoteExactInput(State memory poolManagerState, IV4Quoter.QuoteExactParams memory params) internal {
        // Debit tokenIn.
        address tokenIn = Currency.unwrap(params.exactCurrency);
        if (params.exactAmount == ActionConstants.OPEN_DELTA) {
            params.exactAmount = poolManagerState.getTokenInBalance(tokenIn).toUint128();
        }
        poolManagerState.debitTokenInOrBorrow(tokenIn, params.exactAmount);

        // Do the swap.
        uint256 gasBefore = gasleft();
        try poolManager.unlock(abi.encodeCall(this._quoteExactInput, (params))) {}
        catch (bytes memory reason) {
            uint256 gasEstimate = gasBefore - gasleft();
            poolManagerState.addGas(gasEstimate);

            // Extract the quote from QuoteSwap error, or throw if the quote failed
            uint256 amountOut = reason.parseQuoteAmount();

            // Credit tokenOut.
            address tokenOut = Currency.unwrap(params.path[params.path.length - 1].intermediateCurrency);
            poolManagerState.creditTokenOut(tokenOut, amountOut);
        }
    }

    function v4QuoteExactOutputSingle(State memory poolManagerState, IV4Quoter.QuoteExactSingleParams memory params)
        internal
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
            uint256 gasEstimate = gasBefore - gasleft();
            poolManagerState.addGas(gasEstimate);

            // Extract the quote from QuoteSwap error, or throw if the quote failed
            uint256 amountIn = reason.parseQuoteAmount();

            // Debit tokenIn.
            poolManagerState.debitTokenInOrBorrow(tokenIn, amountIn);
        }
    }

    function v4QuoteExactOutput(State memory poolManagerState, IV4Quoter.QuoteExactParams memory params) internal {
        // Credit tokenOut.
        address tokenOut = Currency.unwrap(params.exactCurrency);
        poolManagerState.creditTokenOut(tokenOut, params.exactAmount);

        // Do the swap.
        uint256 gasBefore = gasleft();
        try poolManager.unlock(abi.encodeCall(this._quoteExactOutput, (params))) {}
        catch (bytes memory reason) {
            uint256 gasEstimate = gasBefore - gasleft();
            poolManagerState.addGas(gasEstimate);

            // Extract the quote from QuoteSwap error, or throw if the quote failed
            uint256 amountIn = reason.parseQuoteAmount();

            // Debit tokenIn.
            address tokenIn = Currency.unwrap(params.path[params.path.length - 1].intermediateCurrency);
            poolManagerState.debitTokenInOrBorrow(tokenIn, amountIn);
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
}
