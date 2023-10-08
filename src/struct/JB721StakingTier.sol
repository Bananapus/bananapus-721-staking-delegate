// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @custom:member tierId The ID of the tier to mint.
/// @custom:param amount The amount to stake. Must be more than the tier minimum amount.
struct JB721StakingTier {
    uint16 tierId;
    uint128 amount;
}
