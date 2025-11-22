// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {IUniversalQuoter} from './interfaces/IUniversalQuoter.sol';
import {MetaDexImmutables, MetaDexParameters} from './modules/meta-dex/MetaDexImmutables.sol';
import {PaymentsImmutables, PaymentsParameters} from './modules/PaymentsImmutables.sol';
import {QuoteDispatcher} from './base/QuoteDispatcher.sol';
import {QuoterStateLib, State} from './libraries/QuoterState.sol';
import {RouterParameters} from './types/RouterParameters.sol';
import {UniswapImmutables, UniswapParameters} from './modules/uniswap/UniswapImmutables.sol';
import {V4SwapQuoter} from './modules/uniswap/v4/V4SwapQuoter.sol';

contract UniversalQuoter is IUniversalQuoter, QuoteDispatcher {
    using QuoterStateLib for State;
    constructor(RouterParameters memory params)
        UniswapImmutables(UniswapParameters(
                params.v2Factory, params.v3Factory, params.pairInitCodeHash, params.poolInitCodeHash
            ))
        V4SwapQuoter(params.v4PoolManager)
        PaymentsImmutables(PaymentsParameters(params.permit2, params.weth9))
        MetaDexImmutables(MetaDexParameters(
                params.velodromeFactory,
                params.velodromeInitCodeHash,
                params.slipstreamV1Factory,
                params.slipstreamV1InitCodeHash,
                params.slipstreamV2Factory,
                params.slipstreamV2InitCodeHash
            ))
    {}

    /// @inheritdoc QuoteDispatcher
    function quote(bytes calldata commands, bytes[] calldata inputs, address msgSender_, uint256 tokenStartBalance)
        public
        override
        returns (uint256 tokenStartBalance_, uint256 amountOut, uint256 gasEstimate)
    {
        // Set msg.sender in transient storage if we are not in a sub-plan.
        if (!QuoterStateLib.isSubPlan()) _msgSender = msgSender_;

        // Accounting of state.
        State memory state;
        state.tokenStart.balance = tokenStartBalance;
        state.msgSender = msgSender();

        // First tokenIn is by default tokenStart.
        state.tokenIn = state.tokenStart;

        uint256 numCommands = commands.length;
        if (inputs.length != numCommands) revert LengthMismatch();

        // loop through all given commands, execute them and pass along outputs as defined
        for (uint256 commandIndex = 0; commandIndex < numCommands; commandIndex++) {
            bytes1 command = commands[commandIndex];
            bytes calldata input = inputs[commandIndex];
            gasEstimate += dispatch(command, input, state);
        }

        // Validate end state.
        state.validateEndState();

        // Return the amount of tokenOut.
        tokenStartBalance_ = state.tokenStart.balance;
        amountOut = state.tokenEnd.balance;
    }
}
