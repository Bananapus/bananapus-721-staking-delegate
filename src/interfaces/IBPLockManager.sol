// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

/***
 * @notice 
 * Interface for a contract that is able to lock positions, 
 * this interface contains the methods that are required by `JB721StakingDelegate`.
 */
interface IBPLockManager {
    /**
     * @notice hook (optionally) called upon registration to simplify UX
     * @param _id the id of the token being locked
     * @param _data data regarding the lock as send by the user, can be any data
     */
    function onRegistration(uint256 _id, bytes[] calldata _data) external;

    /**
     * @notice hook called upon redemption, if a token had its 
     * @param _id the id of the token being redeemed
     */
    function onRedeem(uint256 _id) external;

    /**
     * @param _token the staking token
     * @param _id the token ID of the staking token to check
     * @return If the token is currently unlocked or not
     */
    function isUnlocked(address _token, uint256 _id) external view returns (bool);
}