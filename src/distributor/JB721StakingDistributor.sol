// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import { JBDistributor } from "lib/bananapus-distributor/src/JBDistributor.sol";
import { JB721StakingDelegate } from "../JB721StakingDelegate.sol";

contract JB721StakingDistributor is JBDistributor {

    JB721StakingDelegate immutable delegate;

    /**
     * 
     * @param _periodicity The duration of a period/cycle in blocks
     * @param _vestingCycles The number of cycles it takes for rewards to vest
     */
    constructor(JB721StakingDelegate _delegate, uint256 _periodicity, uint256 _vestingCycles) JBDistributor(_periodicity, _vestingCycles) {
        delegate = _delegate;
    }

    function _tokenStake(uint256 _tokenId) internal view virtual override returns (uint256 _tokenStakeAmount) {
        return delegate.stakingTokenBalance(_tokenId);
    }


    function _totalStake(uint256 _blockNumber) internal view virtual override returns (uint256 _stakedAmount) {
        return delegate.getPastTotalSupply(_blockNumber);
    }
}