// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./utils/DSTestFull.sol";

import "../src/JB721StakingDelegate.sol";
import "../src/JB721StakingDelegateDeployer.sol";
import "../src/distributor/JB721StakingDistributor.sol";

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {JBTokenAmount} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBTokenAmount.sol";
import {JBConstants} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBConstants.sol";

contract DelegateTest_Unit is Test {
    using stdStorage for StdStorage;

    error INSUFFICIENT_VALUE();
    error OVERSPENDING();
    error STAKE_NOT_ENOUGH_FOR_TIER(uint16 _tier, uint256 _minAmount, uint256 _providedAmount);
    error TOKEN_LOCKED(uint256 _tokenID, IBPLockManager _manager);

    uint256 _projectId = 103;
    string _baseUri;

    IERC20Metadata internal _stakingToken = IERC20Metadata(_mockContract("staking_token"));
    IJBController _controller = IJBController(_mockContract("jb_controller"));
    IJBDirectory _directory = IJBDirectory(_mockContract("jb_directory"));
    IJBPaymentTerminal _terminal = IJBPaymentTerminal(_mockContract("jb_payment_terminal"));
    IJBSingleTokenPaymentTerminalStore _terminalStore =
        IJBSingleTokenPaymentTerminalStore(_mockContract("jb_terminal_store"));
    IJBSplitsStore _splitStore = IJBSplitsStore(_mockContract("jb_split_store"));
    IJB721TokenUriResolver _resolver = IJB721TokenUriResolver(_mockContract("jb_token_resolver"));
    IJBOperatorStore _operatorStore = IJBOperatorStore(_mockContract("jb_operator_store"));
    IJBProjects _projects = IJBProjects(_mockContract("jb_projects"));
    JBERC20TerminalDeployer _terminalDeployer = JBERC20TerminalDeployer(_mockContract("jb_terminal_deployer"));
    IJBDelegatesRegistry _delegateRegistry = IJBDelegatesRegistry(_mockContract("jb_delegate_registry"));

    JB721StakingDelegateDeployer _deployer;

    function setUp() public {
        // Deploy the deployer
        _deployer = new JB721StakingDelegateDeployer(
            _controller, 
            _directory,
            _projects,
            _operatorStore,
            _terminalStore,
            _splitStore,
            _terminalDeployer,
            _delegateRegistry
        );
    }

    function testDeploy() public {
        _deployer.deployDelegate(
            _projectId, _stakingToken, _resolver, "JBXStake", "STAKE", "", _baseUri, bytes32("0"), 10 ** 18, 59
        );
    }

    function testMint_customStakeAmount(address _payer, uint16 _tierId, uint96 _customAdditionalStakeAmount) public {
        vm.assume(_payer != address(0));

        JB721StakingDelegate _delegate = _deployDelegate();
        uint128 _value = uint128(_validateTierAndGetCost(_delegate, _tierId));

        // Check that we won't overflow if we add the _customAdditionalStakeAmount
        vm.assume(_customAdditionalStakeAmount < type(uint128).max - _value);

        JB721StakingTier[] memory _tiers = new JB721StakingTier[](1);
        _tiers[0] = JB721StakingTier({tierId: _tierId, amount: _value});

        uint256 _numberMintedBefore = _delegate.numberOfTokensMintedOfTier(_tierId);
        uint256 _expectedTokenId = _generateTokenId(_tierId, _numberMintedBefore + 1);

        vm.prank(address(_terminal));
        _delegate.didPay(_buildPayData(_payer, _value, _payer, _tiers));

        // Check that the correct tier was minted
        assertEq(_delegate.numberOfTokensMintedOfTier(_tierId), _numberMintedBefore + 1);

        // Check that the token represents the correct amount
        assertEq(_delegate.stakingTokenBalance(_expectedTokenId), _value);
    }

    function testMint_customStakeAmount_reverts_tierStakeTooSmall(
        address _payer,
        uint16 _tierId,
        uint128 _tierStakeAmount
    ) public {
        vm.assume(_payer != address(0));

        JB721StakingDelegate _delegate = _deployDelegate();

        // Make sure that the amount we are going to send is not enough for the tier
        uint128 _tierCost = uint128(_validateTierAndGetCost(_delegate, _tierId));
        vm.assume(_tierStakeAmount < _tierCost);

        // Here we specify the incorrect amount, this is not enough stake for this tier
        // However in the actual payment we do pay enought to mint this tier
        JB721StakingTier[] memory _tiers = new JB721StakingTier[](1);
        _tiers[0] = JB721StakingTier({tierId: _tierId, amount: _tierStakeAmount});

        vm.expectRevert(
            abi.encodeWithSelector(STAKE_NOT_ENOUGH_FOR_TIER.selector, _tierId, _tierCost, _tierStakeAmount)
        );

        vm.prank(address(_terminal));
        _delegate.didPay(_buildPayData(_payer, _tierCost, _payer, _tiers));
    }

    function testMint_customStakeAmount_reverts_paymentTooSmall(address _payer, uint16 _tierId, uint128 _paymentAmount)
        public
    {
        vm.assume(_payer != address(0));

        JB721StakingDelegate _delegate = _deployDelegate();

        // Make sure that the amount we are going to send is not enough for the tier
        uint128 _tierCost = uint128(_validateTierAndGetCost(_delegate, _tierId));
        _paymentAmount = uint128(bound(_paymentAmount, 0, _tierCost));

        // Here we specify the (correct) expected amount
        // However in the actual payment we do not pay enought to mint this
        JB721StakingTier[] memory _tiers = new JB721StakingTier[](1);
        _tiers[0] = JB721StakingTier({tierId: _tierId, amount: _tierCost});

        vm.expectRevert(INSUFFICIENT_VALUE.selector);

        vm.prank(address(_terminal));
        _delegate.didPay(_buildPayData(_payer, _paymentAmount, _payer, _tiers));
    }

    function testMint_customStakeAmount_reverts_paymentTooBig(address _payer, uint16 _tierId, uint128 _paymentAmount)
        public
    {
        vm.assume(_payer != address(0));

        JB721StakingDelegate _delegate = _deployDelegate();

        uint128 _tierCost = uint128(_validateTierAndGetCost(_delegate, _tierId));
        _paymentAmount = uint128(bound(_paymentAmount, _tierCost + 1, type(uint128).max));

        // Here we specify the (correct) expected amount
        // However in the actual payment we do not pay enought to mint this
        JB721StakingTier[] memory _tiers = new JB721StakingTier[](1);
        _tiers[0] = JB721StakingTier({tierId: _tierId, amount: _tierCost});

        vm.expectRevert(OVERSPENDING.selector);

        vm.prank(address(_terminal));
        _delegate.didPay(_buildPayData(_payer, _paymentAmount, _payer, _tiers));
    }

    function testMint_beneficiaryReceivesVotingPower(
        address _beneficiary,
        uint16 _tierId,
        uint224 _stakingAmount,
        uint224 _votingPowerPreMint
    ) public {
        // Check that we won't overflow the uint224
        vm.assume(type(uint224).max - _votingPowerPreMint > _stakingAmount);
        vm.assume(_beneficiary != address(0));

        // Deploy the delegate
        JB721StakingDelegateHarness _delegate = _deployDelegate();

        // Pre set the voting power
        _addDelegatedVotingPower(_delegate, _beneficiary, _votingPowerPreMint);

        // Delegate to themselves
        vm.prank(_beneficiary);
        _delegate.delegate(_beneficiary);

        // Mint a position for them
        _delegate.ForTest_mintTo(_tierId, _stakingAmount, _beneficiary);

        // Assert the votingPower was added
        assertEq(_delegate.getVotes(_beneficiary), _votingPowerPreMint + _stakingAmount);
    }

    /// This checks that the user themselves does not get the votingPower if their voting power is delegated to some
    /// other address
    function testMint_beneficiaryDoesNotReceiveVotingPowerWhenNotDelegated(
        address _beneficiary,
        uint16 _tierId,
        uint224 _stakingAmount,
        uint224 _votingPowerPreMint,
        address _delegateTo
    ) public {
        // Check that we won't overflow the uint224
        vm.assume(type(uint224).max - _votingPowerPreMint > _stakingAmount);
        // This tests the scenario where these are not the same user
        vm.assume(_delegateTo != _beneficiary);
        // Can't mint an NFT to the zero address
        vm.assume(_beneficiary != address(0));

        // Deploy the delegate
        JB721StakingDelegateHarness _delegate = _deployDelegate();

        // Pre set the voting power
        _addDelegatedVotingPower(_delegate, _beneficiary, _votingPowerPreMint);

        // Delegate to someone else
        if (_delegateTo != address(0)) {
            vm.prank(_beneficiary);
            _delegate.delegate(_delegateTo);
        }

        // Mint a position for them
        _delegate.ForTest_mintTo(_tierId, _stakingAmount, _beneficiary);

        // Assert the votingPower was *not* added
        assertEq(_delegate.getVotes(_beneficiary), _votingPowerPreMint);

        // Assert the votingPower was added to the delegate
        if (_delegateTo != address(0)) {
            assertEq(_delegate.getVotes(_delegateTo), _stakingAmount);
        }
    }

    function testBurn_correctAmountOfTokens_redeemEntireSupply(address _beneficiary, JB721StakingTier[] memory _tiers)
        public
    {
        vm.assume(_tiers.length > 0);
        vm.assume(_beneficiary != address(0));

        // Deploy the delegate
        JB721StakingDelegateHarness _delegate = _deployDelegate();

        uint256[] memory _tokenIDs = new uint256[](_tiers.length);

        uint224 _amountBeforeOverflow = type(uint224).max;
        for (uint256 _i; _i < _tiers.length; _i++) {
            // Make sure if we mint the next tier we stay within the max totalsupply
            vm.assume(_tiers[_i].amount < _amountBeforeOverflow);
            _amountBeforeOverflow -= _tiers[_i].amount;

            // Mint the specified position
            _tokenIDs[_i] = _delegate.ForTest_mintTo(_tiers[_i].tierId, _tiers[_i].amount, _beneficiary);
        }

        uint256 _totalStakeValue = type(uint224).max - _amountBeforeOverflow;

        assertEq(_delegate.totalRedemptionWeight(address(0)), _totalStakeValue);
        assertEq(_delegate.redemptionWeightOf(address(0), _tokenIDs), _totalStakeValue);

        vm.assume(_totalStakeValue > 100 gwei);

        (uint256 _reclaimAmount,,) = _delegate.redeemParams(_buildRedeemData(_beneficiary, _tokenIDs));

        assertEq(_reclaimAmount, _totalStakeValue);
    }

    function testTransfer_transfersVotingUnits(
        address _user,
        address _userDelegate,
        uint224 _userDelegateVotingPowerBefore,
        JB721StakingTier memory _token,
        address _recipient,
        address _recipientDelegate,
        uint224 _recipientDelegateVotingPowerBefore
    ) public {
        // Check that we won't overflow the uint224
        vm.assume(type(uint224).max - _userDelegateVotingPowerBefore > _token.amount);
        vm.assume(type(uint224).max - _recipientDelegateVotingPowerBefore > _token.amount);
        vm.assume(type(uint224).max - _recipientDelegateVotingPowerBefore > _userDelegateVotingPowerBefore);
        vm.assume(
            type(uint224).max - _recipientDelegateVotingPowerBefore - _token.amount > _userDelegateVotingPowerBefore
        );

        // We exclude the scenario where both users delegate to the same address, since that complicates this test
        vm.assume(_userDelegate != _recipientDelegate);
        vm.assume(_user != _recipient && _user != _recipient);

        // Can't mint or transfer to the zero address
        vm.assume(_user != address(0) && _recipient != address(0));

        bool _userVotingPowerIsDelegated = _userDelegate != address(0);
        bool _recipientVotingPowerIsDelegated = _recipientDelegate != address(0);

        // Deploy the delegate
        JB721StakingDelegateHarness _delegate = _deployDelegate();

        // Set the delegates for the user
        vm.prank(_user);
        _delegate.delegate(_userDelegate);

        // Set the delegates for the recipient
        vm.prank(_recipient);
        _delegate.delegate(_recipientDelegate);

        // Give the user and the recipient their starting votingpower
        _addDelegatedVotingPower(_delegate, _userDelegate, _userDelegateVotingPowerBefore);
        _addDelegatedVotingPower(_delegate, _recipientDelegate, _recipientDelegateVotingPowerBefore);

        // Mint the token that is going to be transfered to the recipient
        uint256 _tokenID = _delegate.ForTest_mintTo(_token.tierId, _token.amount, _user);

        // Check that the delegate received the voting power
        // (this is just a sanity check)
        if (_userVotingPowerIsDelegated) {
            assertEq(_delegate.getVotes(_userDelegate), _userDelegateVotingPowerBefore + _token.amount);
        } else {
            // If the user has 'delegated' to the zero address this means that their voting power is inactive,
            // The zero address should never have any voting power
            assertEq(_delegate.getVotes(_userDelegate), 0);
        }

        // Transfer the token to the beneficiary
        vm.prank(_user);
        _delegate.transferFrom(_user, _recipient, _tokenID);

        // Check that the users delegated voting power has decreased
        if (_userVotingPowerIsDelegated) {
            assertEq(_delegate.getVotes(_userDelegate), _userDelegateVotingPowerBefore);
        }

        // And that the recipient delegated voting power has increased
        if (_recipientVotingPowerIsDelegated) {
            assertEq(_delegate.getVotes(_recipientDelegate), _recipientDelegateVotingPowerBefore + _token.amount);
        }
    }

    // This test is intended to check the gas usage of the tier stake lookup
    function testTiers_getCost(uint256 _tierIdSeed) public {
        JB721StakingDelegateHarness _delegate = _deployDelegate();
        uint16 _tierId = uint16(bound(_tierIdSeed, 0, 59));
        _delegate.ForTest_getCost(_tierId);
    }

    // This test is intended to check the gas usage of the tier stake lookup
    function testTiersOf() public {
        JB721StakingDelegateHarness _delegate = _deployDelegate();

        uint256[] memory _categories;
        JB721Tier[] memory _tiers = _delegate.tiersOf(address(0), _categories, false, 15, 63);

        assertEq(_tiers.length, 45);
    }

    function testDistributor() public {
        uint256 _periodDurationBlocks = 100;
        uint256 _vestingDuration = 12;
        uint256 _amountToDistribute = 10 ether;

        TestERC20 _token = new TestERC20();

        JB721StakingDelegateHarness _delegate = _deployDelegate();
        JB721StakingDistributor _distributor =
            new JB721StakingDistributor(_delegate, _periodDurationBlocks, _vestingDuration);

        //
        address _beneficiary = address(0xba5ed);

        // Mint a token
        uint256 _tokenId = _delegate.ForTest_mintTo(1, 100, _beneficiary);

        // Send some tokens to be distributed to the distributor
        _token.ForTest_mintTo(_amountToDistribute, address(_distributor));

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(_token);

        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = _tokenId;

        // You can't claim in the same block that the cycle starts
        vm.roll(block.number + 1);

        // Do a claim with the NFTs on the tokens
        vm.prank(_beneficiary);
        _distributor.beginVesting(nftIds, tokens);

        uint256 _vestedCycle = _distributor.currentRound() + _vestingDuration;

        // Calculate in what block the vesting is done, then forward to thet cycle
        vm.roll(_distributor.roundStartBlock(_vestedCycle));

        // Collect the tokens
        vm.prank(_beneficiary);
        _distributor.collectVestedRewards(nftIds, tokens, _vestedCycle);

        // In this test the user should receive the full amount, since its the only person that holds the tokens
        assertEq(_token.balanceOf(_beneficiary), _amountToDistribute);
    }

    function testLockManager_configure(bool _alreadyHasLockManager) public {
        address _beneficiary = address(0xba5ed);

        // Deploy the delegate
        JB721StakingDelegateHarness _delegate = _deployDelegate();
        MockLockManager _lockManager = new MockLockManager();

        // Mint a token
        uint256 _tokenId = _delegate.ForTest_mintTo(1, 100, _beneficiary);

        // If bool is set we make it so there is already a lockManager set
        if (_alreadyHasLockManager) {
            MockLockManager _oldLockManager = new MockLockManager();
            _delegate.ForTest_setLockManager(_tokenId, _oldLockManager);

            // It should perform a call to see if the token is indeed unlocked
            vm.expectCall(
                address(_oldLockManager), abi.encodeCall(_oldLockManager.isUnlocked, (address(_delegate), _tokenId))
            );
        }

        // Set the lock manager
        vm.prank(_beneficiary);
        _delegate.setLockManager(_tokenId, _lockManager);

        // Check that it updated
        assertEq(address(_delegate.lockManager(_tokenId)), address(_lockManager));

        // TODO: check emit
    }

    function testLockManager_configureLocked_reverts() public {
        address _beneficiary = address(0xba5ed);

        // Deploy the delegate
        JB721StakingDelegateHarness _delegate = _deployDelegate();
        MockLockManager _lockManager = new MockLockManager();
        MockLockManager _newLockManager = new MockLockManager();

        // Mint a token
        uint256 _tokenId = _delegate.ForTest_mintTo(1, 100, _beneficiary);

        // Set the old lockManager and configure it to report as locked
        _delegate.ForTest_setLockManager(_tokenId, _lockManager);
        _lockManager.ForTest_setLocked(_tokenId, true);

        vm.expectRevert(abi.encodeWithSelector(TOKEN_LOCKED.selector, _tokenId, _lockManager));

        // Attempt to change the lockManager
        vm.prank(_beneficiary);
        _delegate.setLockManager(_tokenId, _newLockManager);
    }

    function testLockManager_transferUnlocked(bool _withLockManager) public {
        address _beneficiary = address(0xba5ed);
        address _recipient = address(0x11111);

        // Deploy the delegate
        JB721StakingDelegateHarness _delegate = _deployDelegate();

        // Mint a token
        uint256 _tokenId = _delegate.ForTest_mintTo(1, 100, _beneficiary);

        if (_withLockManager) {
            // Set the lock manager
            MockLockManager _lockManager = new MockLockManager();
            _delegate.ForTest_setLockManager(_tokenId, _lockManager);

            // It should perform a call to see if the token is indeed unlocked
            vm.expectCall(
                address(_lockManager), abi.encodeCall(_lockManager.isUnlocked, (address(_delegate), _tokenId))
            );
        }

        vm.prank(_beneficiary);
        _delegate.transferFrom(_beneficiary, _recipient, _tokenId);

        // Check that the recipient is now the owner
        assertEq(_delegate.ownerOf(_tokenId), _recipient);

        // TODO: check emit
    }

    function testLockManager_transferLocked_reverts() public {
        address _beneficiary = address(0xba5ed);
        address _recipient = address(0x11111);

        // Deploy the delegate
        JB721StakingDelegateHarness _delegate = _deployDelegate();
        MockLockManager _lockManager = new MockLockManager();

        // Mint a token
        uint256 _tokenId = _delegate.ForTest_mintTo(1, 100, _beneficiary);

        // Set the lock manager
        vm.prank(_beneficiary);
        _delegate.setLockManager(_tokenId, _lockManager);

        // Lock the token
        _lockManager.ForTest_setLocked(_tokenId, true);

        vm.expectRevert(abi.encodeWithSelector(TOKEN_LOCKED.selector, _tokenId, _lockManager));

        vm.prank(_beneficiary);
        _delegate.transferFrom(_beneficiary, _recipient, _tokenId);
    }

    function testLockManager_burnUnlocked(bool _withLockManager) public {
        address _beneficiary = address(0xba5ed);

        // Deploy the delegate
        JB721StakingDelegateHarness _delegate = _deployDelegate();

        // Mint a token
        uint256 _tokenId = _delegate.ForTest_mintTo(1, 100, _beneficiary);

        if (_withLockManager) {
            // Set the lock manager
            MockLockManager _lockManager = new MockLockManager();
            _delegate.ForTest_setLockManager(_tokenId, _lockManager);

            // It should perform a onRedeem hook call
            vm.expectCall(address(_lockManager), abi.encodeCall(_lockManager.onRedeem, (_tokenId, _beneficiary)));

            // It should perform a call to see if the token is indeed unlocked
            vm.expectCall(
                address(_lockManager), abi.encodeCall(_lockManager.isUnlocked, (address(_delegate), _tokenId))
            );
        }

        _delegate.ForTest_burn(_tokenId);
    }

    function testLockManager_burnLocked_reverts() public {
        address _beneficiary = address(0xba5ed);

        // Deploy the delegate
        JB721StakingDelegateHarness _delegate = _deployDelegate();

        // Mint a token
        uint256 _tokenId = _delegate.ForTest_mintTo(1, 100, _beneficiary);

        // Set the lock manager
        MockLockManager _lockManager = new MockLockManager();
        _delegate.ForTest_setLockManager(_tokenId, _lockManager);

        // Lock the token
        _lockManager.ForTest_setLocked(_tokenId, true);

        // It should perform a onRedeem hook call
        vm.expectCall(address(_lockManager), abi.encodeCall(_lockManager.onRedeem, (_tokenId, _beneficiary)));

        // It should perform a call to see if the token is indeed unlocked
        vm.expectCall(address(_lockManager), abi.encodeCall(_lockManager.isUnlocked, (address(_delegate), _tokenId)));

        vm.expectRevert(abi.encodeWithSelector(TOKEN_LOCKED.selector, _tokenId, _lockManager));

        _delegate.ForTest_burn(_tokenId);
    }

    //*********************************************************************//
    // ----------------------------- Helpers ----------------------------- //
    //*********************************************************************//

    function _generateTokenId(uint256 _tierId, uint256 _tokenNumber) internal pure returns (uint256) {
        return (_tierId * 1_000_000_000) + _tokenNumber;
    }

    function _validateTierAndGetCost(JB721StakingDelegate _delegate, uint16 _tierId)
        internal
        view
        returns (uint256 _cost)
    {
        // ValidateTier
        uint256 _maxTier = _delegate.maxTierId();
        vm.assume(_tierId <= _maxTier);

        JB721Tier memory _tier = _delegate.tierOf(address(_delegate), _tierId, false);
        return _tier.price;
    }

    function _deployDelegate() internal returns (JB721StakingDelegateHarness _delegate) {
        _delegate = new JB721StakingDelegateHarness(
            _projectId, _stakingToken, _directory, _resolver, "JBXStake", "STAKE", "", _baseUri, bytes32("0"), 10 ** 18, 59
        );

        vm.mockCall(
            address(_directory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, int256(_projectId), address(_terminal)),
            abi.encode(true)
        );
    }

    function _addDelegatedVotingPower(
        JB721StakingDelegateHarness _delegate,
        address _beneficiary,
        uint224 _votingPowerAmount
    ) internal {
        // If the user has 'delegated' to the zero address this means that their voting power is inactive,
        // The zero address should never have any voting power
        if (_beneficiary == address(0)) return;
        uint256 _currentVotes = _delegate.getVotes(_beneficiary);

        // Transfer voting units from the zero address to the user
        _delegate.ForTest_transferVotingUnits(address(0), _beneficiary, _votingPowerAmount);

        // Assert that the voting power was received
        assertEq(
            _delegate.getVotes(_beneficiary),
            _currentVotes + _votingPowerAmount,
            "Beneficiary of delegated tokens did not receive the voting power"
        );
    }

    function _buildPayData(address _payer, uint256 _value, address _beneficiary, JB721StakingTier[] memory _tiers)
        internal
        view
        returns (JBDidPayData memory)
    {
        // (bytes32, bytes32, bytes4, bool, address, JB721StakingTier[])
        bytes memory _metadata = abi.encode(
            bytes32(0),
            bytes32(0),
            type(IJB721StakingDelegate).interfaceId,
            false,
            _beneficiary,
            _tiers,
            address(0),
            bytes("")
        );

        return JBDidPayData({
            payer: _payer,
            projectId: _projectId,
            currentFundingCycleConfiguration: 0,
            amount: JBTokenAmount({token: address(_stakingToken), value: _value, decimals: 18, currency: 0}),
            forwardedAmount: JBTokenAmount({token: address(0), value: 0, decimals: 0, currency: 0}),
            projectTokenCount: 0,
            beneficiary: _beneficiary,
            preferClaimedTokens: false,
            memo: "",
            metadata: _metadata
        });
    }

    function _buildRedeemData(address _redeemer, uint256[] memory _tokenIds)
        internal
        view
        returns (JBRedeemParamsData memory)
    {
        bytes memory _metadata = abi.encode(bytes32(0), type(IJB721Delegate).interfaceId, _tokenIds);

        return JBRedeemParamsData({
            terminal: _terminal,
            holder: _redeemer,
            projectId: _projectId,
            currentFundingCycleConfiguration: 0,
            tokenCount: 0,
            totalSupply: 0,
            overflow: 0,
            reclaimAmount: JBTokenAmount({token: address(0), value: 0, decimals: 0, currency: 0}),
            useTotalOverflow: false,
            redemptionRate: JBConstants.MAX_REDEMPTION_RATE,
            memo: "",
            metadata: _metadata
        });
    }

    function _buildPayData(address _payer, uint256 _value, address _beneficiary, uint16[] memory _tierIds)
        internal
        view
        returns (JBDidPayData memory)
    {
        // (bytes32, bytes32, bytes4, bool, JB721StakingTier[])
        bytes memory _metadata =
            abi.encode(bytes32(0), bytes32(0), type(IJBTiered721Delegate).interfaceId, false, _tierIds);

        return JBDidPayData({
            payer: _payer,
            projectId: _projectId,
            currentFundingCycleConfiguration: 0,
            amount: JBTokenAmount({token: address(_stakingToken), value: _value, decimals: 18, currency: 0}),
            forwardedAmount: JBTokenAmount({token: address(0), value: 0, decimals: 0, currency: 0}),
            projectTokenCount: 0,
            beneficiary: _beneficiary,
            preferClaimedTokens: false,
            memo: "",
            metadata: _metadata
        });
    }

    // Seed for the generation of pseudorandom addresses
    bytes32 private _nextAddressSeed = keccak256(abi.encodePacked("address"));

    /**
     * @dev Creates a new pseudorandom address and labels it with the given label
     * @param _name Name of the label.
     * @return _address The address generated and labeled
     */
    function _label(string memory _name) internal returns (address _address) {
        return _label(_newAddress(), _name);
    }

    /**
     * @dev Labels the given address and returns it
     *
     * @param _addy Address to label.
     * @param _name Name of the label.
     *
     * @return _address The address Labeled address
     */
    function _label(address _addy, string memory _name) internal returns (address _address) {
        vm.label(_addy, _name);
        return _addy;
    }

    /**
     * @dev Creates a mock contract in a pseudorandom address and labels it.
     * @param _name Label for the mock contract.
     * @return _address The address of the mock contract.
     */
    function _mockContract(string memory _name) internal returns (address _address) {
        return _mockContract(_newAddress(), _name);
    }

    /**
     * @dev Creates a mock contract in a specified address and labels it.
     *
     * @param _addy Address for the mock contract.
     * @param _name Label for the mock contract.
     *
     * @return _address The address of the mock contract.
     */
    function _mockContract(address _addy, string memory _name) internal returns (address _address) {
        vm.etch(_addy, new bytes(0x1));
        return _label(_addy, _name);
    }

    /**
     * @dev Creates a pseudorandom address.
     * @return _address The address of the mock contract.
     */
    function _newAddress() internal returns (address _address) {
        address payable _nextAddress = payable(address(uint160(uint256(_nextAddressSeed))));
        _nextAddressSeed = keccak256(abi.encodePacked(_nextAddressSeed));
        _address = _nextAddress;
    }

    function _expectEmitNoIndex() internal {
        vm.expectEmit(false, false, false, true);
    }
}

