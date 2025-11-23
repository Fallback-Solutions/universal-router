// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

interface IUniversalQuoter {
    /// @notice Thrown when attempting to execute commands and an incorrect number of inputs are provided
    error LengthMismatch();
}
