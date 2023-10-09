// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import "../src/JB721StakingDelegate.sol";
import "../src/JBERC20TerminalDeployer.sol";
import "../src/JB721StakingDelegateDeployer.sol";
import "../src/distributor/JB721StakingDistributor.sol";

import "@jbx-protocol/juice-contracts-v3/contracts/JBERC20PaymentTerminal.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleStore.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayoutRedemptionPaymentTerminal.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBProjects.sol";

// import "../src/Empty.sol";

contract EmptyTest_Fork is Test {
    IJBController JBController;
    IJBDirectory JBDirectory;
    IJBFundingCycleStore JBFundingCycleStore;
    IJBPayoutRedemptionPaymentTerminal JBEthTerminal;
    IJBPayoutRedemptionPaymentTerminal stakingTerminal;
    IJBSingleTokenPaymentTerminalStore JBsingleTokenPaymentStore;
    IJBSplitsStore JBSplitsStore;
    IJBProjects JBProjects;
    JB721StakingDelegate delegate;
    IJBDelegatesRegistry registry = IJBDelegatesRegistry(0x7A53cAA1dC4d752CAD283d039501c0Ee45719FaC);

    address projectOwner = address(0x7331);

    uint256 projectId;
    IERC20Metadata stakingToken = IERC20Metadata(0x4554CC10898f92D45378b98D6D6c2dD54c687Fb2); // JBXV3

    function setUp() public {
        vm.createSelectFork("https://rpc.ankr.com/eth"); // Will start on latest block by default
        // Collect the mainnet deployment addresses
        JBController = IJBController(
            stdJson.readAddress(
                vm.readFile("./node_modules/@jbx-protocol/juice-contracts-v3/deployments/mainnet/JBController.json"),
                ".address"
            )
        );
        JBEthTerminal = IJBPayoutRedemptionPaymentTerminal(
            stdJson.readAddress(
                vm.readFile(
                    "./node_modules/@jbx-protocol/juice-contracts-v3/deployments/mainnet/JBETHPaymentTerminal.json"
                ),
                ".address"
            )
        );
        JBsingleTokenPaymentStore = IJBSingleTokenPaymentTerminalStore(
            stdJson.readAddress(
                vm.readFile(
                    "./node_modules/@jbx-protocol/juice-contracts-v3/deployments/mainnet/JBSingleTokenPaymentTerminalStore.json"
                ),
                ".address"
            )
        );
        JBSplitsStore = IJBSplitsStore(
            stdJson.readAddress(
                vm.readFile("./node_modules/@jbx-protocol/juice-contracts-v3/deployments/mainnet/JBSplitsStore.json"),
                ".address"
            )
        );
        JBDirectory = JBController.directory();
        JBFundingCycleStore = JBController.fundingCycleStore();
        JBProjects = JBController.projects();

        JBERC20TerminalDeployer _terminalDeployer = new JBERC20TerminalDeployer();

        // Deploy the deployer, and create a staking project
        (projectId, stakingTerminal, delegate) = new JB721StakingDelegateDeployer(
            JBController, 
            JBDirectory,
            JBDirectory.projects(),
            JBOperatable(address(JBDirectory)).operatorStore(),
            JBsingleTokenPaymentStore,
            JBSplitsStore,
            _terminalDeployer,
            registry
        ).deployStakingProject(
            JBProjectMetadata({content: '', domain: 0}),
            stakingToken,
            IJB721TokenUriResolver(address(0)),
            "Juicebox Staking Test",
            "JST",
            "",
            "",
            bytes32(0),
            10 ** 18,
            59
        );
    }

    function testPay_customStakeAmount(uint16 _tierId, uint128 _customAdditionalStakeAmount, address _delegatingTo)
        public
    {
        // Check against oveflow
        vm.assume(_customAdditionalStakeAmount < type(uint128).max - 100 ether);

        _tierId = uint16(bound(_tierId, 0, 59));
        uint128 _cost = uint128(_validateTierAndGetCost(delegate, _tierId)) + uint128(_customAdditionalStakeAmount);

        JB721StakingTier[] memory _tiers = new JB721StakingTier[](1);
        _tiers[0] = JB721StakingTier({tierId: _tierId, amount: _cost});

        address _payer = address(0x1337);
        _mintTokens(_payer, _cost);

        // Give allowance to the staking terminal
        vm.startPrank(_payer);
        stakingToken.approve(address(stakingTerminal), _cost);

        // Encode the metadata
        bytes memory _metadata = abi.encode(
            bytes32(0),
            bytes32(0),
            type(IJB721StakingDelegate).interfaceId,
            false,
            _delegatingTo,
            _tiers,
            address(0),
            bytes("")
        );

        // Perform the pay (aka. stake the tokens)
        stakingTerminal.pay(projectId, _cost, address(stakingToken), _payer, 0, false, string(""), _metadata);

        // The tokens should be transferred from the user
        assertEq(stakingToken.balanceOf(_payer), 0);
        // The terminal should have the staking tokens
        assertEq(stakingToken.balanceOf(address(stakingTerminal)), _cost);
        // Check that the user received the voting power 1:1 of the staked amount
        assertEq(delegate.userVotingPower(_payer), _cost);
        // Assert that the voting power was delegated to the delegate recipient
        assertEq(delegate.delegates(_payer), _delegatingTo);
        // Voting power is not delegatable to the zero address
        if (_delegatingTo != address(0)) {
            // Assert that they received the voting power
            assertEq(delegate.getVotes(_delegatingTo), _cost);
        }
    }

    // we use this local var so we can use `push` because we don't know the size of the array beforehand
    uint256[] _tokenIds;
    // Helpers

    function _mintTokens(address _to, uint256 _amount) internal {
        IJBToken _stakingToken = IJBToken(address(stakingToken));
        // Prank as being the contract owner (the tokenStore usually)
        vm.startPrank(Ownable(address(stakingToken)).owner());
        // Mint the needed tokens
        _stakingToken.mint(_stakingToken.projectId(), _to, _amount);
        vm.stopPrank();
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
}
