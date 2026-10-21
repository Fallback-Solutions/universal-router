// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

type Facet is address;

/// @title FacetLib
/// @notice `delegatecall` to a `Facet` with bubbled reverts
library FacetLib {
    /// @notice Delegatecalls `facet` and returns the raw response
    /// @param facet Facet to delegatecall into
    /// @param call ABI-encoded calldata
    /// @return result Raw return data
    function delegate(Facet facet, bytes memory call) internal returns (bytes memory result) {
        bool success;
        // forge-lint: disable-next-item(controlled-delegatecall, delegatecall-loop)
        (success, result) = Facet.unwrap(facet).delegatecall(call);
        if (!success) {
            assembly ('memory-safe') {
                revert(add(result, 0x20), mload(result))
            }
        }
    }
}
