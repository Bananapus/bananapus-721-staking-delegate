// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./IJB721StakingDelegateStore.sol";
import "./IBPLockManager.sol";

interface IJB721StakingDelegate {
    function isApprovedOrOwner(
        address _spender,
        uint256 _tokenId
    ) external view returns (bool _isAllowed);

    function stakingTokenBalance(
        uint256 _tokenId
    ) external view returns (uint256 _amount);

    function lockManager(
        uint256 _tokenID
    ) external view returns (IBPLockManager _lockManager);
}
