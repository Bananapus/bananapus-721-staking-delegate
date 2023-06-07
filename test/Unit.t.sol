// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./utils/DSTestFull.sol";

import "../src/JB721StakingDelegate.sol";
import "../src/JB721StakingDelegateDeployer.sol";

contract DelegateTest_Unit is DSTestFull {
    error INSUFFICIENT_VALUE();
    error OVERSPENDING();
    error STAKE_NOT_ENOUGH_FOR_TIER(uint16 _tier, uint256 _minAmount, uint256 _providedAmount);

    uint256 _projectId = 103;

    IERC20 internal _stakingToken = IERC20(_mockContract("staking_token"));
    IJBDirectory _directory = IJBDirectory(_mockContract("jb_directory"));
    IJBPaymentTerminal _terminal = IJBPaymentTerminal(_mockContract("jb_payment_terminal"));
    IJBTokenUriResolver _resolver = IJBTokenUriResolver(_mockContract("jb_token_resolver"));

    JB721StakingDelegateDeployer _deployer;

    function setUp() public {
        // Deploy the delegate
        JB721StakingDelegate _delegateImplementation = new JB721StakingDelegateHarness();

        // Deploy the deployer
        _deployer = new JB721StakingDelegateDeployer(_delegateImplementation);
    }

    function testDeploy() public {
        _deployer.deploy(_projectId, _stakingToken, _directory, _resolver, "JBXStake", "STAKE", "", "", bytes32("0"));
    }

    function testMint_customStakeAmount(
        address _payer,
        address _beneficiary,
        uint16 _tierId,
        uint96 _customAdditionalStakeAmount
    ) public {
        vm.assume(_beneficiary != address(0));
        vm.assume(_customAdditionalStakeAmount < type(uint128).max - 100 ether);

        uint128 _value = 100 ether + uint128(_customAdditionalStakeAmount);
        JB721StakingDelegate _delegate = _deployDelegate();

        JB721StakingTier[] memory _tiers = new JB721StakingTier[](1);
        _tiers[0] = JB721StakingTier({tierId: _tierId, amount: _value});

        uint256 _numberMintedBefore = _delegate.numberOfTokensMintedOfTier(_tierId);
        uint256 _expectedTokenId = _generateTokenId(_tierId, _numberMintedBefore + 1);

        vm.prank(address(_terminal));
        _delegate.didPay(_buildPayData(_payer, _value, _beneficiary, _tiers));

        // Check that the correct tier was minted
        assertEq(_delegate.numberOfTokensMintedOfTier(_tierId), _numberMintedBefore + 1);

        // Check that the token represents the correct amount
        assertEq(_delegate.stakingTokenBalance(_expectedTokenId), _value);
    }

     function testMint_customStakeAmount_reverts_tierStakeTooSmall(address _payer, address _beneficiary, uint16 _tierId, uint128 _tierStakeAmount) public {
        uint128 _tierCost = 100 ether;

        vm.assume(_tierStakeAmount < _tierCost);
        vm.assume(_beneficiary != address(0));
        
        JB721StakingDelegate _delegate = _deployDelegate();

        // Here we specify the incorrect amount, this is not enough stake for this tier
        // However in the actual payment we do pay enought to mint this tier
        JB721StakingTier[] memory _tiers = new JB721StakingTier[](1);
        _tiers[0] = JB721StakingTier({tierId: _tierId, amount: _tierStakeAmount});

        vm.expectRevert(abi.encodeWithSelector(STAKE_NOT_ENOUGH_FOR_TIER.selector, _tierId, _tierCost, _tierStakeAmount));

        vm.prank(address(_terminal));
        _delegate.didPay(_buildPayData(_payer, _tierCost, _beneficiary, _tiers));
    }

    function testMint_customStakeAmount_reverts_paymentTooSmall(address _payer, address _beneficiary, uint16 _tierId, uint128 _paymentAmount) public {
        uint128 _tierCost = 100 ether;

        vm.assume(_paymentAmount < _tierCost);
        vm.assume(_beneficiary != address(0));
        
        JB721StakingDelegate _delegate = _deployDelegate();

        // Here we specify the (correct) expected amount
        // However in the actual payment we do not pay enought to mint this
        JB721StakingTier[] memory _tiers = new JB721StakingTier[](1);
        _tiers[0] = JB721StakingTier({tierId: _tierId, amount: _tierCost});

        vm.expectRevert(INSUFFICIENT_VALUE.selector);

        vm.prank(address(_terminal));
        _delegate.didPay(_buildPayData(_payer, _paymentAmount, _beneficiary, _tiers));
    }


    function testMint_customStakeAmount_reverts_paymentTooBig(address _payer, address _beneficiary, uint16 _tierId, uint128 _paymentAmount) public {
        uint128 _tierCost = 100 ether;

        vm.assume(_paymentAmount > _tierCost);
        vm.assume(_beneficiary != address(0));
        
        JB721StakingDelegate _delegate = _deployDelegate();

        // Here we specify the (correct) expected amount
        // However in the actual payment we do not pay enought to mint this
        JB721StakingTier[] memory _tiers = new JB721StakingTier[](1);
        _tiers[0] = JB721StakingTier({tierId: _tierId, amount: _tierCost});

        vm.expectRevert(OVERSPENDING.selector);

        vm.prank(address(_terminal));
        _delegate.didPay(_buildPayData(_payer, _paymentAmount, _beneficiary, _tiers));
    }

    function testMint_defaultStakeAmount(address _payer, address _beneficiary, uint16 _tierId) public {
        vm.assume(_beneficiary != address(0));

        uint128 _value = 100 ether;
        JB721StakingDelegate _delegate = _deployDelegate();

        uint16[] memory _tierIds = new uint16[](1);
        _tierIds[0] = _tierId;

        uint256 _numberMintedBefore = _delegate.numberOfTokensMintedOfTier(_tierId);
        uint256 _expectedTokenId = _generateTokenId(_tierId, _numberMintedBefore + 1);

        vm.prank(address(_terminal));
        _delegate.didPay(_buildPayData(_payer, _value, _beneficiary, _tierIds));

        // Check that the correct tier was minted
        assertEq(_delegate.numberOfTokensMintedOfTier(_tierId), _numberMintedBefore + 1);

        // Check that the token represents the correct amount
        assertEq(_delegate.stakingTokenBalance(_expectedTokenId), _value);
    }

    function testMint_defaultStakeAmount_reverts_paymentTooSmall(address _payer, address _beneficiary, uint16 _tierId, uint224 _paymentAmount) public {
        uint128 _tierCost = 100 ether;

        vm.assume(_paymentAmount < _tierCost);
        vm.assume(_beneficiary != address(0));
        
        JB721StakingDelegate _delegate = _deployDelegate();

        uint16[] memory _tierIds = new uint16[](1);
        _tierIds[0] = _tierId;

        vm.expectRevert(INSUFFICIENT_VALUE.selector);

        vm.prank(address(_terminal));
        _delegate.didPay(_buildPayData(_payer, _paymentAmount, _beneficiary, _tierIds));
    }

    function testMint_defaultStakeAmount_reverts_paymentTooBig(address _payer, address _beneficiary, uint16 _tierId, uint224 _paymentAmount) public {
        uint128 _tierCost = 100 ether;

        vm.assume(_paymentAmount > _tierCost);
        vm.assume(_beneficiary != address(0));
        
        JB721StakingDelegate _delegate = _deployDelegate();

        uint16[] memory _tierIds = new uint16[](1);
        _tierIds[0] = _tierId;

        vm.expectRevert(OVERSPENDING.selector);

        vm.prank(address(_terminal));
        _delegate.didPay(_buildPayData(_payer, _paymentAmount, _beneficiary, _tierIds));
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
        if(_userVotingPowerIsDelegated){
            assertEq(
                _delegate.getVotes(_userDelegate),
                _userDelegateVotingPowerBefore + _token.amount
            );
        }else{
            // If the user has 'delegated' to the zero address this means that their voting power is inactive,
            // The zero address should never have any voting power
            assertEq(
                _delegate.getVotes(_userDelegate),
                0
            );
        }
        
        // Transfer the token to the beneficiary
        vm.prank(_user);
        _delegate.transferFrom(_user, _recipient, _tokenID);

        // Check that the users delegated voting power has decreased
        if(_userVotingPowerIsDelegated){
            assertEq(
                _delegate.getVotes(_userDelegate),
                _userDelegateVotingPowerBefore
            );
        }

        // And that the recipient delegated voting power has increased
        if(_recipientVotingPowerIsDelegated){
            assertEq(
                _delegate.getVotes(_recipientDelegate),
                _recipientDelegateVotingPowerBefore + _token.amount
            );
        }
    }

    //*********************************************************************//
    // ----------------------------- Helpers ----------------------------- //
    //*********************************************************************//

    function _generateTokenId(uint256 _tierId, uint256 _tokenNumber) internal pure returns (uint256) {
        return (_tierId * 1_000_000_000) + _tokenNumber;
    }

    function _deployDelegate() internal returns (JB721StakingDelegateHarness _delegate) {
        _delegate = JB721StakingDelegateHarness(
            address(
                _deployer.deploy(
                    _projectId, _stakingToken, _directory, _resolver, "JBXStake", "STAKE", "", "", bytes32("0")
                )
            )
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
        // Get a new random address that will delegate to the beneficiary
        address _delegatee = _newAddress();

        vm.prank(_delegatee);
        _delegate.delegate(_beneficiary);

        uint256 _votingPowerBefore = _delegate.getVotes(_beneficiary);

        _delegate.ForTest_mintTo(type(uint16).max, _votingPowerAmount, _delegatee);

        // If the user has 'delegated' to the zero address this means that their voting power is inactive,
        // The zero address should never have any voting power
        if (_beneficiary == address(0)) return;

        // Assert that the voting power was received
        assertEq(
            _delegate.getVotes(_beneficiary),
            _votingPowerAmount + _votingPowerBefore,
            "Beneficiary of delegated tokens did not receive the voting power"
        );
    }

    function _buildPayData(address _payer, uint256 _value, address _beneficiary, JB721StakingTier[] memory _tiers)
        internal
        view
        returns (JBDidPayData memory)
    {
        // (bytes32, bytes32, bytes4, bool, address, JB721StakingTier[])
        bytes memory _metadata =
            abi.encode(bytes32(0), bytes32(0), type(IJB721StakingDelegate).interfaceId, false, _beneficiary, _tiers);

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
        // (bytes32, bytes32, bytes4, bool, address, JB721StakingTier[])
        bytes memory _metadata =
            abi.encode(bytes32(0), bytes32(0), type(IJBTiered721Delegate).interfaceId, false, _beneficiary, _tierIds);

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
}

contract JB721StakingDelegateHarness is JB721StakingDelegate {
    function ForTest_mintTo(uint16 _tierId, uint256 _stakingAmountWorth, address _beneficiary)
        external
        returns (uint256 _tokenID)
    {
        return _mintTier(_tierId, _stakingAmountWorth, _beneficiary);
    }
}
