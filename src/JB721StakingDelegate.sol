// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {JB721Delegate} from "@jbx-protocol/juice-721-delegate/contracts/abstract/JB721Delegate.sol";
import {JBIpfsDecoder} from "@jbx-protocol/juice-721-delegate/contracts/libraries/JBIpfsDecoder.sol";
import {Votes} from "@jbx-protocol/juice-721-delegate/contracts/abstract/Votes.sol";
import {JB721StakingTier} from "./struct/JB721StakingTier.sol";
import {JB721Tier} from "@jbx-protocol/juice-721-delegate/contracts/structs/JB721Tier.sol";
import {JBRedeemParamsData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedeemParamsData.sol";
import {JBDidPayData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBDidPayData.sol";
import {JBRedemptionDelegateAllocation} from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedemptionDelegateAllocation.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IBPLockManager} from "./interfaces/IBPLockManager.sol";
import {JBTiered721Flags} from "@jbx-protocol/juice-721-delegate/contracts/structs/JBTiered721Flags.sol";
import {IJBDirectory} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import {IJB721StakingDelegate} from "./interfaces/IJB721StakingDelegate.sol";
import {IJBTiered721MinimalDelegate} from "./interfaces/IJBTiered721MinimalDelegate.sol";
import {IJBTiered721MinimalDelegateStore} from "./interfaces/IJBTiered721MinimalDelegateStore.sol";
import {
    IJBTiered721Delegate,
    IJB721Delegate
} from "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721Delegate.sol";
import {IJB721TokenUriResolver} from "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJB721TokenUriResolver.sol";

/// @notice A contract that issues and redeems NFTs that represent locked token positions.
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

    error INVALID_PAYMENT_METADATA();
    error DELEGATION_NOT_ALLOWED();
    error INVALID_TOKEN();
    error INVALID_TIER();
    error INVALID_MAX_TIER();
    error STAKE_NOT_ENOUGH_FOR_TIER(uint16 _tier, uint256 _minAmount, uint256 _providedAmount);
    error INSUFFICIENT_VALUE();
    error OVERSPENDING();
    error TOKEN_LOCKED(uint256 _tokenID, IBPLockManager _manager);

    //*********************************************************************//
    // -------------------- private constant properties ------------------ //
    //*********************************************************************//

    uint256 private constant _ONE_BILLION = 1_000_000_000;

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The address of the singleton 'JB721StakingDelegate'.
    address public immutable codeOrigin;

    /// @notice The staking token for this delegate, this is the only token that is accepted as payments.
    IERC20 public immutable stakingToken;

    /// @notice The contract that contains the 721's rendering and contextual data.
    IJB721TokenUriResolver public immutable uriResolver;

    /// @notice Encoded URI to be used when no token resolver is provided.
    bytes32 public immutable encodedIPFSUri;

    /// @notice The max tier ID that is allowed (up to a limit of 59)
    uint256 public immutable maxTierId;

    /// @notice The multiplier applied to minimum staking thresholds for each tier ID.
    /// @dev This is useful to tune the staking mechanism to various expected token supplies. Some networks issue 1
    /// $TOKEN per 1 ETH received, others 1 million $TOKENs per ETH received, etc.
    uint256 public immutable tierMultiplier;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice A URI containing metadata for this 721.
    string public override contractURI;

    /// @notice The common base for the encoded IPFS URI.
    string public baseURI;

    /// @notice The staked token balances represented by each 721 ID.
    /// @custom:param tokenId The ID of the 721 that represents the given staked balance.
    mapping(uint256 _tokenId => uint256) public stakingTokenBalance;

    /// @notice The lock manager for each 721 ID.
    /// @custom:param The ID of the 721 that uses the given lock manager.
    mapping(uint256 _tokenId => IBPLockManager) public lockManager;

    /// @notice The voting power of each user.
    /// @custom:param The amount of voting power for the given account.
    mapping(address _account => uint256) public userVotingPower;

    /// @notice The number of tokens minted within each tier.
    /// @custom:param The ID of the tier to get the mint count of.
    mapping(uint256 _tierId => uint256) public numberOfTokensMintedOfTier;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice Returns information for a specific tier.
    /// @param _id The ID of the tier to get.
    /// @param _includeResolvedUri A flag indicating if the URI should be resolved within the returned tier.
    /// @return tier The tier.
    function tierOf(address, uint256 _id, bool _includeResolvedUri) public view returns (JB721Tier memory tier) {
        // Keep a reference to the minimum amount that must be staked to mint the from the tier.
        uint256 _price = _getTierMinStake(uint16(_id));

        return JB721Tier({
            id: _id,
            price: _price,
            remainingQuantity: _ONE_BILLION - numberOfTokensMintedOfTier[_id],
            initialQuantity: _ONE_BILLION,
            votingUnits: _price,
            reservedRate: 0,
            reservedTokenBeneficiary: address(0),
            encodedIPFSUri: encodedIPFSUri,
            category: 0,
            allowManualMint: false,
            transfersPausable: false,
            resolvedUri: _includeResolvedUri ? tokenURI(_id) : ""
        });
    }

    /// @notice Returns an array of tiers.
    /// @param _includeResolvedUri A flag indicating if the URIs should be resolved within the returned tiers.
    /// @param _startingId The ID of the tier to begin returning from. Tiers are sorted by contribution floor. Send 0 to
    /// get all active tiers.
    /// @param _size The number of tiers to include.
    /// @return tiers An array of active tiers.
    function tiersOf(address, uint256[] calldata, bool _includeResolvedUri, uint256 _startingId, uint256 _size)
        external
        view
        override
        returns (JB721Tier[] memory tiers)
    {
        // Check up to what tierId we are going to be loading
        uint256 _upToTier = _startingId + _size;

        // Cap at the last tier
        if (_upToTier > maxTierId + 1) _upToTier = maxTierId + 1;

        // Initialize an array with the appropriate length.
        tiers = new JB721Tier[](_upToTier - _startingId);

        // Iterate through all tiers.
        for (uint256 _i; _i < _upToTier - _startingId;) {
            // Return the tier.
            tiers[_i] = tierOf(address(0), _startingId + _i, _includeResolvedUri);

            unchecked {
                ++_i;
            }
        }
    }

    /// @notice The store for this delegate.
    /// @dev To save gas and simplify the contract this address is both the delegate and the store.
    function store() external view override returns (address) {
        // We store everything at this contract to save some gas on the calls.
        return address(this);
    }

    /// @notice Flags for the delegate.
    function flagsOf(address) external pure returns (JBTiered721Flags memory) {
        return JBTiered721Flags({
            lockReservedTokenChanges: true,
            lockVotingUnitChanges: true,
            lockManualMintingChanges: true,
            preventOverspending: true
        });
    }

    /// @notice Calculate the redeem value for a set of token IDs.
    /// @param _tokenIds The IDs of the tokens to calculate a redeem value for.
    /// @return weight The redemption weight of the set of tokens.
    function redemptionWeightOf(address, uint256[] memory _tokenIds) external view returns (uint256 weight) {
        return _redemptionWeightOf(_tokenIds);
    }

    /// @notice The sum of all redemptions.
    /// @return weight The total weight.
    function totalRedemptionWeight(address) external view returns (uint256 weight) {
        return _getTotalSupply();
    }

    /// @notice Check if a spender has access to manage a token.
    function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool) {
        return _isApprovedOrOwner(_spender, _tokenId);
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice Calculate the redeem value for a set of token IDs.
    /// @param _tokenIds The IDs of the tokens to calculate a redeem value for.
    /// @return weight The redemption weight of the set of tokens.
    function redemptionWeightOf(uint256[] memory _tokenIds, JBRedeemParamsData calldata)
        public
        view
        virtual
        override
        returns (uint256 weight)
    {
        return _redemptionWeightOf(_tokenIds);
    }

    /// @notice The sum of all redemptions.
    /// @return weight The total weight.
    function totalRedemptionWeight(JBRedeemParamsData calldata) public view virtual override returns (uint256) {
        return _getTotalSupply();
    }

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param _interfaceId The ID of the interface to check for adherence to.
    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return _interfaceId == type(IJB721StakingDelegate).interfaceId || _interfaceId == type(IERC2981).interfaceId
            || super.supportsInterface(_interfaceId);
    }

    /// @notice The metadata URI of the provided token ID.
    /// @dev Defer to the tokenUriResolver if set, otherwise, use the tokenUri set with the token's tier.
    /// @param _tokenId The ID of the token to get the tier URI for.
    /// @return The token URI corresponding with the tier or the tokenUriResolver URI.
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        // If a token URI resolver is provided, use it to resolve the token URI.
        if (address(uriResolver) != address(0)) return uriResolver.tokenUriOf(address(this), _tokenId);

        // Return the token URI for the token's tier.
        return JBIpfsDecoder.decode(baseURI, encodedIPFSUri);
    }

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    constructor(
        uint256 _projectId,
        IERC20 _stakingToken,
        IJBDirectory _directory,
        IJB721TokenUriResolver _uriResolver,
        string memory _name,
        string memory _symbol,
        string memory _contractUri,
        string memory _baseUri,
        bytes32 _encodedIPFSUri,
        uint256 _tierMultiplier,
        uint8 _maxTierId
    ) {
        if (projectId != 0) revert();
        if (_maxTierId > 59) revert INVALID_MAX_TIER();

        stakingToken = _stakingToken;
        uriResolver = _uriResolver;
        contractURI = _contractUri;
        encodedIPFSUri = _encodedIPFSUri;
        baseURI = _baseUri;
        maxTierId = _maxTierId;
        tierMultiplier = _tierMultiplier;

        // Initialize the superclass.
        JB721Delegate._initialize(_projectId, _directory, _name, _symbol);
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Sets the lock manager for a token.
    /// @dev Only the owner of a token or an approved operator can set a new lock manager.
    /// @param _tokenId The ID of the token to set the lock manager of.
    /// @param _newLockManager The new lock manager to set.
    function setLockManager(uint256 _tokenId, IBPLockManager _newLockManager) external {
        // Make sure the sender is allowed to perform this action
        if (!_isApprovedOrOwner(msg.sender, _tokenId)) revert UNAUTHORIZED_TOKEN(_tokenId);

        // Get the lock manager for this token ID.
        IBPLockManager _lockManager = lockManager[_tokenId];

        // If there is already a lockManager set, check to see if the token is unlocked
        if (
            address(_lockManager) != address(0) && address(_lockManager).code.length != 0
                && !_lockManager.isUnlocked(address(this), _tokenId)
        ) revert TOKEN_LOCKED(_tokenId, _lockManager);

        // Set the new lock manager.
        lockManager[_tokenId] = _newLockManager;

        // TODO: emit event?
        // ANSWER: yes.
    }

    //*********************************************************************//
    // ------------------------ internal functions ----------------------- //
    //*********************************************************************//

    /// @notice The voting units for an account across all tiers. 721s in a tier have a specific preset number of voting
    /// units.
    /// @param _account The account to get voting units for.
    /// @return units The voting units for the account.
    function _getVotingUnits(address _account) internal view virtual override returns (uint256 units) {
        return userVotingPower[_account];
    }

    /// @notice Process a received payment.
    /// @param _data The Juicebox standard project payment data.
    function _processPayment(JBDidPayData calldata _data) internal virtual override {
        // Only payment in the staking token is allowed.
        if (IERC20(_data.amount.token) != stakingToken) revert INVALID_TOKEN();

        // Keep a reference to the leftover amount.
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

                // Keep a reference to the lock manager to use.
                IBPLockManager _lockManager;

                // Keep a reference to the lock manager data to register the lock manager with.
                bytes memory _lockManagerData;

                // Decode the metadata.
                (,,,, _votingDelegate, _tierIdsToMint, _lockManager, _lockManagerData) = abi.decode(
                    _data.metadata, (bytes32, bytes32, bytes4, bool, address, JB721StakingTier[], IBPLockManager, bytes)
                );

                // Only allow delegation if the payer is the beneficiary.
                if (_votingDelegate != address(0) && _data.payer != _data.beneficiary) revert DELEGATION_NOT_ALLOWED();

                // Mint the specified tiers with the custom stake amount
                uint256[] memory _tokenIds;

                // Mint 721 positions for the staked amount.
                (_leftoverAmount, _tokenIds) =
                    _mintTiers(_leftoverAmount, _tierIdsToMint, _data.beneficiary, _votingDelegate, _lockManager);

                // Register the lock manager if needed.
                if (address(_lockManager) != address(0)) {
                    _lockManager.onRegistration(
                        _data.payer, _data.beneficiary, _data.amount.value, _tokenIds, _lockManagerData
                    );
                }
            } else {
                revert INVALID_PAYMENT_METADATA();
            }
        } else {
            revert INVALID_PAYMENT_METADATA();
        }

        // All paid tokens must be staked.
        if (_leftoverAmount != 0) revert OVERSPENDING();
    }

    /// @notice Part of IJBFundingCycleDataSource, this function gets called when a project's token holders redeem.
    /// @param _data The Juicebox standard project redemption data.
    /// @return reclaimAmount The amount that should be reclaimed from the treasury.
    /// @return memo The memo that should be forwarded to the event.
    /// @return delegateAllocations The amount to send to delegates instead of adding to the beneficiary.
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

        // Return the redemption weight of all the tokens.
        return (redemptionWeightOf(_decodedTokenIds, _data), _data.memo, delegateAllocations);
    }

    /// @notice Mint tiers.
    /// @param _value The full amount being staked.
    /// @param _tiers The tiers and stake amount to be minted.
    /// @param _beneficiary The address that should receive the minted 721s.
    /// @param _votingDelegate The address that should be delegated votes from the mint.
    /// @return leftoverAmount The amount that is left over after the tiers were minted.
    function _mintTiers(
        uint256 _value,
        JB721StakingTier[] memory _tiers,
        address _beneficiary,
        address _votingDelegate,
        IBPLockManager _lockManager
    ) internal returns (uint256 leftoverAmount, uint256[] memory tokenIds) {
        // Keep a reference to the leftover amount.
        leftoverAmount = _value;

        // Keep a reference to the number of tiers being minted.
        uint256 _numberOfTiers = _tiers.length;

        // Initialize the token ID array to the same number of entries as the number of tiers.
        tokenIds = new uint256[](_numberOfTiers);

        // Mint from each tier.
        for (uint256 _i; _i < _numberOfTiers;) {
            // Get a reference to the minimum amount required to mint from the tier.
            uint256 _tierMinAmount = _getTierMinStake(_tiers[_i].tierId);

            // Make sure the minimum amount is being staked.
            if (_tiers[_i].amount < _tierMinAmount) {
                revert STAKE_NOT_ENOUGH_FOR_TIER(_tiers[_i].tierId, _tierMinAmount, _tiers[_i].amount);
            }

            // Make sure there's enough leftover to mint.
            if (leftoverAmount < _tiers[_i].amount) {
                revert INSUFFICIENT_VALUE();
            }

            // Decrement the leftover amount.
            unchecked {
                leftoverAmount -= _tiers[_i].amount;
            }

            // Mint the token.
            tokenIds[_i] = _mintTier(_tiers[_i].tierId, _tiers[_i].amount, _beneficiary);

            // Set the lock manager for the mint.
            lockManager[tokenIds[_i]] = _lockManager;

            unchecked {
                ++_i;
            }
        }

        // Delegate the staked amount if needed.
        if (_votingDelegate != address(0)) _delegate(_beneficiary, _votingDelegate);
    }

    /// @notice Mint from a tier.
    /// @param _tierId The tier ID to mint from.
    /// @param _stakeAmount The amount that is being staked.
    /// @param _beneficiary The address that is the beneficiary of the mint.
    /// @return tokenId the id of the token that was minted
    function _mintTier(uint16 _tierId, uint256 _stakeAmount, address _beneficiary) internal returns (uint256 tokenId) {
        // Generate the token ID.
        unchecked {
            tokenId = _generateTokenId(_tierId, ++numberOfTokensMintedOfTier[_tierId]);
        }

        // Track how much the minted token is backed by.
        stakingTokenBalance[tokenId] = _stakeAmount;

        // Mint the token.
        _mint(_beneficiary, tokenId);
    }

    /// @notice Get the minimum required stake for the tier ID.
    /// @dev Reverts if the tier ID does not exist
    /// @param _tierId The ID of the tier to get the minimum stake for.
    /// @return The minimum required stake.
    function _getTierMinStake(uint16 _tierId) internal view returns (uint256) {
        return _getTierBaseAmount(_tierId) * tierMultiplier;
    }

    /// @notice Get the base minimum amount for each tier.
    /// @param _tierId The ID of the tier to get the minimum amount for.
    /// @return The minimum token amount for the tier.
    function _getTierBaseAmount(uint256 _tierId) internal view returns (uint256) {
        // Make sure the tier exists.
        if (_tierId > maxTierId) revert INVALID_TIER();

        // To make it easier to compare these tiers to the doc we increase the tier by 1
        unchecked {
            _tierId = _tierId + 1;
        }

        // 1-10
        if (_tierId <= 10) {
            if (_tierId == 1) {
                return 1;
            }
            return _tierId * 100 - 100;
        }
        // 11-20
        if (_tierId <= 20) return (_tierId - 10) * 1000;
        // 20-30
        if (_tierId <= 30) return (_tierId - 20) * 2000 + 10_000;
        // 30-37
        if (_tierId <= 37) return (_tierId - 27) * 10_000;
        // 37-46
        if (_tierId <= 46) return (_tierId - 36) * 100_000;
        // 46-55
        if (_tierId <= 55) return (_tierId - 45) * 1_000_000;
        // 56-58
        if (_tierId <= 58) return (_tierId - 55) * 10_000_000;
        // 59
        if (_tierId == 59) return 100_000_000;
        // 60
        if (_tierId == 60) return 600_000_000;

        // Not found so revert.
        revert();
    }

    /// @notice Finds the token ID given a tier ID and a token number within that tier.
    /// @param _tierId The ID of the tier to generate an ID for.
    /// @param _tokenNumber The number of the token in the tier.
    /// @return The ID of the token.
    function _generateTokenId(uint256 _tierId, uint256 _tokenNumber) internal pure returns (uint256) {
        return (_tierId * _ONE_BILLION) + _tokenNumber;
    }

    /// @notice The tier ID of the provided token ID.
    /// @dev Tiers are 1-indexed from the `tiers` array, meaning the 0th element of the array is tier 1.
    /// @param _tokenId The token ID to get the tier ID of.
    /// @return The tier ID for the provided token ID.
    function tierIdOfToken(uint256 _tokenId) public pure returns (uint256) {
        return _tokenId / _ONE_BILLION;
    }

    /// @notice Hook to prevent locked tokens from being transferred.
    /// @param _from The address to transfer the token from.
    /// @param _to The address to transfer the token to.
    /// @param _tokenId The ID of the token being transferred.
    function _beforeTokenTransfer(address _from, address _to, uint256 _tokenId) internal virtual override {
        // Allow mints.
        if (_from == address(0)) return;

        // Get the lock manager for this token ID.
        IBPLockManager _lockManager = lockManager[_tokenId];

        // Allow transfers if there is no lock manager.
        if (address(_lockManager) == address(0)) return;

        // NOTICE: unsafe call
        // Alert that a redeem is being attempted if the token is being transferred to the zero address.
        if (_to == address(0)) _lockManager.onRedeem(_tokenId, _from);

        // NOTICE: unsafe call
        // Make sure the token is unlocked before allowing it to move.
        if (!_lockManager.isUnlocked(address(this), _tokenId)) revert TOKEN_LOCKED(_tokenId, _lockManager);

        // Delete the lock manager for the receiver since this token now (probably) belongs to some other user.
        delete lockManager[_tokenId];
    }

    /// @notice Transfer voting units after the transfer of a token.
    /// @param _from The address where the transfer is originating.
    /// @param _to The address to which the transfer is being made.
    /// @param _tokenId The ID of the token being transferred.
    function _afterTokenTransfer(address _from, address _to, uint256 _tokenId) internal virtual override {
        // Keep a reference to the staking value of the 721.
        uint256 _stakingValue = stakingTokenBalance[_tokenId];

        // Reduce voting power from the sending address.
        if (_from != address(0)) userVotingPower[_from] -= _stakingValue;

        // Add voting power to the receiving address.
        if (_to != address(0)) userVotingPower[_to] += _stakingValue;

        // Transfer the voting units.
        _transferVotingUnits(_from, _to, _stakingValue);

        super._afterTokenTransfer(_from, _to, _tokenId);
    }

    /// @notice Calculates the combined redemption weight of the given token IDs.
    /// @param _tokenIds The IDs of the tokens to get the cumulative redemption weight of.
    /// @return weight The redemption weight of all the token IDs.
    function _redemptionWeightOf(uint256[] memory _tokenIds) internal view returns (uint256 weight) {
        // Keep a reference to the number of tokens.
        uint256 _numberOfTokens = _tokenIds.length;

        for (uint256 _i; _i < _numberOfTokens;) {
            unchecked {
                // Add the staked value that the nft represents and increment the loop.
                weight += stakingTokenBalance[_tokenIds[_i++]];
            }
        }
    }
}
