// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Interface for 721Delegate that has all the required methods for UI support.
interface IJBTiered721MinimalDelegate {
    function contractURI() external view returns (string memory);
    function store() external view returns (address);
}
