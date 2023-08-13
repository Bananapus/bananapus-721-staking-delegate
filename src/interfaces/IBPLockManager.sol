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
     * @param _payer the person who send the transaction and paid for the staked position
     * @param _beneficiary the person who received the staked position
     * @param _tokenID the id of the token being locked
     * @param _data data regarding the lock as send by the user, can be any data.
     */
    function onRegistration(
        address _payer,
        address _beneficiary,
        uint256 _tokenID,
        bytes calldata _data
    ) external;

    /**
     * @notice hook called upon redemption, if a token had its 
     * @param _tokenID the id of the token being redeemed
     * @param _owner the current owner of the token
     */
    function onRedeem(uint256 _tokenID, address _owner) external;

    /**
     * @param _delegate the staking token
     * @param _id the token ID of the staking token to check
     * @return If the token is currently unlocked or not
     */
    function isUnlocked(address _delegate, uint256 _id) external view returns (bool);
}