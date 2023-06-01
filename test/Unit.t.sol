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
        JB721StakingDelegate _delegateImplementation = new JB721StakingDelegate();

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

    //*********************************************************************//
    // ----------------------------- Helpers ----------------------------- //
    //*********************************************************************//

    function _generateTokenId(uint256 _tierId, uint256 _tokenNumber) internal pure returns (uint256) {
        return (_tierId * 1_000_000_000) + _tokenNumber;
    }

    function _deployDelegate() internal returns (JB721StakingDelegate _delegate) {
        _delegate = _deployer.deploy(
            _projectId, _stakingToken, _directory, _resolver, "JBXStake", "STAKE", "", "", bytes32("0")
        );

        vm.mockCall(
            address(_directory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, int256(_projectId), address(_terminal)),
            abi.encode(true)
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
