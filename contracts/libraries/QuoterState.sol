// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {ActionConstants} from '@uniswap/v4-periphery/src/libraries/ActionConstants.sol';

struct State {
    // The msg.sender of the swap.
    address msgSender;
    // The estimate of the gas usage of the swap.
    uint256 gasUsage;
    // The Initial tokenIn being sold.
    Token tokenStart;
    // The current tokenIn (can be the initial tokenIn or an intermediate tokenIn).
    Token tokenIn;
    // The current tokenOut (can be the final tokenOut, transferred to msg.sender, or an intermediate token).
    Token tokenOut;
    // The final tokenOut send back to msg.sender.
    Token tokenEnd;
    // The currency borrowed from the vault, and how much of it is still owed.
    Token flashLoan;
}

struct Token {
    address token;
    uint256 balance;
    // Whether `token` has been assigned. Needed because address(0) is the native currency,
    // so it cannot double as an "unset" sentinel.
    bool set;
}

library QuoterStateLib {
    using QuoterStateLib for State;

    error BalanceTooLow();
    error FlashLoanNotRepaid();
    error MultipleFlashLoans();
    error InvalidNextToken();
    error InvalidReceiver();
    error InvalidTokenEnd();
    error InvalidTokenIn();
    error InvalidTokenStart();
    error NotDuringSubPlan();
    error TokenEndNotTransferred();
    error TokenInNotConsumed();
    error TokenOutNotConsumed();

    function isSubPlan() internal view returns (bool) {
        return msg.sender == address(this);
    }

    function addGas(State memory state, uint256 gasEstimate) internal pure {
        state.gasUsage += gasEstimate;
    }

    function addGasERC20Transfer(State memory state) internal pure {
        // Gas estimate is the worst case erc20-transfer cost (cold sstore).
        state.addGas(20_000);
    }

    function validateTokenStart(State memory state, address token) internal pure {
        if (state.tokenStart.token != token) revert InvalidTokenStart();
    }

    function validateTokenIn(State memory state, address token) internal view {
        // If token equals tokenIn, do nothing.
        if (state.tokenIn.set && token == state.tokenIn.token) {
            return;
        }
        // If no tokenIn is set, set it to the given token.
        else if (!state.tokenIn.set) {
            state.tokenIn.token = token;
            state.tokenIn.set = true;
        }
        // If tokenIn equals tokenOut, we have to move one iteration up in the swap path.
        else if (state.tokenOut.set && token == state.tokenOut.token) {
            nextToken(state);
        }
        // Else, token is invalid.
        else {
            revert InvalidTokenIn();
        }
    }

    function getTokenInBalance(State memory state, address token) internal view returns (uint256 balance) {
        validateTokenIn(state, token);

        return state.tokenIn.balance;
    }

    function creditTokenIn(State memory state, address token, uint256 amount) internal view {
        validateTokenIn(state, token);

        amount = repay(state, token, amount);

        // Credit the amount to tokenIn balance.
        state.tokenIn.balance += amount;
    }

    function debitTokenIn(State memory state, address token, uint256 amount) internal view {
        validateTokenIn(state, token);

        // Debit the amount from the tokenIn balance.
        if (state.tokenIn.balance < amount) revert BalanceTooLow();
        state.tokenIn.balance -= amount;
    }

    /// @dev Only the v4 action handlers may borrow. The router's own balances are real ERC20
    /// balances, where a shortfall is a bug rather than the vault lending.
    function debitTokenInOrBorrow(State memory state, address token, uint256 amount) internal view {
        validateTokenIn(state, token);

        if (state.tokenIn.balance < amount) {
            uint256 shortfall = amount - state.tokenIn.balance;
            borrow(state, token, shortfall);
            state.tokenIn.balance += shortfall;
        }
        state.tokenIn.balance -= amount;
    }

    function debitTokenOutOrBorrow(State memory state, address token, uint256 amount) internal view {
        validateTokenOut(state, token);

        if (state.tokenOut.balance < amount) {
            uint256 shortfall = amount - state.tokenOut.balance;
            borrow(state, token, shortfall);
            state.tokenOut.balance += shortfall;
        }
        state.tokenOut.balance -= amount;
    }

    function flashLoanBalance(State memory state, address token) internal pure returns (uint256) {
        return state.flashLoan.set && state.flashLoan.token == token ? state.flashLoan.balance : 0;
    }

    function borrow(State memory state, address token, uint256 amount) private pure {
        if (!state.flashLoan.set) {
            state.flashLoan.token = token;
            state.flashLoan.set = true;
        } else if (state.flashLoan.token != token) {
            revert MultipleFlashLoans();
        }
        state.flashLoan.balance += amount;
    }

    /// @dev Applies an incoming amount to the outstanding loan and returns what is left over.
    /// Mirrors CurrencyDelta.applyDelta, which keeps one net delta per currency and absorbs a
    /// swap output against an outstanding negative with no settle involved, so netting on
    /// every matching credit is the faithful model of runtime rather than an approximation.
    function repay(State memory state, address token, uint256 amount) private pure returns (uint256) {
        if (!state.flashLoan.set || state.flashLoan.token != token || state.flashLoan.balance == 0) {
            return amount;
        }

        uint256 repaid = state.flashLoan.balance < amount ? state.flashLoan.balance : amount;
        state.flashLoan.balance -= repaid;
        // Release the slot so a later cycle may borrow a different currency.
        if (state.flashLoan.balance == 0) state.flashLoan.set = false;
        return amount - repaid;
    }

    function debitTokenInBalance(State memory state, address token) internal view returns (uint256 balance) {
        validateTokenIn(state, token);

        // Debit the the full tokenIn balance.
        balance = state.tokenIn.balance;
        state.tokenIn.balance = 0;
    }

    function validateTokenOut(State memory state, address token) internal view {
        // If token equals tokenOut, do nothing.
        if (state.tokenOut.set && token == state.tokenOut.token) return;

        // If no tokenOut is set, set it to the given token.
        if (!state.tokenOut.set) {
            state.tokenOut.token = token;
            state.tokenOut.set = true;
        }
        // Else we have to move one iteration up in the swap path and set tokenOut.
        else {
            nextToken(state);
            state.tokenOut.token = token;
            state.tokenOut.set = true;
        }
    }

    function getTokenOutBalance(State memory state, address token) internal view returns (uint256 balance) {
        validateTokenOut(state, token);

        return state.tokenOut.balance;
    }

    function creditTokenOut(State memory state, address token, uint256 amount) internal view {
        validateTokenOut(state, token);

        amount = repay(state, token, amount);

        // Credit the amount to tokenOut balance.
        state.tokenOut.balance += amount;
    }

    function debitTokenOut(State memory state, address token, uint256 amount) internal view {
        validateTokenOut(state, token);

        // Debit the amount from the tokenOut balance.
        if (state.tokenOut.balance < amount) revert BalanceTooLow();
        state.tokenOut.balance -= amount;
    }

    function debitTokenOutBalance(State memory state, address token) internal view returns (uint256 balance) {
        validateTokenOut(state, token);

        // Debit the the full tokenOut balance.
        balance = state.tokenOut.balance;
        state.tokenOut.balance = 0;
    }

    function validateTokenEnd(State memory state, address token) internal view {
        // If token equals tokenEnd, do nothing.
        if (state.tokenEnd.set && token == state.tokenEnd.token) return;

        // If equality does not hold, tokenEnd must not yet be set.
        if (state.tokenEnd.set) revert InvalidTokenEnd();

        // If no tokenEnd is set, it must be equal to tokenOut.
        validateTokenOut(state, token);
        state.tokenEnd.token = token;
        state.tokenEnd.set = true;
    }

    function creditTokenEnd(State memory state, address token, uint256 amount) internal view {
        validateTokenEnd(state, token);

        // Credit the amount to tokenEnd balance.
        state.tokenEnd.balance += amount;
    }

    function creditRecipient(State memory state, address token, uint256 amount, address recipient) internal view {
        if (recipient == address(this) || recipient == ActionConstants.ADDRESS_THIS) {
            creditTokenOut(state, token, amount);
        } else if (recipient == state.msgSender || recipient == ActionConstants.MSG_SENDER) {
            creditTokenEnd(state, token, amount);
        } else {
            revert InvalidReceiver();
        }
    }

    function sweep(State memory state, address token, address recipient) internal view {
        if (!(recipient == state.msgSender || recipient == ActionConstants.MSG_SENDER)) revert InvalidReceiver();

        uint256 amount = debitTokenOutBalance(state, token);
        creditTokenEnd(state, token, amount);
    }

    /// @dev To move to a next asset, tokenOut cannot be tokenEnd.
    /// And either tokenIn has to be fully consumed,
    /// or in the case of a Sub Plan, if tokenIn is not fully consumed, it must be tokenStart.
    function nextToken(State memory state) internal view {
        // tokenOut cannot be tokenEnd
        if (state.tokenOut.set && state.tokenEnd.set && state.tokenOut.token == state.tokenEnd.token) {
            revert InvalidNextToken();
        }

        // TokenIn must be consumed,
        // or in the case of a Sub Plan, tokenIn must be the first asset of the Sub Plan.
        if (
            state.tokenIn.balance > 0
                && !(isSubPlan() && state.tokenStart.set && state.tokenIn.token == state.tokenStart.token)
        ) {
            revert TokenInNotConsumed();
        }

        // We move one iteration up in the swap path.
        // TokenOut of this iteration becomes tokenIn of the next iteration.
        state.tokenIn = state.tokenOut;
        delete state.tokenOut;
    }

    function validateEndState(State memory state) internal view {
        // TokenOut must be consumed.
        if (state.tokenOut.balance > 0) revert TokenOutNotConsumed();

        // TokenIn must be consumed,
        // or in the case of a Sub Plan, tokenIn must be the first asset of the Sub Plan.
        if (
            state.tokenIn.balance > 0
                && !(isSubPlan() && state.tokenStart.set && state.tokenIn.token == state.tokenStart.token)
        ) {
            revert TokenInNotConsumed();
        }

        // The vault must be made whole.
        if (state.flashLoan.balance > 0) revert FlashLoanNotRepaid();

        // TokenEnd must be transferred to msg.sender.
        if (state.tokenEnd.balance == 0) revert TokenEndNotTransferred();
    }

    /// @dev A v4 action block, like a mid-lock sub-plan, need not end in a tokenEnd: a block
    /// whose only exit is TAKE(ADDRESS_THIS) leaves the funds on the router.
    function validateSegmentState(State memory state) internal view {
        if (
            state.tokenIn.balance > 0
                && !(isSubPlan() && state.tokenStart.set && state.tokenIn.token == state.tokenStart.token)
        ) {
            revert TokenInNotConsumed();
        }
        if (state.flashLoan.balance > 0) revert FlashLoanNotRepaid();
    }

    function update(State memory state, State memory newState) internal view {
        // newState must be the result from a finished sub plan.
        validateEndState(newState);

        // Update balance TokenStart.
        state.validateTokenStart(newState.tokenStart.token);
        state.tokenStart.balance = newState.tokenStart.balance;

        // Balance for TokenIn is either zero, or tokenIn is the same as tokenStart.
        // Balance for TokenOut is zero.

        // Update balance TokenEnd.
        state.validateTokenEnd(newState.tokenEnd.token);
        state.tokenEnd.balance = newState.tokenEnd.balance;

        // Update gas usage.
        state.gasUsage = newState.gasUsage;
    }
}
