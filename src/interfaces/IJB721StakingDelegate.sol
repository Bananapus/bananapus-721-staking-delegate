// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./IJB721StakingDelegateStore.sol";

interface IJB721StakingDelegate {
    function codeOrigin() external view returns (address);

    // function store() external view returns (IJB721StakingDelegateStore);
}
