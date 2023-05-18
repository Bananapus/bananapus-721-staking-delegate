// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@jbx-protocol/juice-721-delegate/contracts/structs/JB721Tier.sol";
import "@jbx-protocol/juice-721-delegate/contracts/structs/JBTiered721Flags.sol";

/**
 * @notice Interface for 721DelegateStore that has all the required methods for UI support.
 */
interface IJBTiered721MinimalDelegateStore {
    function tierOf(
        address _nft,
        uint256 _id,
        bool _includeResolvedUri
    ) external view returns (JB721Tier memory tier);

    function flagsOf(
        address _nft
    ) external view returns (JBTiered721Flags memory);

    function redemptionWeightOf(
        address _nft,
        uint256[] memory _tokenIds
    ) external view returns (uint256 weight);

    function totalRedemptionWeight(
        address _nft
    ) external view returns (uint256 weight);
}
