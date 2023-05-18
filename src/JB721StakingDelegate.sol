// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBTokenUriResolver.sol";
import "@jbx-protocol/juice-721-delegate/contracts/abstract/JB721Delegate.sol";
import "@jbx-protocol/juice-721-delegate/contracts/libraries/JBIpfsDecoder.sol";
import "@jbx-protocol/juice-721-delegate/contracts/abstract/Votes.sol";
import "./interfaces/IJB721StakingDelegate.sol";

contract JB721StakingDelegate is Votes, JB721Delegate, IJB721StakingDelegate {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//
    error INVALID_TOKEN();

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
    string public contractURI;

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
        uint256 _nOfTokens = _tokenIds.length;
        for (uint256 _i; _i < _nOfTokens; ) {
            unchecked {
                // Add the staked value that the nft represents
                // and increment the loop
                _value += stakingTokenBalance[_tokenIds[_i++]];
                ++ _i;
            }
        }
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
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        // If a token URI resolver is provided, use it to resolve the token URI.
        if (address(uriResolver) != address(0)) return uriResolver.getUri(_tokenId);

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
        uint256 _tokenId;

        // Increment the counter (which also reports the total number minted)
        unchecked {
            _tokenId = ++numberOfTokensMinted;
        }

        // Track how much this NFT is worth
        stakingTokenBalance[_tokenId] = _data.amount.value;

        // TODO: Add tokenUri stuff

        // Mint the token.
        _mint(_data.beneficiary, _tokenId);
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
}
