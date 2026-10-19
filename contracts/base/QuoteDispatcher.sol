// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {BytesLib} from '../modules/uniswap/v3/BytesLib.sol';
import {Commands} from '../libraries/Commands.sol';
import {Facet, FacetLib} from '../libraries/Facet.sol';
import {IV2QuoteFacet} from '../interfaces/IV2QuoteFacet.sol';
import {CalldataDecoder} from '@uniswap/v4-periphery/src/libraries/CalldataDecoder.sol';
import {PaymentsImmutables} from '../modules/PaymentsImmutables.sol';
import {Protocols} from '../libraries/Protocols.sol';
import {QuoterStateLib, State} from '../libraries/QuoterState.sol';
import {V2Path} from '../modules/uniswap/v2/V2Path.sol';
import {V3SwapQuoter} from '../modules/uniswap/v3/V3SwapQuoter.sol';
import {V4SwapQuoter} from '../modules/uniswap/v4/V4SwapQuoter.sol';

/// @title Decodes and Executes Commands
/// @notice Called by the UniversalQuoter contract to efficiently decode and execute a singular command
abstract contract QuoteDispatcher is PaymentsImmutables, V3SwapQuoter, V4SwapQuoter {
    using BytesLib for bytes;
    using CalldataDecoder for bytes;
    using FacetLib for Facet;
    using QuoterStateLib for State;

    error InvalidCommandType(uint256 commandType);

    /// @notice The facet quoting the v2-style swaps
    Facet internal immutable V2_QUOTE_FACET;

    /// @param v2QuoteFacet The deployed V2QuoteFacet
    constructor(address v2QuoteFacet) {
        V2_QUOTE_FACET = Facet.wrap(v2QuoteFacet);
    }

    /// @notice Quotes encoded commands along with provided inputs
    /// @param state The simulated state of the Universal Router before executing the commands
    /// @param commands A set of concatenated commands, each 1 byte in length
    /// @param inputs An array of byte strings containing abi encoded inputs for each command
    /// @return state_ The simulated state of the Universal Router after executing the commands
    function quote(State memory state, bytes calldata commands, bytes[] calldata inputs)
        external
        virtual
        returns (State memory);

    /// @notice Quotes a partial plan that continues an open state
    /// @param state The simulated state to continue
    /// @param commands A set of concatenated commands, each 1 byte in length
    /// @param inputs An array of byte strings containing abi encoded inputs for each command
    /// @return state_ The simulated state after executing the commands
    function quoteSubPlan(State memory state, bytes calldata commands, bytes[] calldata inputs)
        external
        virtual
        returns (State memory state_);

    /// @inheritdoc V4SwapQuoter
    function _quoteSubPlan(State memory state, bytes calldata commands, bytes[] calldata inputs)
        internal
        override
        returns (State memory state_)
    {
        return QuoteDispatcher(address(this)).quoteSubPlan(state, commands, inputs);
    }

    /// @notice Decodes and executes the given command with the given inputs
    /// @param state The simulated state of the Universal Router before executing the commands
    /// @param commandType The command type to execute
    /// @param inputs The inputs to execute the command with
    /// @dev 2 masks are used to enable use of a nested-if statement in execution for efficiency reasons
    function dispatch(State memory state, bytes1 commandType, bytes calldata inputs) internal {
        uint256 command = uint8(commandType & Commands.COMMAND_TYPE_MASK);

        // 0x00 <= command < 0x21
        if (command < Commands.EXECUTE_SUB_PLAN) {
            // 0x00 <= command < 0x10
            if (command < Commands.V4_SWAP) {
                // 0x00 <= command < 0x08
                if (command < Commands.V2_SWAP_EXACT_IN) {
                    if (command == Commands.V3_SWAP_EXACT_IN) {
                        v3QuoteExactInput(state, Protocols.UNISWAP_V3, inputs);
                    } else if (command == Commands.V3_SWAP_EXACT_OUT) {
                        v3QuoteExactOutput(state, Protocols.UNISWAP_V3, inputs);
                    } else if (command == Commands.PERMIT2_TRANSFER_FROM) {
                        revert InvalidCommandType(command);
                    } else if (command == Commands.PERMIT2_PERMIT_BATCH) {
                        revert InvalidCommandType(command);
                    } else if (command == Commands.SWEEP) {
                        // equivalent: abi.decode(inputs, (address, address, uint256))
                        address token;
                        address recipient;
                        uint160 amountMin;
                        assembly {
                            token := calldataload(inputs.offset)
                            recipient := calldataload(add(inputs.offset, 0x20))
                            amountMin := calldataload(add(inputs.offset, 0x40))
                        }
                        state.sweep(token, recipient, amountMin);
                        state.addGasERC20Transfer();
                    } else if (command == Commands.TRANSFER) {
                        revert InvalidCommandType(command);
                    } else if (command == Commands.PAY_PORTION) {
                        revert InvalidCommandType(command);
                    } else {
                        // placeholder area for command 0x07
                        revert InvalidCommandType(command);
                    }
                } else {
                    // 0x08 <= command < 0x10
                    if (command == Commands.V2_SWAP_EXACT_IN) {
                        // equivalent: abi.decode(inputs, (address, uint256, uint256, bytes, bool))
                        address recipient;
                        uint256 amountIn;
                        assembly {
                            recipient := calldataload(inputs.offset)
                            amountIn := calldataload(add(inputs.offset, 0x20))
                            // 0x60 offset is the path, decoded below
                        }
                        address[] calldata path = inputs.toAddressArray(3);
                        _quoteViaFacet(
                            state,
                            abi.encodeCall(
                                IV2QuoteFacet.v2QuoteExactIn,
                                (state, recipient, amountIn, V2Path.fromTokens(path), Protocols.UNISWAP_V2)
                            )
                        );
                    } else if (command == Commands.V2_SWAP_EXACT_OUT) {
                        // equivalent: abi.decode(inputs, (address, uint256, uint256, bytes, bool))
                        address recipient;
                        uint256 amountOut;
                        assembly {
                            recipient := calldataload(inputs.offset)
                            amountOut := calldataload(add(inputs.offset, 0x20))
                            // 0x60 offset is the path, decoded below
                        }
                        address[] calldata path = inputs.toAddressArray(3);
                        _quoteViaFacet(
                            state,
                            abi.encodeCall(
                                IV2QuoteFacet.v2QuoteExactOut,
                                (state, recipient, amountOut, V2Path.fromTokens(path), Protocols.UNISWAP_V2)
                            )
                        );
                    } else if (command == Commands.PERMIT2_PERMIT) {
                        revert InvalidCommandType(command);
                    } else if (command == Commands.WRAP_ETH) {
                        revert InvalidCommandType(command);
                    } else if (command == Commands.UNWRAP_WETH) {
                        revert InvalidCommandType(command);
                    } else if (command == Commands.PERMIT2_TRANSFER_FROM_BATCH) {
                        revert InvalidCommandType(command);
                    } else if (command == Commands.BALANCE_CHECK_ERC20) {
                        revert InvalidCommandType(command);
                    } else {
                        // placeholder area for command 0x0f
                        revert InvalidCommandType(command);
                    }
                }
            } else {
                // 0x10 <= command < 0x21
                if (command == Commands.V4_SWAP) {
                    _quoteActions(state, inputs);
                    // This contract MUST be approved to spend the token since its going to be doing the call on the position manager
                } else if (command == Commands.V3_POSITION_MANAGER_PERMIT) {
                    revert InvalidCommandType(command);
                } else if (command == Commands.V3_POSITION_MANAGER_CALL) {
                    revert InvalidCommandType(command);
                } else if (command == Commands.V4_INITIALIZE_POOL) {
                    revert InvalidCommandType(command);
                } else if (command == Commands.V4_POSITION_MANAGER_CALL) {
                    // should only call modifyLiquidities() to mint
                    revert InvalidCommandType(command);
                } else {
                    // placeholder area for commands 0x15-0x20
                    revert InvalidCommandType(command);
                }
            }
        } else if (command < Commands.ACROSS_V4_DEPOSIT_V3) {
            // 0x21 <= command
            if (command == Commands.EXECUTE_SUB_PLAN) {
                (bytes calldata commands_, bytes[] calldata inputs_) = inputs.decodeCommandsAndInputs();
                State memory stateSubPlan = QuoteDispatcher(address(this)).quote(state, commands_, inputs_);
                state.update(stateSubPlan);
            } else {
                // placeholder area for commands 0x22-0x3f
                revert InvalidCommandType(command);
            }
        } else if (command < Commands.VELODROME_SWAP_EXACT_IN) {
            if (command == Commands.ACROSS_V4_DEPOSIT_V3) {
                revert InvalidCommandType(command);
            } else {
                // placeholder area for commands 0x41-0x4f
                revert InvalidCommandType(command);
            }
        } else {
            if (command < Commands.SLIPSTREAM_V1_SWAP_EXACT_OUT) {
                if (command == Commands.VELODROME_SWAP_EXACT_IN) {
                    v2QuoteExactInput(state, Protocols.VELODROME, inputs);
                } else if (command == Commands.VELODROME_SWAP_EXACT_OUT) {
                    v2QuoteExactOutput(state, Protocols.VELODROME, inputs);
                } else if (command == Commands.SLIPSTREAM_V1_SWAP_EXACT_IN) {
                    v3QuoteExactInput(state, Protocols.SLIPSTREAM_V1, inputs);
                } else if (command == Commands.V2_FORK_SWAP_EXACT_IN) {
                    // equivalent: abi.decode(inputs, (address, uint256, uint256, address, address, address, uint256, bool))
                    address recipient;
                    uint256 amountIn;
                    address pair;
                    address tokenIn;
                    address tokenOut;
                    uint256 feePips;
                    assembly {
                        recipient := calldataload(inputs.offset)
                        amountIn := calldataload(add(inputs.offset, 0x20))
                        pair := calldataload(add(inputs.offset, 0x60))
                        tokenIn := calldataload(add(inputs.offset, 0x80))
                        tokenOut := calldataload(add(inputs.offset, 0xa0))
                        feePips := calldataload(add(inputs.offset, 0xc0))
                    }
                    _quoteViaFacet(
                        state,
                        abi.encodeCall(
                            IV2QuoteFacet.v2ForkQuoteExactIn,
                            (state, recipient, amountIn, pair, tokenIn, tokenOut, feePips)
                        )
                    );
                } else if (command == Commands.V3_FORK_SWAP_EXACT_IN) {
                    // equivalent: abi.decode(inputs, (address, uint256, uint256, address, address, address, bool))
                    address recipient;
                    uint256 amountIn;
                    address pool;
                    address tokenIn;
                    address tokenOut;
                    assembly {
                        recipient := calldataload(inputs.offset)
                        amountIn := calldataload(add(inputs.offset, 0x20))
                        pool := calldataload(add(inputs.offset, 0x60))
                        tokenIn := calldataload(add(inputs.offset, 0x80))
                        tokenOut := calldataload(add(inputs.offset, 0xa0))
                    }
                    v3ForkQuoteExactInput(state, recipient, amountIn, pool, tokenIn, tokenOut);
                } else {
                    // placeholder area for commands 0x55-0x57
                    revert InvalidCommandType(command);
                }
            } else if (command < Commands.METADEX_V1_SWAP_EXACT_IN) {
                if (command == Commands.SLIPSTREAM_V1_SWAP_EXACT_OUT) {
                    v3QuoteExactOutput(state, Protocols.SLIPSTREAM_V1, inputs);
                } else if (command == Commands.SLIPSTREAM_V2_SWAP_EXACT_IN) {
                    v3QuoteExactInput(state, Protocols.SLIPSTREAM_V2, inputs);
                } else if (command == Commands.SLIPSTREAM_V2_SWAP_EXACT_OUT) {
                    v3QuoteExactOutput(state, Protocols.SLIPSTREAM_V2, inputs);
                } else if (command == Commands.SLIPSTREAM_V3_SWAP_EXACT_IN) {
                    v3QuoteExactInput(state, Protocols.SLIPSTREAM_V3, inputs);
                } else if (command == Commands.SLIPSTREAM_V3_SWAP_EXACT_OUT) {
                    v3QuoteExactOutput(state, Protocols.SLIPSTREAM_V3, inputs);
                } else {
                    // placeholder area for commands 0x5d-0x5f
                    revert InvalidCommandType(command);
                }
            } else {
                if (command == Commands.METADEX_V1_SWAP_EXACT_IN) {
                    v2QuoteExactInput(state, Protocols.METADEX_V1, inputs);
                } else if (command == Commands.METADEX_CL_V1_SWAP_EXACT_IN) {
                    v3QuoteExactInput(state, Protocols.METADEX_CL_V1, inputs);
                } else if (command == Commands.METADEX_CL_V1_SWAP_EXACT_OUT) {
                    v3QuoteExactOutput(state, Protocols.METADEX_CL_V1, inputs);
                } else {
                    // placeholder area for commands 0x61 and 0x64-0x7f
                    revert InvalidCommandType(command);
                }
            }
        }
    }

    /// @notice Decodes and quotes the SwapExactInput command for Uniswap V2 type protocols, with the given inputs
    /// @param state The simulated state of the Universal Router
    /// @param protocol The Uniswap V2 type protocol
    /// @param inputs The inputs to quote the command with
    function v2QuoteExactInput(State memory state, uint256 protocol, bytes calldata inputs) internal {
        // equivalent: abi.decode(inputs, (address, uint256, uint256, bytes, bool))
        address recipient;
        uint256 amountIn;
        assembly {
            recipient := calldataload(inputs.offset)
            amountIn := calldataload(add(inputs.offset, 0x20))
            // 0x60 offset is the path, decoded below
        }
        bytes calldata path = inputs.toBytes(3);

        _quoteViaFacet(
            state, abi.encodeCall(IV2QuoteFacet.v2QuoteExactIn, (state, recipient, amountIn, path, protocol))
        );
    }

    /// @notice Decodes and quotes the SwapExactOutput command for Uniswap V2 type protocols, with the given inputs
    /// @param state The simulated state of the Universal Router
    /// @param protocol The Uniswap V2 type protocol
    /// @param inputs The inputs to quote the command with
    function v2QuoteExactOutput(State memory state, uint256 protocol, bytes calldata inputs) internal {
        // equivalent: abi.decode(inputs, (address, uint256, uint256, bytes, bool))
        address recipient;
        uint256 amountOut;
        assembly {
            recipient := calldataload(inputs.offset)
            amountOut := calldataload(add(inputs.offset, 0x20))
            // 0x60 offset is the path, decoded below
        }
        bytes calldata path = inputs.toBytes(3);

        _quoteViaFacet(
            state, abi.encodeCall(IV2QuoteFacet.v2QuoteExactOut, (state, recipient, amountOut, path, protocol))
        );
    }

    /// @notice Decodes and executes the SwapExactInput command for Uniswap V3 type protocols, with the given inputs
    /// @param protocol The Uniswap V3 type protocol
    /// @param inputs The inputs to execute the command with
    function v3QuoteExactInput(State memory state, uint256 protocol, bytes calldata inputs) internal {
        // equivalent: abi.decode(inputs, (address, uint256, uint256, bytes, bool))
        address recipient;
        uint256 amountIn;
        assembly {
            recipient := calldataload(inputs.offset)
            amountIn := calldataload(add(inputs.offset, 0x20))
            // 0x60 offset is the path, decoded below
        }
        bytes calldata path = inputs.toBytes(3);

        v3QuoteExactInput(state, recipient, amountIn, path, protocol);
    }

    /// @notice Decodes and executes the SwapExactOutput command for Uniswap V3 type protocols, with the given inputs
    /// @param protocol The Uniswap V3 type protocol
    /// @param inputs The inputs to execute the command with
    function v3QuoteExactOutput(State memory state, uint256 protocol, bytes calldata inputs) internal {
        // equivalent: abi.decode(inputs, (address, uint256, uint256, bytes, bool))
        address recipient;
        uint256 amountOut;
        assembly {
            recipient := calldataload(inputs.offset)
            amountOut := calldataload(add(inputs.offset, 0x20))
            // 0x60 offset is the path, decoded below
        }
        bytes calldata path = inputs.toBytes(3);

        v3QuoteExactOutput(state, recipient, amountOut, path, protocol);
    }

    /// @notice Quotes a command in the v2 quote facet and copies the resulting state back
    /// @param state The simulated state of the Universal Router
    /// @param call ABI-encoded facet call
    function _quoteViaFacet(State memory state, bytes memory call) private {
        State memory state_ = abi.decode(V2_QUOTE_FACET.delegate(call), (State));
        state.gasUsage = state_.gasUsage;
        state.tokenStart = state_.tokenStart;
        state.tokenIn = state_.tokenIn;
        state.tokenOut = state_.tokenOut;
        state.tokenEnd = state_.tokenEnd;
        state.flashLoan = state_.flashLoan;
    }
}
