// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {UniswapImmutables} from '../UniswapImmutables.sol';
import {BytesLib} from '../v3/BytesLib.sol';
import {V4RouterActions} from '../../../libraries/V4RouterActions.sol';
import {Permit2Payments} from '../../Permit2Payments.sol';
import {V4Router} from '@uniswap/v4-periphery/src/V4Router.sol';
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';

/// @title Router for Uniswap v4 Trades
abstract contract V4SwapRouter is V4Router, Permit2Payments {
    using BytesLib for bytes;

    constructor(address _poolManager) V4Router(IPoolManager(_poolManager)) {}

    function _pay(Currency token, address payer, uint256 amount) internal override {
        payOrPermit2Transfer(Currency.unwrap(token), payer, address(poolManager), amount);
    }

    /// @notice Executes a nested plan from inside the router's open v4 lock
    /// @param commands A set of concatenated commands, each 1 byte in length
    /// @param inputs An array of byte strings containing abi encoded inputs for each command
    /// @dev Implemented by Dispatcher through a self-call, which preserves msgSender()
    function _executeSubPlan(bytes calldata commands, bytes[] calldata inputs) internal virtual;

    /// @dev Actions owned by this router, the rest go to V4Router
    function _handleAction(uint256 action, bytes calldata params) internal virtual override {
        if (action == V4RouterActions.EXECUTE_SUB_PLAN_ACTION) {
            (bytes calldata commands, bytes[] calldata inputs) = params.decodeCommandsAndInputs();
            _executeSubPlan(commands, inputs);
            return;
        }

        super._handleAction(action, params);
    }
}
