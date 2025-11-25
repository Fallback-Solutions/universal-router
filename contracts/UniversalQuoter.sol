// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {IUniversalQuoter} from './interfaces/IUniversalQuoter.sol';
import {MetaDexImmutables, MetaDexParameters} from './modules/meta-dex/MetaDexImmutables.sol';
import {PaymentsImmutables, PaymentsParameters} from './modules/PaymentsImmutables.sol';
import {QuoteDispatcher} from './base/QuoteDispatcher.sol';
import {QuoterStateLib, State, Token} from './libraries/QuoterState.sol';
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

    /// @notice Quotes encoded commands along with provided inputs.
    /// @param commands A set of concatenated commands, each 1 byte in length
    /// @param inputs An array of byte strings containing abi encoded inputs for each command
    /// @param msgSender The address of the msg.sender of the swap
    /// @param startBalance The initial balance of tokenStart
    /// @return amountOut The amount of tokenOut received
    /// @return gasEstimate The gas estimate for executing the commands
    function quote(bytes calldata commands, bytes[] calldata inputs, address msgSender, uint256 startBalance)
        public
        returns (uint256 amountOut, uint256 gasEstimate)
    {
        // Accounting of state.
        State memory state;
        state.tokenStart.balance = startBalance;
        state.msgSender = msgSender;

        // State gets updated when commands are quoted
        quote(state, commands, inputs);

        amountOut = state.tokenEnd.balance;
        gasEstimate = state.gasUsage;
    }

    /// @inheritdoc QuoteDispatcher
    function quote(State memory state, bytes calldata commands, bytes[] calldata inputs)
        public
        override
        returns (State memory)
    {
        // First tokenIn is by default tokenStart.
        state.tokenIn = state.tokenStart;

        uint256 numCommands = commands.length;
        if (inputs.length != numCommands) revert LengthMismatch();

        // loop through all given commands, execute them and pass along outputs as defined
        for (uint256 commandIndex = 0; commandIndex < numCommands; commandIndex++) {
            bytes1 command = commands[commandIndex];
            bytes calldata input = inputs[commandIndex];
            dispatch(state, command, input);
        }

        // Validate end state.
        state.validateEndState();

        return state;
    }
}
