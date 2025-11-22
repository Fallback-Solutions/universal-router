// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {V2SwapRouter} from '../modules/uniswap/v2/V2SwapRouter.sol';
import {V3SwapQuoter} from '../modules/uniswap/v3/V3SwapQuoter.sol';
import {V4SwapQuoter} from '../modules/uniswap/v4/V4SwapQuoter.sol';
import {BytesLib} from '../modules/uniswap/v3/BytesLib.sol';
import {Payments} from '../modules/Payments.sol';
import {PaymentsImmutables} from '../modules/PaymentsImmutables.sol';
import {Commands} from '../libraries/Commands.sol';
import {ERC20} from 'solmate/src/tokens/ERC20.sol';
import {IAllowanceTransfer} from 'permit2/src/interfaces/IAllowanceTransfer.sol';
import {ActionConstants} from '@uniswap/v4-periphery/src/libraries/ActionConstants.sol';
import {CalldataDecoder} from '@uniswap/v4-periphery/src/libraries/CalldataDecoder.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {Protocols} from '../libraries/Protocols.sol';
import {QuoterStateLib, State} from '../libraries/QuoterState.sol';

/// @title Decodes and Executes Commands
/// @notice Called by the UniversalQuoter contract to efficiently decode and execute a singular command
abstract contract QuoteDispatcher is Payments, V2SwapRouter, V3SwapQuoter, V4SwapQuoter {
    using BytesLib for bytes;
    using CalldataDecoder for bytes;
    using QuoterStateLib for State;

    address internal transient _msgSender;

    error InvalidCommandType(uint256 commandType);

    /// @notice Quotes encoded commands along with provided inputs.
    /// @param commands A set of concatenated commands, each 1 byte in length
    /// @param inputs An array of byte strings containing abi encoded inputs for each command
    /// @param msgSender_ The address of the msg.sender of the swap
    /// @param tokenStartBalance The initial balance of tokenStart
    /// @return tokenStartBalance_ The final balance of tokenStart
    /// @return amountOut The amount of tokenOut received
    /// @return gasEstimate The gas estimate for executing the commands
    function quote(bytes calldata commands, bytes[] calldata inputs, address msgSender_, uint256 tokenStartBalance)
        external
        virtual
        returns (uint256 tokenStartBalance_, uint256 amountOut, uint256 gasEstimate);

    /// @notice Public view function to be used instead of msg.sender, as the contract performs self-reentrancy and at
    /// times msg.sender == address(this). Instead msgSender() returns the initiator of the lock
    /// @dev overrides BaseActionsRouter.msgSender in V4Router
    function msgSender() public view override returns (address) {
        return _msgSender;
    }

    /// @notice Decodes and executes the given command with the given inputs
    /// @param commandType The command type to execute
    /// @param inputs The inputs to execute the command with
    /// @param state The contracts available balances of tokenIn and tokenOut
    /// @dev 2 masks are used to enable use of a nested-if statement in execution for efficiency reasons
    /// @return gasEstimate The gas estimate for executing the command
    function dispatch(bytes1 commandType, bytes calldata inputs, State memory state)
        internal
        returns (uint256 gasEstimate)
    {
        uint256 command = uint8(commandType & Commands.COMMAND_TYPE_MASK);

        // 0x00 <= command < 0x21
        if (command < Commands.EXECUTE_SUB_PLAN) {
            // 0x00 <= command < 0x10
            if (command < Commands.V4_SWAP) {
                // 0x00 <= command < 0x08
                if (command < Commands.V2_SWAP_EXACT_IN) {
                    if (command == Commands.V3_SWAP_EXACT_IN) {
                        gasEstimate = v3QuoteExactInput(state, Protocols.UNISWAP_V3, inputs);
                    } else if (command == Commands.V3_SWAP_EXACT_OUT) {
                        gasEstimate = v3QuoteExactOutput(state, Protocols.UNISWAP_V3, inputs);
                    } else if (command == Commands.PERMIT2_TRANSFER_FROM) {
                        revert InvalidCommandType(command);
                    } else if (command == Commands.PERMIT2_PERMIT_BATCH) {
                        revert InvalidCommandType(command);
                    } else if (command == Commands.SWEEP) {
                        address token;
                        address recipient;
                        assembly {
                            token := calldataload(inputs.offset)
                            recipient := calldataload(add(inputs.offset, 0x20))
                        }
                        state.sweep(token, map(recipient));
                        // Gas estimate is the worst case erc20-transfer cost (cold sstore).
                        gasEstimate = 20_000;
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
                        revert InvalidCommandType(command);
                    } else if (command == Commands.V2_SWAP_EXACT_OUT) {
                        revert InvalidCommandType(command);
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
                    gasEstimate = _quoteActions(state, inputs);
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
                (bytes calldata _commands, bytes[] calldata _inputs) = inputs.decodeCommandsAndInputs();

                uint256 amountOut;
                (state.tokenIn.balance, amountOut, gasEstimate) =
                    QuoteDispatcher(address(this)).quote(_commands, _inputs, address(0), state.tokenIn.balance);
                state.tokenOut.balance += amountOut;
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
                    revert InvalidCommandType(command);
                } else if (command == Commands.VELODROME_SWAP_EXACT_OUT) {
                    revert InvalidCommandType(command);
                } else if (command == Commands.SLIPSTREAM_V1_SWAP_EXACT_IN) {
                    gasEstimate = v3QuoteExactInput(state, Protocols.SLIPSTREAM_V1, inputs);
                } else {
                    // placeholder area for commands 0x53-0x57
                    revert InvalidCommandType(command);
                }
            } else {
                if (command == Commands.SLIPSTREAM_V1_SWAP_EXACT_OUT) {
                    gasEstimate = v3QuoteExactOutput(state, Protocols.SLIPSTREAM_V1, inputs);
                } else if (command == Commands.SLIPSTREAM_V2_SWAP_EXACT_IN) {
                    gasEstimate = v3QuoteExactInput(state, Protocols.SLIPSTREAM_V2, inputs);
                } else if (command == Commands.SLIPSTREAM_V2_SWAP_EXACT_OUT) {
                    gasEstimate = v3QuoteExactOutput(state, Protocols.SLIPSTREAM_V2, inputs);
                } else {
                    // placeholder area for commands 0x5b-0x5f
                    revert InvalidCommandType(command);
                }
            }
        }
    }

    /// @notice Decodes and executes the SwapExactInput command for Uniswap V3 type protocols, with the given inputs
    /// @param protocol The Uniswap V3 type protocol
    /// @param inputs The inputs to execute the command with
    function v3QuoteExactInput(State memory state, uint256 protocol, bytes calldata inputs)
        internal
        returns (uint256 gasEstimate)
    {
        // equivalent: abi.decode(inputs, (address, uint256, uint256, bytes, bool))
        address recipient;
        uint256 amountIn;
        assembly {
            recipient := calldataload(inputs.offset)
            amountIn := calldataload(add(inputs.offset, 0x20))
            // 0x60 offset is the path, decoded below
        }
        bytes calldata path = inputs.toBytes(3);

        gasEstimate = v3QuoteExactInput(state, map(recipient), amountIn, path, protocol);
    }

    /// @notice Decodes and executes the SwapExactOutput command for Uniswap V3 type protocols, with the given inputs
    /// @param protocol The Uniswap V3 type protocol
    /// @param inputs The inputs to execute the command with
    function v3QuoteExactOutput(State memory state, uint256 protocol, bytes calldata inputs)
        internal
        returns (uint256 gasEstimate)
    {
        // equivalent: abi.decode(inputs, (address, uint256, uint256, bytes, bool))
        address recipient;
        uint256 amountOut;
        assembly {
            recipient := calldataload(inputs.offset)
            amountOut := calldataload(add(inputs.offset, 0x20))
            // 0x60 offset is the path, decoded below
        }
        bytes calldata path = inputs.toBytes(3);

        gasEstimate = v3QuoteExactOutput(state, map(recipient), amountOut, path, protocol);
    }

    /// @notice Calculates the recipient address for a command
    /// @param recipient The recipient or recipient-flag for the command
    /// @return output The resultant recipient for the command
    function map(address recipient) internal view returns (address) {
        if (recipient == ActionConstants.MSG_SENDER) {
            return msgSender();
        } else if (recipient == ActionConstants.ADDRESS_THIS) {
            return address(this);
        } else {
            return recipient;
        }
    }
}