contract JB721StakingDelegateHarness is JB721StakingDelegate {
    constructor(
        uint256 _projectId,
        IERC20 _stakingToken,
        IJBDirectory _directory,
        IJB721TokenUriResolver _uriResolver,
        string memory _name,
        string memory _symbol,
        string memory _contractURI,
        string memory _baseURI,
        bytes32 _encodedIPFSUri,
        uint256 _tierMultiplier,
        uint8 _maxTier
    )
        JB721StakingDelegate(
            _projectId,
            _stakingToken,
            _directory,
            _uriResolver,
            _name,
            _symbol,
            _contractURI,
            _baseURI,
            _encodedIPFSUri,
            _tierMultiplier,
            _maxTier
        )
    {}

    function ForTest_setLockManager(uint256 _tokenId, IBPLockManager _lockManager) external {
        lockManager[_tokenId] = _lockManager;
    }

    function ForTest_burn(uint256 _tokenId) external {
        _burn(_tokenId);
    }

    function ForTest_mintTo(uint16 _tierId, uint256 _stakingAmountWorth, address _beneficiary)
        external
        returns (uint256 _tokenID)
    {
        return _mintTier(_tierId, _stakingAmountWorth, _beneficiary);
    }

    function ForTest_transferVotingUnits(address _from, address _to, uint224 _amount) external {
        address _fromDelegateBefore = delegates(_from);
        address _toDelegateBefore = delegates(_to);

        // Update the delegate to themselves
        _delegate(_from, _from);
        _delegate(_to, _to);

        // Transfer the voting units
        _transferVotingUnits(_from, _to, _amount);

        // Return the delegates to the original
        _delegate(_from, _fromDelegateBefore);
        _delegate(_to, _toDelegateBefore);
    }

    function ForTest_getCost(uint16 _tierId) external view returns (uint256 _minStake) {
        return _getTierMinStake(_tierId);
    }
}

contract TestERC20 is ERC20 {
    constructor() ERC20("testToken", "TEST") {}

    function ForTest_mintTo(uint256 _amount, address _beneficiary) external {
        _mint(_beneficiary, _amount);
    }
}

contract MockLockManager is IBPLockManager {
    mapping(uint256 _tokenId => bool) internal locked;

    function ForTest_setLocked(uint256 _tokenId, bool _state) external {
        locked[_tokenId] = _state;
    }

    // Interface methods
    function onRegistration(
        address _payer,
        address _beneficiary,
        uint256 _stakingAmount,
        uint256[] memory _tokenIDs,
        bytes calldata _data
    ) external override {}

    function onRedeem(uint256, address) external override {}

    function isUnlocked(address, uint256 _id) external view override returns (bool) {
        return !locked[_id];
    }
}
