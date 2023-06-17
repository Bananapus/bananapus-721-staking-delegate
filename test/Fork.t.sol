// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import "../src/JB721StakingDelegateDeployer.sol";

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

    address projectOwner = address(0x7331);

    uint256 projectId;
    IERC20 stakingToken = IERC20(0x4554CC10898f92D45378b98D6D6c2dD54c687Fb2); // JBXV3

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

        projectId = JBProjects.count() + 1;

        // Deploy the deployer, with the implementation and then deploy a implementation clone
        delegate = new JB721StakingDelegateDeployer()
        .deploy(
            projectId,
            stakingToken,
            JBDirectory,
            IJBTokenUriResolver(address(0)),
            "JBXStake",
            "STAKE",
            "",
            "",
            bytes32('0')
        );

        // Deploy a new terminal for the project token
        stakingTerminal = new JBERC20PaymentTerminal(
            IERC20Metadata(address(stakingToken)),
            JBCurrencies.ETH,
            JBCurrencies.ETH,
            0,
            JBOperatable(address(JBDirectory)).operatorStore(),
            JBDirectory.projects(),
            JBDirectory,
            JBSplitsStore,
            JBsingleTokenPaymentStore.prices(),
            JBsingleTokenPaymentStore,
            address(this)
        );

        IJBPaymentTerminal[] memory _terminals = new IJBPaymentTerminal[](1);
        _terminals[0] = stakingTerminal;

        projectId = JBController.launchProjectFor(
            projectOwner,
            JBProjectMetadata({content: "", domain: 0}),
            JBFundingCycleData({duration: 0, weight: 0, discountRate: 0, ballot: IJBFundingCycleBallot(address(0))}),
            JBFundingCycleMetadata({
                global: JBGlobalFundingCycleMetadata({
                    allowSetTerminals: true,
                    allowSetController: false,
                    pauseTransfers: false
                }),
                reservedRate: 0,
                redemptionRate: 0,
                ballotRedemptionRate: 0,
                pausePay: false,
                pauseDistributions: false,
                pauseRedeem: false,
                pauseBurn: false,
                allowMinting: true,
                allowTerminalMigration: false,
                allowControllerMigration: false,
                holdFees: false,
                preferClaimedTokenOverride: false,
                useTotalOverflowForRedemptions: false,
                useDataSourceForPay: true,
                useDataSourceForRedeem: true,
                dataSource: address(delegate),
                metadata: 0
            }),
            0,
            new JBGroupedSplits[](0),
            new JBFundAccessConstraints[](0),
            _terminals,
            ""
        );
    }

    function testPay_defaultStakeAmount(uint16[] memory _tierIds) public {
        // Calculate the cost for the mint
        uint256 _cost;
        for (uint256 _i; _i < _tierIds.length;) {
            // TODO: for now this is a hardcoded price
            vm.assume(_cost < type(uint224).max - 100 ether);
            _cost += 100 ether;

            unchecked {
                ++_i;
            }
        }

        address _payer = address(0x1337);
        _mintTokens(_payer, _cost);

        // Give allowance to the staking terminal
        vm.startPrank(_payer);
        stakingToken.approve(address(stakingTerminal), _cost);

        // Encode the metadata
        bytes memory _metadata =
            abi.encode(bytes32(0), bytes32(0), type(IJBTiered721Delegate).interfaceId, false, _tierIds);

        // Perform the pay (aka. stake the tokens)
        stakingTerminal.pay(projectId, _cost, address(stakingToken), _payer, 0, false, string(""), _metadata);

        // The tokens should be transferred from the user
        assertEq(stakingToken.balanceOf(_payer), 0);
        // The terminal should have the staking tokens
        assertEq(stakingToken.balanceOf(address(stakingTerminal)), _cost);
        // Check that the user received the voting power 1:1 of the staked amount
        assertEq(delegate.userVotingPower(_payer), _cost);
    }

    function testPay_customStakeAmount(uint16 _tierId, uint128 _customAdditionalStakeAmount, address _delegatingTo)
        public
    {
        // Calculate the cost for the mint
        vm.assume(_customAdditionalStakeAmount < type(uint128).max - 100 ether);
        uint128 _cost = 100 ether + uint128(_customAdditionalStakeAmount);

        JB721StakingTier[] memory _tiers = new JB721StakingTier[](1);
        _tiers[0] = JB721StakingTier({tierId: _tierId, amount: _cost});

        address _payer = address(0x1337);
        _mintTokens(_payer, _cost);

        // Give allowance to the staking terminal
        vm.startPrank(_payer);
        stakingToken.approve(address(stakingTerminal), _cost);

        // Encode the metadata
        bytes memory _metadata =
            abi.encode(bytes32(0), bytes32(0), type(IJB721StakingDelegate).interfaceId, false, _delegatingTo, _tiers);

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

    function testPayAndRedeem_defaultStakeAmount(uint8[] memory _tierIds) public {
        address _payer = address(0x1337);

        // Calculate the cost for the mint
        uint256 _cost;
        for (uint256 _i; _i < _tierIds.length;) {
            // TODO: for now this is a hardcoded price
            vm.assume(_cost < type(uint224).max - 100 ether);
            _cost += 100 ether;

            unchecked {
                ++_i;
            }
        }

        _mintTokens(_payer, _cost);

        // Give allowance to the staking terminal
        vm.startPrank(_payer);
        stakingToken.approve(address(stakingTerminal), _cost);

        // Encode the metadata
        bytes memory _metadata =
            abi.encode(bytes32(0), bytes32(0), type(IJBTiered721Delegate).interfaceId, false, _tierIds);

        // Perform the pay (aka. stake the tokens)
        stakingTerminal.pay(projectId, _cost, address(stakingToken), _payer, 0, false, string(""), _metadata);

        // The tokens should be transferred from the user
        assertEq(stakingToken.balanceOf(_payer), 0);
        // The terminal should have the staking tokens
        assertEq(stakingToken.balanceOf(address(stakingTerminal)), _cost);
        // Check that the user received the voting power 1:1 of the staked amount
        assertEq(delegate.userVotingPower(_payer), _cost);

        // We have to check every tier to see what the exact tokenIds are
        for (uint256 _tierId; _tierId < 256; _tierId++) {
            // Get the number minted for the tier
            uint256 _nMinted = delegate.numberOfTokensMintedOfTier(_tierId);
            // Append all the ids to the array so we can redeem them
            for (uint256 _j = 1; _j <= _nMinted; _j++) {
                _tokenIds.push(_tierId * 1_000_000_000 + _j);
            }
        }

        // Build the redemption metadata
        bytes memory _redemptionMetadata = abi.encode(bytes32(0), type(IJB721Delegate).interfaceId, _tokenIds);

        vm.prank(_payer);
        stakingTerminal.redeemTokensOf(
            _payer, projectId, 0, address(stakingToken), 0, payable(_payer), "", _redemptionMetadata
        );

        // Assert that the user received their staked tokens
        assertEq(stakingToken.balanceOf(_payer), _cost);
    }

    // Helpers
    function _mintTokens(address _to, uint256 _amount) internal {
        IJBToken _stakingToken = IJBToken(address(stakingToken));
        // Prank as being the contract owner (the tokenStore usually)
        vm.startPrank(Ownable(address(stakingToken)).owner());
        // Mint the needed tokens
        _stakingToken.mint(_stakingToken.projectId(), _to, _amount);
        vm.stopPrank();
    }
}
