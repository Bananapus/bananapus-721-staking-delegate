// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IJBDirectory} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import {IJBController} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController.sol";
import {IJBSingleTokenPaymentTerminalStore} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminalStore.sol";
import {IJBOperatorStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";
import {IJBSplitsStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitsStore.sol";
import {IJBProjects} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBProjects.sol";
import {IJBProjects} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBProjects.sol";
import {IJBDelegatesRegistry} from "@jbx-protocol/juice-delegates-registry/src/interfaces/IJBDelegatesRegistry.sol";
import {JB721StakingDelegate} from "./JB721StakingDelegate.sol";
import {JBERC20TerminalDeployer} from "./JBERC20TerminalDeployer.sol";

/// @notice Deploy Juicebox projects with a single purpose of providing staking functionality.
contract JB721StakingDelegateDeployer {
    //*********************************************************************//
    // --------------------- internal stored properties ------------------ //
    //*********************************************************************//

    /// @notice This contract's current nonce, used for the Juicebox delegates registry.
    uint256 internal _nonce;

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The controller through which staking projects are made from.
    IJBController public immutable controller;

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory public immutable directory;

    /// @notice The contract that stores and manages payment terminal data.
    IJBSingleTokenPaymentTerminalStore public immutable paymentTerminalStore;

    /// @notice A contract storing operator assignments.
    IJBOperatorStore public immutable operatorStore;

    /// @notice The contract that stores splits for each project.
    IJBSplitsStore public immutable splitStore;

    /// @notice Mints ERC-721's that represent project ownership and transfers.
    IJBProjects public immutable projects;

    /// @notice The contract that deploys ERC20 terminals through which staking will occur.
    JBERC20TerminalDeployer public immutable terminalDeployer;

    /// @notice A contract that stores references to deployer contracts of delegates.
    IJBDelegatesRegistry public immutable delegatesRegistry;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param _controller The controller through which staking projects are made from.
    /// @param _directory The directory of terminals and controllers for projects.
    /// @param _projects Mints ERC-721's that represent project ownership and transfers.
    /// @param _operatorStore A contract storing operator assignments.
    /// @param _paymentTerminalStore The contract that stores and manages payment terminal data.
    /// @param _splitStore The contract that stores splits for each project.
    /// @param _terminalDeployer The contract that deploys ERC20 terminals through which staking will occur.
    /// @param _delegatesRegistry A contract that stores references to deployer contracts of delegates.
    constructor(
        IJBController _controller,
        IJBDirectory _directory,
        IJBProjects _projects,
        IJBOperatorStore _operatorStore,
        IJBSingleTokenPaymentTerminalStore _paymentTerminalStore,
        IJBSplitsStore _splitStore,
        JBERC20TerminalDeployer _terminalDeployer,
        IJBDelegatesRegistry _delegatesRegistry
    ) {
        controller = _controller;
        paymentTerminalStore = _paymentTerminalStore;
        directory = _directory;
        operatorStore = _operatorStore;
        splitStore = _splitStore;
        projects = _projects;
        terminalDeployer = _terminalDeployer;
        delegatesRegistry = _delegatesRegistry;
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Deploy a Juicebox project that offers staking.
    /// @param _projectMetadata Metadata to associate with the project within a particular domain. This can be updated
    /// any time by the owner of the project.
    /// @param _stakingToken The staking token to expect.
    /// @param _uriResolver The contract that contains the 721's rendering and contextual data.
    /// @param _name The name of the staking 721.
    /// @param _symbol The symbol of the staking 721.
    /// @param _contractUri A URI containing metadata for the 721.
    /// @param _baseUr A common base for the encoded IPFS URIs.
    /// @param _encodedIPFSUri Encoded URI to be used when no token resolver is provided.
    /// @param _tierMultiplier The multiplier applied to minimum staking thresholds for each tier ID.
    /// @param _maxTier The maximum number of tiers.
    /// @return stakingProjectId The ID of the project managing staking.
    /// @return stakingTerminal The payment terminal through which staking will be conducted.
    /// @return delegate The 721 delegate representing staking positions.
    function deployStakingProject(
        JBProjectMetadata memory _projectMetadata,
        IERC20Metadata _stakingToken,
        IJB721TokenUriResolver _uriResolver,
        string memory _name,
        string memory _symbol,
        string memory _contractUri,
        string memory _baseUri,
        bytes32 _encodedIPFSUri,
        uint256 _tierMultiplier,
        uint8 _maxTier
    )
        external
        returns (
            uint256 stakingProjectId,
            IJBPayoutRedemptionPaymentTerminal stakingTerminal,
            JB721StakingDelegate delegate
        )
    {
        // Get the project ID, optimistically knowing it will be one greater than the current count.
        uint256 _projectId = projects.count() + 1;

        // Deploy the delegate.
        _delegate = deployDelegate(
            _projectId,
            _stakingToken,
            _uriResolver,
            _name,
            _symbol,
            _contractUri,
            _baseUri,
            _encodedIPFSUri,
            _tierMultiplier,
            _maxTier
        );

        // Deploy a new terminal for the project token.
        _stakingTerminal = terminalDeployer.deploy(
            _stakingToken,
            JBCurrencies.ETH,
            JBCurrencies.ETH,
            0,
            operatorStore,
            projects,
            directory,
            splitStore,
            paymentTerminalStore.prices(),
            paymentTerminalStore
        );

        // Package the terminal into an array.
        IJBPaymentTerminal[] memory _terminals = new IJBPaymentTerminal[](1);
        _terminals[0] = _stakingTerminal;

        // Deploy the project and configure it to use the delegate and project token terminal
        _stakingProjectId = _launchProject(_projectMetadata, _delegate, _terminals);
    }

    //*********************************************************************//
    // ----------------------- public transactions ----------------------- //
    //*********************************************************************//

    /// @notice Deploys a staking delegate.
    /// @param _projectId The ID of the project to which the staking delegate applies.
    /// @param _stakingToken The staking token to expect.
    /// @param _uriResolver The contract that contains the 721's rendering and contextual data.
    function deployDelegate(
        uint256 _projectId,
        IERC20Metadata _stakingToken,
        IJB721TokenUriResolver _uriResolver,
        string memory _name,
        string memory _symbol,
        string memory _contractURI,
        string memory _baseURI,
        bytes32 _encodedIPFSUri,
        uint256 _tierMultiplier,
        uint8 _maxTier
    ) public returns (JB721StakingDelegate newDelegate) {
        /// Deploy a new delegate
        newDelegate = new JB721StakingDelegate(
            _projectId, _stakingToken, directory, _uriResolver, _name, _symbol, _contractURI, _baseURI, _encodedIPFSUri, _tierMultiplier, _maxTier
        );

        // Add the delegate to the registry. Contract nonce starts at 1.
        unchecked {
            delegatesRegistry.addDelegate(address(this), ++_nonce);
        }
    }

    //*********************************************************************//
    // ---------------------- internal transactions ---------------------- //
    //*********************************************************************//

    /// @notice Launches a juicebox project.
    /// @param _projectMetadata Metadata to associate with the project within a particular domain. This can be updated
    /// any time by the owner of the project.
    /// @param _delegate The staking delegate to forward payments to.
    /// @param _terminals The terminals to expect staking operations to be made from.
    function _launchProject(
        JBProjectMetadata memory _projectMetadata,
        JB721StakingDelegate _delegate,
        IJBPaymentTerminal[] memory _terminals
    ) internal returns (uint256) {
        return controller.launchProjectFor(
            address(this),
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
            "staking deployed"
        );
    }
}
