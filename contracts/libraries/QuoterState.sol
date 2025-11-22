// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

struct State {
    // Initial start tokenIn being sold.
    Token tokenStart;
    // The current tokenIn (can be the start tokenIn or an intermediate token).
    Token tokenIn;
    // The current tokenOut (can be the end tokenOut, transferred to msg.sender, or an intermediate token).
    Token tokenOut;
    // The final tokenOut send back to msg.sender.
    Token tokenEnd;
    // The msg.sender of the swap.
    address msgSender;
}

struct Token {
    address token;
    uint256 balance;
}

library QuoterStateLib {
    error BalanceTooLow();
    error InvalidNextToken();
    error InvalidReceiver();
    error InvalidTokenEnd();
    error InvalidTokenIn();
    error NotDuringSubPlan();
    error TokenEndNotTransferred();
    error TokenInNotConsumed();
    error TokenOutNotConsumed();

    function isSubPlan() internal view returns (bool) {
        return msg.sender == address(this);
    }

    function validateTokenIn(State memory state, address token) internal view {
        // If token equals tokenIn, do nothing.
        if (token == state.tokenIn.token) return;
        // If no tokenIn is set, set it to the given token.
        else if (state.tokenIn.token == address(0)) state.tokenIn.token = token;
        // If tokenIn equals tokenOut, we have to move one iteration up in the swap path.
        else if (token == state.tokenOut.token) nextToken(state);
        // Else, token is invalid.
        else revert InvalidTokenIn();
    }

    function getTokenInBalance(State memory state, address token) internal view returns (uint256 balance) {
        validateTokenIn(state, token);

        return state.tokenIn.balance;
    }

    function creditTokenIn(State memory state, address token, uint256 amount) internal view {
        validateTokenIn(state, token);

        // Credit the amount to tokenIn balance.
        state.tokenIn.balance += amount;
    }

    function debitTokenIn(State memory state, address token, uint256 amount) internal view {
        validateTokenIn(state, token);

        // Debit the amount from the tokenIn balance.
        if (state.tokenIn.balance < amount) revert BalanceTooLow();
        state.tokenIn.balance -= amount;
    }

    function debitTokenInBalance(State memory state, address token) internal view returns (uint256 balance) {
        // Using the full balance is not allowed in sub plans.
        if (isSubPlan()) revert NotDuringSubPlan();

        validateTokenIn(state, token);

        // Debit the the full tokenIn balance.
        balance = state.tokenIn.balance;
        state.tokenIn.balance = 0;
    }

    function validateTokenOut(State memory state, address token) internal view {
        // If token equals tokenOut, do nothing.
        if (token == state.tokenOut.token) return;

        // If no tokenOut is set, set it to the given token.
        if (state.tokenOut.token == address(0)) {
            state.tokenOut.token = token;
        }
        // Else we have to move one iteration up in the swap path and set tokenOut.
        else {
            nextToken(state);
            state.tokenOut.token = token;
        }
    }

    function getTokenOutBalance(State memory state, address token) internal view returns (uint256 balance) {
        validateTokenOut(state, token);

        return state.tokenOut.balance;
    }

    function creditTokenOut(State memory state, address token, uint256 amount) internal view {
        validateTokenOut(state, token);

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
        if (token == state.tokenEnd.token) return;

        // If equality does not hold, tokenEnd must not yet be set.
        if (state.tokenEnd.token != address(0)) revert InvalidTokenEnd();

        // If no tokenEnd is set, it must be equal to tokenOut.
        validateTokenOut(state, token);
        state.tokenEnd.token = token;
    }

    function creditTokenEnd(State memory state, address token, uint256 amount) internal view {
        validateTokenEnd(state, token);

        // Credit the amount to tokenEnd balance.
        state.tokenEnd.balance += amount;
    }

    function creditRecipient(State memory state, address token, uint256 amount, address recipient) internal view {
        if (recipient == address(this)) creditTokenOut(state, token, amount);
        else if (recipient == state.msgSender) creditTokenEnd(state, token, amount);
        else revert InvalidReceiver();
    }

    function sweep(State memory state, address token, address recipient) internal view {
        if (recipient != state.msgSender) revert InvalidReceiver();

        uint256 amount = debitTokenOutBalance(state, token);
        creditTokenEnd(state, token, amount);
    }

    /// @dev To move to a next asset, tokenOut cannot be tokenEnd.
    /// And either tokenIn has to be fully consumed,
    /// or in the case of a Sub Plan, if tokenIn is not fully consumed, it must be tokenStart.
    function nextToken(State memory state) internal view {
        // tokenOut cannot be tokenEnd
        if (state.tokenOut.token == state.tokenEnd.token) revert InvalidNextToken();

        // TokenIn must be consumed,
        // or in the case of a Sub Plan, tokenIn must be the first asset of the Sub Plan.
        if (state.tokenIn.balance > 0 && !(isSubPlan() && state.tokenIn.token == state.tokenStart.token)) {
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
        if (state.tokenIn.balance > 0 && !(isSubPlan() && state.tokenIn.token == state.tokenStart.token)) {
            revert TokenInNotConsumed();
        }

        // TokenEnd must be transferred to msg.sender.
        if (state.tokenEnd.balance == 0) revert TokenEndNotTransferred();
    }
}
