// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBTokenUriResolver.sol";
import "@jbx-protocol/juice-721-delegate/contracts/abstract/JB721Delegate.sol";
import "@jbx-protocol/juice-721-delegate/contracts/libraries/JBIpfsDecoder.sol";
import "@jbx-protocol/juice-721-delegate/contracts/abstract/Votes.sol";
import "./interfaces/IJB721StakingDelegate.sol";
import "./interfaces/IJBTiered721MinimalDelegate.sol";
import "./interfaces/IJBTiered721MinimalDelegateStore.sol";

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
    error INVALID_TOKEN();
    error OVERSPENDING();
    error INVALID_METADATA();

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//
    /**
      @notice
      The address of the origin 'JB721StakingDelegate', used to check in the init if the contract is the original or not
    */
    address public override codeOrigin;

    /**
     * @dev A mapping of staked token balances per id
     */
    mapping(uint256 => uint256) public stakingTokenBalance;

    /**
     * @dev A mapping of (current) voting power for the users
     */
    mapping(address => uint256) public userVotingPower;

    /**
     * @notice
     */
    uint256 public numberOfTokensMinted;

    /**
      @notice
      The contract that stores and manages the NFT's data.
    */
    IJBTokenUriResolver public uriResolver;

    /**
     * @notice
     * Contract metadata uri.
     *
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

    function tierOf(
        address,
        uint256 _id,
        bool _includeResolvedUri
    ) external view returns (JB721Tier memory tier) {
        _includeResolvedUri;

        uint256 _tierMinted = 100;
        uint256 _price = 1 ether;
        bytes32 _encodedIPFSUri;

        return
            JB721Tier({
                id: _id,
                price: _price,
                remainingQuantity: type(uint128).max - _tierMinted,
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

    function store() external view override returns (address) {
        // We store everything at this contract to save some gas on the calls.
        return address(this);
    }

    function flagsOf(address) external pure returns (JBTiered721Flags memory) {
        return
            JBTiered721Flags({
                lockReservedTokenChanges: true,
                lockVotingUnitChanges: true,
                lockManualMintingChanges: true,
                preventOverspending: true
            });
    }

    function redemptionWeightOf(
        address,
        uint256[] memory _tokenIds
    ) external view returns (uint256 weight) {
        return _redemptionWeightOf(_tokenIds);
    }

    function totalRedemptionWeight(
        address
    ) external view returns (uint256 weight) {
        return _getTotalSupply();
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /** 
    @notice
    The cumulative weight the given token IDs have in redemptions compared to the `totalRedemptionWeight`. 

    @param _tokenIds The IDs of the tokens to get the cumulative redemption weight of.

    @return _value The weight.
  */
    function redemptionWeightOf(
        uint256[] memory _tokenIds,
        JBRedeemParamsData calldata
    ) public view virtual override returns (uint256 _value) {
        return _redemptionWeightOf(_tokenIds);
    }

    /** 
    @notice
    The cumulative weight that all token IDs have in redemptions. 

    @return The total weight.
  */
    function totalRedemptionWeight(
        JBRedeemParamsData calldata
    ) public view virtual override returns (uint256) {
        return _getTotalSupply();
    }

    /**
      @notice
      Indicates if this contract adheres to the specified interface.

      @dev
      See {IERC165-supportsInterface}.

      @param _interfaceId The ID of the interface to check for adherence to.
    */
    function supportsInterface(
        bytes4 _interfaceId
    ) public view virtual override returns (bool) {
        return
            _interfaceId == type(IJB721StakingDelegate).interfaceId ||
            _interfaceId == type(IERC2981).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    constructor() {
        codeOrigin = address(this);
    }

    function initialize(
        uint256 _projectId,
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
    function tokenURI(
        uint256 _tokenId
    ) public view override returns (string memory) {
        // If a token URI resolver is provided, use it to resolve the token URI.
        if (address(uriResolver) != address(0))
            return uriResolver.getUri(_tokenId);

        // Return the token URI for the token's tier.
        return JBIpfsDecoder.decode(baseURI, encodedIPFSUri);
    }

    //*********************************************************************//
    // ------------------------ internal functions ----------------------- //
    //*********************************************************************//

    /** 
    @notice
    Process a received payment.

    @param _data The Juicebox standard project payment data.
  */
    function _processPayment(
        JBDidPayData calldata _data
    ) internal virtual override {
         uint256 _leftoverAmount = _data.amount.value;

        // Skip the first 32 bytes which are used by the JB protocol to pass the referring project's ID.
        // Skip another 32 bytes reserved for generic extension parameters.
        // Check the 4 bytes interfaceId to verify the metadata is intended for this contract.
        if (
            _data.metadata.length > 68 &&
            bytes4(_data.metadata[64:68]) == type(IJB721StakingDelegate).interfaceId
        ) {
            // TODO: Check if we should be using this interface or use another one

            // Keep a reference to the the specific tier IDs to mint.
            uint16[] memory _tierIdsToMint;

            // Decode the metadata.
            (, , , , _tierIdsToMint) = abi.decode(
                _data.metadata,
                (bytes32, bytes32, bytes4, bool, uint16[])
            );
            
            // Mint the specified tiers
            _leftoverAmount = _mintTiers(_leftoverAmount, _tierIdsToMint, _data.beneficiary);
            // If 
            if(_leftoverAmount != 0)
                revert OVERSPENDING();
        } else {
            // For this delegate the user needs to pass the correct metadata
            revert INVALID_METADATA();
        }

    }

    /**
    @notice
    The voting units for an account from its NFTs across all tiers. NFTs have a tier-specific preset number of voting units. 

    @param _account The account to get voting units for.

    @return units The voting units for the account.
  */
    function _getVotingUnits(
        address _account
    ) internal view virtual override returns (uint256 units) {
        return userVotingPower[_account];
    }

    function _mintTiers(
        uint256 _value,
        uint16[] memory _tierIdsToMint,
        address _beneficiary
    ) internal returns (uint256 _leftoverAmount) {
        _value; _tierIdsToMint; _beneficiary;

        uint256 _mintsLength = _tierIdsToMint.length;

         for (uint256 _i; _i < _mintsLength; ) {
            uint256 _tokenId;

            // TODO: replace with a correct amount
            uint256 _mintValue = _value / _mintsLength;

            // Decrease the amount we have left to mint with
            _value -= _mintValue;

            // TODO: replace with a proper tierID
            unchecked {
                _tokenId = ++numberOfTokensMinted;
            }

            // Track how much this NFT is worth
            stakingTokenBalance[_tokenId] = _mintValue;

            // Mint the token.
            _mint(_beneficiary, _tokenId);

            unchecked {
                ++_i;
            }
         }
        return _value;
    }

    /**
    @notice
    Transfer voting units after the transfer of a token.

    @param _from The address where the transfer is originating.
    @param _to The address to which the transfer is being made.
    @param _tokenId The ID of the token being transferred.
   */
    function _afterTokenTransfer(
        address _from,
        address _to,
        uint256 _tokenId
    ) internal virtual override {
        uint256 _stakingValue = stakingTokenBalance[_tokenId];

        if (_from != address(0)) userVotingPower[_from] -= _stakingValue;
        if (_to != address(0)) userVotingPower[_to] += _stakingValue;

        // Transfer the voting units.
        _transferVotingUnits(_from, _to, _stakingValue);

        super._afterTokenTransfer(_from, _to, _tokenId);
    }

    /**
     * @notice calculates the combined redemption weight of the given token IDs.
     * @param _tokenIds The IDs of the tokens to get the cumulative redemption weight of.
     */
    function _redemptionWeightOf(
        uint256[] memory _tokenIds
    ) internal view returns (uint256 _weight) {
        uint256 _nOfTokens = _tokenIds.length;
        for (uint256 _i; _i < _nOfTokens; ) {
            unchecked {
                // Add the staked value that the nft represents
                // and increment the loop
                _weight += stakingTokenBalance[_tokenIds[_i++]];
                ++_i;
            }
        }
    }
}
