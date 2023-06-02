// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./utils/DSTestFull.sol";

import "../src/JB721StakingDelegate.sol";
import "../src/JB721StakingDelegateDeployer.sol";

contract DelegateTest_Unit is DSTestFull {
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
        assertEq(
            _delegate.getVotes(_beneficiary),
            _votingPowerPreMint + _stakingAmount
        );
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
        assertEq(
            _delegate.getVotes(_beneficiary),
            _votingPowerPreMint
        );

        // Assert the votingPower was added to the delegate
        if (_delegateTo != address(0)) {
            assertEq(
                _delegate.getVotes(_delegateTo),
                _stakingAmount
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
        _delegate = JB721StakingDelegateHarness(address(_deployer.deploy(
            _projectId, _stakingToken, _directory, _resolver, "JBXStake", "STAKE", "", "", bytes32("0")
        )));

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

        _delegate.ForTest_mintTo(
            type(uint16).max,
            _votingPowerAmount,
            _delegatee
        );

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
        // (bytes32, bytes32, bytes4, bool, JB721StakingTier[])
        bytes memory _metadata =
            abi.encode(bytes32(0), bytes32(0), type(IJB721StakingDelegate).interfaceId, false, _tiers);

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
}


contract JB721StakingDelegateHarness is JB721StakingDelegate {
    function ForTest_mintTo(uint16 _tierId, uint256 _stakingAmountWorth, address _beneficiary) external {
        _mintTier(_tierId, _stakingAmountWorth, _beneficiary);
    }
}