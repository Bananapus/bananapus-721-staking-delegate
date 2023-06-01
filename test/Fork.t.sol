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
        delegate = new JB721StakingDelegateDeployer(
            new JB721StakingDelegate()
        ).deploy(
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

    // Test that a pay does not revert
    function testPay() public {
        address _payer = address(0x1337);
        _mintTokens(_payer, 1000);

        // Give allowance to the staking terminal
        vm.startPrank(_payer);
        stakingToken.approve(address(stakingTerminal), 1000);

        // Perform the pay (aka. stake the tokens)
        stakingTerminal.pay(projectId, 1000, address(stakingToken), _payer, 0, false, string(""), bytes(""));

        // Balance should be 0
        assertEq(stakingToken.balanceOf(_payer), 0);
    }

    // Test that a pay does not revert
    function testPayMintsNFT() public {
        address _payer = address(0x1337);
        _mintTokens(_payer, 1000);

        // Give allowance to the staking terminal
        vm.startPrank(_payer);
        stakingToken.approve(address(stakingTerminal), 1000);

        // Perform the pay (aka. stake the tokens)
        stakingTerminal.pay(projectId, 1000, address(stakingToken), _payer, 0, false, string(""), bytes(""));

        // There should now be a single token minted
        // assertEq(
        //     delegate.numberOfTokensMinted(),
        //     1
        // );
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
