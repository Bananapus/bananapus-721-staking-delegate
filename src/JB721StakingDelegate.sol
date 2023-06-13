// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBTokenUriResolver.sol";
import "@jbx-protocol/juice-721-delegate/contracts/abstract/JB721Delegate.sol";
import "@jbx-protocol/juice-721-delegate/contracts/libraries/JBIpfsDecoder.sol";
import "@jbx-protocol/juice-721-delegate/contracts/abstract/Votes.sol";
import "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721Delegate.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IJB721StakingDelegate.sol";
import "./interfaces/IJBTiered721MinimalDelegate.sol";
import "./interfaces/IJBTiered721MinimalDelegateStore.sol";
import "./struct/JB721StakingTier.sol";

contract JB721StakingDelegate is
    Votes,
    JB721Delegate,
    IJB721StakingDelegate,
    IJBTiered721MinimalDelegate,
    IJBTiered721MinimalDelegateStore
{
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//
    error DELEGATION_NOT_ALLOWED();
    error INVALID_TOKEN();
    error STAKE_NOT_ENOUGH_FOR_TIER(uint16 _tier, uint256 _minAmount, uint256 _providedAmount);
    error INSUFFICIENT_VALUE();
    error OVERSPENDING();
    error INVALID_METADATA();

    //*********************************************************************//
    // -------------------- private constant properties ------------------ //
    //*********************************************************************//
    uint256 private constant _ONE_BILLION = 1_000_000_000;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//
    /**
     * @notice
     * The address of the singleton 'JB721StakingDelegate'
     */
    address public immutable override codeOrigin;

    /**
     * @notice
     * The staking token for this delegate, this is the only token that we accept in payments
     */
    IERC20 public stakingToken;

    /**
     * @dev A mapping of staked token balances per id
     */
    mapping(uint256 => uint256) public stakingTokenBalance;

    /**
     * @dev A mapping of (current) voting power for the users
     */
    mapping(address => uint256) public userVotingPower;

    /**
     * @dev the number of tokens minted for each tierID
     */
    mapping(uint256 => uint256) public numberOfTokensMintedOfTier;

    /**
     * @notice
     *   The contract that stores and manages the NFT's data.
     */
    IJBTokenUriResolver public uriResolver;

    /**
     * @notice
     * Contract metadata uri.
     */
    string public override contractURI;

    /**
     * @notice
     * The common base for the tokenUri's
     *
     */
    string public baseURI;

    /**
     * @notice
     * encoded baseURI to be used when no token resolver provided
     *
     */
    bytes32 public encodedIPFSUri;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /**
     * @notice
     * Returns information for a specific tier.
     *
     * @param _id the TierID
     * @param _includeResolvedUri if the tierURI should be resolved
     */
    function tierOf(address, uint256 _id, bool _includeResolvedUri) external view returns (JB721Tier memory tier) {
        _includeResolvedUri;

        uint256 _price = _getTierMinStake(uint16(_id));
        bytes32 _encodedIPFSUri;

        return JB721Tier({
            id: _id,
            price: _price,
            remainingQuantity: type(uint128).max - numberOfTokensMintedOfTier[_id],
            initialQuantity: type(uint128).max,
            votingUnits: _price,
            reservedRate: type(uint256).max,
            reservedTokenBeneficiary: address(0),
            royaltyRate: 0,
            royaltyBeneficiary: address(0),
            encodedIPFSUri: _encodedIPFSUri,
            category: 0,
            allowManualMint: false,
            transfersPausable: false,
            useVotingUnits: false
        });
    }

    /**
     * @notice
     * The store for this delegate.
     * @dev To save gas and simplify the contract this address is both the delegate and the store.
     */
    function store() external view override returns (address) {
        // We store everything at this contract to save some gas on the calls.
        return address(this);
    }

    /**
     * @notice
     * Flags for the delegate.
     */
    function flagsOf(address) external pure returns (JBTiered721Flags memory) {
        return JBTiered721Flags({
            lockReservedTokenChanges: true,
            lockVotingUnitChanges: true,
            lockManualMintingChanges: true,
            preventOverspending: true
        });
    }

    /**
     * @notice
     * Calculate the redeem value for a set of tokenIds.
     *
     * @param _tokenIds The tokenIds to calculate the redeem value for.
     *
     * @return weight The redemption weight of the set of tokens.
     */
    function redemptionWeightOf(address, uint256[] memory _tokenIds) external view returns (uint256 weight) {
        return _redemptionWeightOf(_tokenIds);
    }

    /**
     * @notice
     * The sum of all redemptions .
     * @param -
     *
     * @return weight the total weight.
     */
    function totalRedemptionWeight(address) external view returns (uint256 weight) {
        return _getTotalSupply();
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /**
     * @notice
     * The cumulative weight the given token IDs have in redemptions compared to the `totalRedemptionWeight`.
     *
     * @param _tokenIds The IDs of the tokens to get the cumulative redemption weight of.
     *
     * @return _value The weight.
     */
    function redemptionWeightOf(uint256[] memory _tokenIds, JBRedeemParamsData calldata)
        public
        view
        virtual
        override
        returns (uint256 _value)
    {
        return _redemptionWeightOf(_tokenIds);
    }

    /**
     * @notice
     * The cumulative weight that all token IDs have in redemptions.
     *
     * @return The total weight.
     */
    function totalRedemptionWeight(JBRedeemParamsData calldata) public view virtual override returns (uint256) {
        return _getTotalSupply();
    }

    /**
     * @notice
     * Indicates if this contract adheres to the specified interface.
     *
     * @dev
     * See {IERC165-supportsInterface}.
     *
     * @param _interfaceId The ID of the interface to check for adherence to.
     */
    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return _interfaceId == type(IJB721StakingDelegate).interfaceId || _interfaceId == type(IERC2981).interfaceId
            || super.supportsInterface(_interfaceId);
    }

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    constructor() {
        codeOrigin = address(this);
    }

    function initialize(
        uint256 _projectId,
        IERC20 _stakingToken,
        IJBDirectory _directory,
        IJBTokenUriResolver _uriResolver,
        string memory _name,
        string memory _symbol,
        string memory _contractURI,
        string memory _baseURI,
        bytes32 _encodedIPFSUri
    ) external {
        // Make the original un-initializable.
        if (address(this) == codeOrigin) revert();

        // Stop re-initialization.
        if (projectId != 0) revert();

        stakingToken = _stakingToken;

        uriResolver = _uriResolver;

        contractURI = _contractURI;

        encodedIPFSUri = _encodedIPFSUri;

        baseURI = _baseURI;

        // Initialize the superclass.
        JB721Delegate._initialize(_projectId, _directory, _name, _symbol);
    }

    /**
     * @notice
     * The metadata URI of the provided token ID.
     *
     * @dev
     * Defer to the tokenUriResolver if set, otherwise, use the tokenUri set with the token's tier.
     *
     * @param _tokenId The ID of the token to get the tier URI for.
     *
     * @return The token URI corresponding with the tier or the tokenUriResolver URI.
     */
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        // If a token URI resolver is provided, use it to resolve the token URI.
        if (address(uriResolver) != address(0)) {
            return uriResolver.getUri(_tokenId);
        }

        // Return the token URI for the token's tier.
        return JBIpfsDecoder.decode(baseURI, encodedIPFSUri);
    }

    //*********************************************************************//
    // ------------------------ internal functions ----------------------- //
    //*********************************************************************//

    /**
     * @notice
     * The voting units for an account from its NFTs across all tiers. NFTs have a tier-specific preset number of voting
     * units.
     *
     * @param _account The account to get voting units for.
     *
     * @return units The voting units for the account.
     */
    function _getVotingUnits(address _account) internal view virtual override returns (uint256 units) {
        return userVotingPower[_account];
    }

    /**
     * @notice
     * Delegate all of `account`'s voting units to `delegatee`.
     *
     * @param _account The account delegating all voting units.
     * @param _delegatee The account to delegate all voting units to.
     */
    function _delegateTier(address _account, address _delegatee) internal virtual {
        _delegate(_account, _delegatee);
    }

    /**
     * @notice
     * Process a received payment.
     *
     * @param _data The Juicebox standard project payment data.
     */
    function _processPayment(JBDidPayData calldata _data) internal virtual override {
        // Only payment in the staking token is allowed
        if (IERC20(_data.amount.token) != stakingToken) {
            revert INVALID_TOKEN();
        }

        uint256 _leftoverAmount = _data.amount.value;

        // Keep a reference to the address that should be given attestation votes from this mint.
        address _votingDelegate;

        // Skip the first 32 bytes which are used by the JB protocol to pass the referring project's ID.
        // Skip another 32 bytes reserved for generic extension parameters.
        // Check the 4 bytes interfaceId to verify the metadata is intended for this contract.
        if (_data.metadata.length > 68) {
            if (bytes4(_data.metadata[64:68]) == type(IJB721StakingDelegate).interfaceId) {
                // Keep a reference to the the specific tier IDs to mint.
                JB721StakingTier[] memory _tierIdsToMint;

                // TODO: Possibly add voting power delegation to the metadata to simplify UX
                // Decode the metadata.
                (,,,, _votingDelegate, _tierIdsToMint) = abi.decode(_data.metadata, (bytes32, bytes32, bytes4, bool, address, JB721StakingTier[]));
                if (_votingDelegate != address(0) && _data.payer != _data.beneficiary) revert DELEGATION_NOT_ALLOWED();

                // Mint the specified tiers with the custom stake amount
                _leftoverAmount = _mintTiersWithCustomAmount(_leftoverAmount, _tierIdsToMint, _data.beneficiary, _votingDelegate);
            } else if (bytes4(_data.metadata[64:68]) == type(IJBTiered721Delegate).interfaceId) {
                // Keep a reference to the the specific tier IDs to mint.
                uint16[] memory _tierIdsToMint;

                // Decode the metadata.
                (,,,, _tierIdsToMint) = abi.decode(_data.metadata, (bytes32, bytes32, bytes4, bool, uint16[]));

                // Mint the specified tiers
                _leftoverAmount = _mintTiers(_leftoverAmount, _tierIdsToMint, _data.beneficiary);
            }
        }

        // The user has to spend all of their tokens
        if (_leftoverAmount != 0) {
            revert OVERSPENDING();
        }
    }

    /**
     * @notice 
     *     Part of IJBFundingCycleDataSource, this function gets called when a project's token holders redeem.
     * 
     *     @param _data The Juicebox standard project redemption data.
     * 
     *     @return reclaimAmount The amount that should be reclaimed from the treasury.
     *     @return memo The memo that should be forwarded to the event.
     *     @return delegateAllocations The amount to send to delegates instead of adding to the beneficiary.
     */
    function redeemParams(JBRedeemParamsData calldata _data)
        public
        view
        virtual
        override
        returns (uint256 reclaimAmount, string memory memo, JBRedemptionDelegateAllocation[] memory delegateAllocations)
    {
        // Make sure fungible project tokens aren't being redeemed too.
        if (_data.tokenCount > 0) revert UNEXPECTED_TOKEN_REDEEMED();

        // Check the 4 bytes interfaceId and handle the case where the metadata was not intended for this contract
        // Skip 32 bytes reserved for generic extension parameters.
        if (_data.metadata.length < 36 || bytes4(_data.metadata[32:36]) != type(IJB721Delegate).interfaceId) {
            revert INVALID_REDEMPTION_METADATA();
        }

        // Set the only delegate allocation to be a callback to this contract.
        delegateAllocations = new JBRedemptionDelegateAllocation[](1);
        delegateAllocations[0] = JBRedemptionDelegateAllocation(this, 0);

        // Decode the metadata
        (,, uint256[] memory _decodedTokenIds) = abi.decode(_data.metadata, (bytes32, bytes4, uint256[]));

        return (redemptionWeightOf(_decodedTokenIds, _data), _data.memo, delegateAllocations);
    }



    /**
     * @notice
     * Mint tiers according to the spec of the regular 721-delegate.
     *
     * @param _value The value of the payment.
     * @param _tierIdsToMint The tier ids to mint.
     * @param _beneficiary The beneficiary of the mint.
     *
     * @return _leftoverAmount The amount that is left over after the tiers were minted.
     */
    function _mintTiers(uint256 _value, uint16[] memory _tierIdsToMint, address _beneficiary)
        internal
        returns (uint256 _leftoverAmount)
    {
        _leftoverAmount = _value;
        uint256 _mintsLength = _tierIdsToMint.length;

        for (uint256 _i; _i < _mintsLength;) {
            uint16 _tierId = _tierIdsToMint[_i];
            uint256 _tierMinAmount = _getTierMinStake(_tierId);

            if (_leftoverAmount < _tierMinAmount) {
                revert INSUFFICIENT_VALUE();
            }

            unchecked {
                _leftoverAmount -= _tierMinAmount;
            }

            _mintTier(_tierId, _tierMinAmount, _beneficiary);

            unchecked {
                ++_i;
            }
        }
    }

    /**
     * @notice
     * Mint tiers with a custom stake amount.
     *
     * @param _value The payment value.
     * @param _tiers The tiers and stake amount to be minted.
     * @param _beneficiary The beneficiary of the mint.
     * @param _votingDelegate The voting delegate address.
     *
     * @return _leftoverAmount The amount that is left over after the tiers were minted.
     */
    function _mintTiersWithCustomAmount(uint256 _value, JB721StakingTier[] memory _tiers, address _beneficiary, address _votingDelegate)
        internal
        returns (uint256 _leftoverAmount)
    {
        _leftoverAmount = _value;
        uint256 _mintsLength = _tiers.length;

        for (uint256 _i; _i < _mintsLength;) {
            uint256 _tierMinAmount = _getTierMinStake(_tiers[_i].tierId);

            if (_tiers[_i].amount < _tierMinAmount) {
                revert STAKE_NOT_ENOUGH_FOR_TIER(_tiers[_i].tierId, _tierMinAmount, _tiers[_i].amount);
            }

            if (_leftoverAmount < _tiers[_i].amount) {
                revert INSUFFICIENT_VALUE();
            }

            unchecked {
                _leftoverAmount -= _tiers[_i].amount;
            }

            // If there's either a new delegate or old delegate, increase the delegate weight.
            if (_votingDelegate != address(0)) {
                _delegateTier(_beneficiary, _votingDelegate);
            }

            _mintTier(_tiers[_i].tierId, _tiers[_i].amount, _beneficiary);

            unchecked {
                ++_i;
            }
        }
    }

    /**
     * @notice
     * The accounting logic for minting a single tier.
     *
     * @param _tierId The tier id to mint.
     * @param _stakeAmount The amount that is being staked.
     * @param _beneficiary The address that is the beneficiary of the mint.
     *
     * @return _tokenId the id of the token that was minted
     */
    function _mintTier(uint16 _tierId, uint256 _stakeAmount, address _beneficiary)
        internal
        returns (uint256 _tokenId)
    {
        unchecked {
            _tokenId = _generateTokenId(_tierId, ++numberOfTokensMintedOfTier[_tierId]);
        }

        // Track how much this NFT is worth
        stakingTokenBalance[_tokenId] = _stakeAmount;

        // Mint the token.
        _mint(_beneficiary, _tokenId);
    }

    /**
     * @notice
     * Get the minimum required stake for the TierID.
     * @dev Reverts if the tierID does not exist
     *
     * @param _tier The tierID to get the minimum stake for.
     *
     * @return _minStakeAmount The minimum required stake.
     */
    function _getTierMinStake(uint16 _tier) internal pure returns (uint256 _minStakeAmount) {
        _tier;
        // TODO: Implement

        // Has to revert of the tier does not exist
        return 100 ether;
    }

    /**
     * @notice
     * Finds the token ID and tier given a contribution amount.
     *
     * @param _tierId The ID of the tier to generate an ID for.
     * @param _tokenNumber The number of the token in the tier.
     *
     * @return The ID of the token.
     */
    function _generateTokenId(uint256 _tierId, uint256 _tokenNumber) internal pure returns (uint256) {
        return (_tierId * _ONE_BILLION) + _tokenNumber;
    }

    /**
     * @notice
     * The tier number of the provided token ID.
     *
     * @dev Tier's are 1 indexed from the `tiers` array, meaning the 0th element of the array is tier 1.
     *
     * @param _tokenId The ID of the token to get the tier number of.
     *
     * @return The tier number of the specified token ID.
     */
    function tierIdOfToken(uint256 _tokenId) public pure returns (uint256) {
        return _tokenId / _ONE_BILLION;
    }

    /**
     * @notice
     * Transfer voting units after the transfer of a token.
     *
     * @param _from The address where the transfer is originating.
     * @param _to The address to which the transfer is being made.
     * @param _tokenId The ID of the token being transferred.
     */
    function _afterTokenTransfer(address _from, address _to, uint256 _tokenId) internal virtual override {
        uint256 _stakingValue = stakingTokenBalance[_tokenId];

        if (_from != address(0)) userVotingPower[_from] -= _stakingValue;
        if (_to != address(0)) userVotingPower[_to] += _stakingValue;

        // Transfer the voting units.
        _transferVotingUnits(_from, _to, _stakingValue);

        super._afterTokenTransfer(_from, _to, _tokenId);
    }

    /**
     * @notice
     * Calculates the combined redemption weight of the given token IDs.
     * @param _tokenIds The IDs of the tokens to get the cumulative redemption weight of.
     */
    function _redemptionWeightOf(uint256[] memory _tokenIds) internal view returns (uint256 _weight) {
        uint256 _nOfTokens = _tokenIds.length;
        for (uint256 _i; _i < _nOfTokens;) {
            unchecked {
                // Add the staked value that the nft represents
                // and increment the loop
                _weight += stakingTokenBalance[_tokenIds[_i++]];
            }
        }
    }
}
