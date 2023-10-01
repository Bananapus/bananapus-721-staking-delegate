// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

/**
 * @param tierId the tier to mint
 * @param amount the amount to stake (has to be more than the tier minimum amount)
 */
struct JB721StakingTier {
    uint16 tierId;
    uint128 amount;
}
