// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

/// @title V4RouterActions
/// @notice v4 action ids owned by this router, extending v4-periphery's Actions
/// @dev 0x50-0x5f is reserved for this router. Upstream v4-periphery occupies 0x00-0x1b
library V4RouterActions {
    // Runs a nested router plan inside the open v4 lock
    uint256 internal constant EXECUTE_SUB_PLAN_ACTION = 0x50;
}
