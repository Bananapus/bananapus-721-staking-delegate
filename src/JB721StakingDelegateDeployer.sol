// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./JB721StakingDelegate.sol";
import "./JBERC20TerminalDeployer.sol";

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/JBERC20PaymentTerminal.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";

contract JB721StakingDelegateDeployer {
    IJBController public immutable controller;
    IJBDirectory public immutable directory;
    IJBSingleTokenPaymentTerminalStore public immutable tokenPaymentTerminalStore;
    IJBOperatorStore public immutable operatorStore;
    IJBSplitsStore public immutable splitStore;
    IJBProjects public immutable projects;

    JBERC20TerminalDeployer public immutable terminalDeployer;

    /**
     *
     */
    constructor(
        IJBController _controller,
        IJBDirectory _directory,
        IJBProjects _projects,
        IJBOperatorStore _operatorStore,
        IJBSingleTokenPaymentTerminalStore _tokenPaymentTerminalStore,
        IJBSplitsStore _splitStore,
        JBERC20TerminalDeployer _terminalDeployer
    ) {
        controller = _controller;
        tokenPaymentTerminalStore = _tokenPaymentTerminalStore;
        directory = _directory;
        operatorStore = _operatorStore;
        splitStore = _splitStore;
        projects = _projects;
        terminalDeployer = _terminalDeployer;
    }

    /**
     * @notice deploy a staking project
     *
     * @param _name the name of the nft
     * @param _symbol the symbol of the nft
     */
    function deployStakingProject(
        JBProjectMetadata memory _projectMetadata,
        IERC20Metadata _stakingToken,
        IJBTokenUriResolver _uriResolver,
        string memory _name,
        string memory _symbol,
        string memory _contractURI,
        string memory _baseURI,
        bytes32 _encodedIPFSUri
    )
        external
        returns (
            uint256 _stakingProjectId,
            IJBPayoutRedemptionPaymentTerminal _stakingTerminal,
            JB721StakingDelegate _delegate
        )
    {
        // Optimistically get the projectID
        uint256 _projectId = projects.count() + 1;

        // Deploy the delegate
        _delegate = deployDelegate(
            _projectId, _stakingToken, _uriResolver, _name, _symbol, _contractURI, _baseURI, _encodedIPFSUri
        );

        // Deploy a new terminal for the project token
        _stakingTerminal = terminalDeployer.deploy(
            _stakingToken,
            JBCurrencies.ETH,
            JBCurrencies.ETH,
            0,
            operatorStore,
            projects,
            directory,
            splitStore,
            tokenPaymentTerminalStore.prices(),
            tokenPaymentTerminalStore
        );

        IJBPaymentTerminal[] memory _terminals = new IJBPaymentTerminal[](1);
        _terminals[0] = _stakingTerminal;

        // Deploy the project and configure it to use the delegate and project token terminal
        _stakingProjectId = controller.launchProjectFor(
            address(0x1), // TODO: replace with a better address to prove there is no owner
            _projectMetadata,
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
                dataSource: address(_delegate),
                metadata: 0
            }),
            0,
            new JBGroupedSplits[](0),
            new JBFundAccessConstraints[](0),
            _terminals,
            ""
        );
    }

    /**
     * @notice deploy a staking delegate
     */
    function deployDelegate(
        uint256 _projectId,
        IERC20Metadata _stakingToken,
        IJBTokenUriResolver _uriResolver,
        string memory _name,
        string memory _symbol,
        string memory _contractURI,
        string memory _baseURI,
        bytes32 _encodedIPFSUri
    ) public returns (JB721StakingDelegate _newDelegate) {
        _newDelegate = new JB721StakingDelegate(
            _projectId, _stakingToken, directory, _uriResolver, _name, _symbol, _contractURI, _baseURI, _encodedIPFSUri
        );
    }
}
