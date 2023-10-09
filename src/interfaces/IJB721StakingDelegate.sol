// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBPLockManager} from "./IBPLockManager.sol";

interface IJB721StakingDelegate {
    event LockManagerUpdated(uint256 indexed _tokenID, address _lockManager);

    function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool _isAllowed);

    function stakingTokenBalance(uint256 _tokenId) external view returns (uint256 _amount);

    function lockManager(uint256 _tokenID) external view returns (IBPLockManager _lockManager);
}
