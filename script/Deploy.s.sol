// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../src/JBERC20TerminalDeployer.sol";
import "../src/JB721StakingDelegateDeployer.sol";
import "../src/distributor/JB721StakingDistributor.sol";

import "forge-std/Test.sol";
import {Base64} from "lib/solady/src/utils/Base64.sol";
import "lib/solady/src/utils/LibString.sol";

import "../src/JB721StakingUriResolver.sol";

import {ERC20, IERC20} from "lib/bananapus-distributor/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IJBFundingCycleStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleStore.sol";
import {WETH} from "lib/solady/src/tokens/WETH.sol";

contract DeployMainnet is Script {
    function setUp() public {}

    function run() public {
        vm.broadcast();
    }
}

contract DeployGoerli is Script {
    IJBController JBController = IJBController(0x1d260DE91233e650F136Bf35f8A4ea1F2b68aDB6);
    IJBDirectory JBDirectory = IJBDirectory(0x8E05bcD2812E1449f0EC3aE24E2C395F533d9A99);
    IJBFundingCycleStore JBFundingCycleStore = IJBFundingCycleStore(0xB9Ee9d8203467f6EC0eAC81163d210bd1a7d3b55);
    IJBOperatorStore JBOperatorStore = IJBOperatorStore(0x99dB6b517683237dE9C494bbd17861f3608F3585);
    IJBSingleTokenPaymentTerminalStore3_1_1 JBsingleTokenPaymentStore =
        IJBSingleTokenPaymentTerminalStore3_1_1(0x101cA528F6c2E35664529eB8aa0419Ae1f724b49);
    IJBSplitsStore JBSplitsStore = IJBSplitsStore(0xce2Ce2F37fE5B2C2Dd047908B2F61c9c3f707272);
    IJBProjects JBProjects = IJBProjects(0x21263a042aFE4bAE34F08Bb318056C181bD96D3b);
    IJBDelegatesRegistry registry = IJBDelegatesRegistry(0xCe3Ebe8A7339D1f7703bAF363d26cD2b15D23C23);

    WETH stakingToken = WETH(payable(0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6)); // WETH on Goerli

    JBERC20TerminalDeployer terminalDeployer;
    JB721StakingDelegateDeployer delegateDeployer;

    uint256 constant BLOCK_TIME = 12 seconds;
    uint256 constant VESTING_CYCLE_DURATION = 1 hours / BLOCK_TIME;
    uint256 constant VESTING_CYCLES_UNIL_RELEASED = 3;
    string constant SVG_PATH = "./template.svg";

    function setUp() public {}

    function run() public {
        uint256 _cost = 2 gwei;

        // Mint 2x tierId `0`
        uint16[] memory _tierIds = new uint16[](2);
        _tierIds[0] = 0;
        _tierIds[1] = 0;

        vm.startBroadcast();

        string memory _template = vm.readFile(SVG_PATH);
        address _templatePointer = SSTORE2.write(bytes(_template));

        JB721StakingUriResolver _resolver = new JB721StakingUriResolver(_templatePointer);

        // Deploy the terminal deployer
        terminalDeployer = new JBERC20TerminalDeployer();

        // Deploy the delegate deployer
        delegateDeployer = new JB721StakingDelegateDeployer(
            JBController, 
            JBDirectory,
            JBProjects,
            JBOperatorStore,
            JBsingleTokenPaymentStore,
            JBSplitsStore,
            terminalDeployer,
            registry
        );

        // Deploy the test project
        (uint256 _projectID, IJBPayoutRedemptionPaymentTerminal3_1_1 _stakingTerminal, JB721StakingDelegate _newDelegate) =
        delegateDeployer.deployStakingProject(
            JBProjectMetadata({content: "bafkreig2nxunu6oxhmj6grsam5e7rzs5l6geulbcdukbila43dq2gyofny", domain: 0}),
            IERC20Metadata(address(stakingToken)),
            IJB721TokenUriResolver(_resolver),
            "WETH Governance",
            "WETHDAO",
            "",
            "",
            bytes32(0x536f0f21ac9c3ca5106e7459bca9ade08069b709e184510931644733db2720fa),
            1 gwei,
            59
        );

        // Convert some ETH to wETH
        stakingToken.deposit{value: _cost}();

        // Mint two NFTs in the same Tier
        stakingToken.approve(address(_stakingTerminal), _cost);

        // Deploy the distributor
        JB721StakingDistributor _distributor =
            new JB721StakingDistributor(_newDelegate, VESTING_CYCLE_DURATION, VESTING_CYCLES_UNIL_RELEASED);

        // Deploy a token to be distributed
        TestERC20 _token = new TestERC20();

        // Mint tokens to the distributor
        _token.ForTest_mintTo(100 ether, address(_distributor));

        // Perform the pay (aka. stake the tokens)
        // bytes memory _metadata =
        //     abi.encode(bytes32(0), bytes32(0), type(IJBTiered721Delegate).interfaceId, false, _tierIds);
        // _stakingTerminal.pay(_projectID, _cost, address(stakingToken), tx.origin, 0, false, string(""), _metadata);

        // // Perform the claim
        // IERC20[] memory tokens = new IERC20[](1);
        // tokens[0] = IERC20(_token);

        // uint256[] memory nftIds = new uint256[](1);
        // nftIds[0] = _generateTokenId(1, 1);

        // _distributor.claim(nftIds, tokens);

        vm.stopBroadcast();

        console2.log("delegate", address(_newDelegate));
        console2.log("distributor", address(_distributor));
        console2.log("terminal", address(_stakingTerminal));
        console2.log("token", address(stakingToken));
        console2.log("terminalDeployer", address(terminalDeployer));
        console2.log("delegateDeployer", address(delegateDeployer));
        console2.log("staking project ID", _projectID);
        // console2.log("tokenId", nftIds[0]);
    }

    function _generateTokenId(uint256 _tierId, uint256 _tokenNumber) internal pure returns (uint256) {
        return (_tierId * 1_000_000_000) + _tokenNumber;
    }
}

contract Claim is Script {
    JB721StakingDistributor _distributor = JB721StakingDistributor(0x314A84CCad8bd49e1d198c048f281A416B4b5824);
    IERC20 _token = IERC20(0x6eaB554233DbDafA8197ab2B9E4a471585711618);

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        // Perform the claim
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(_token);

        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = 1;

        _distributor.beginVesting(nftIds, tokens);

        vm.stopBroadcast();
    }
}

contract Collect is Script {
    JB721StakingDistributor _distributor = JB721StakingDistributor(0x314A84CCad8bd49e1d198c048f281A416B4b5824);
    IERC20 _token = IERC20(0x6eaB554233DbDafA8197ab2B9E4a471585711618);

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        _distributor.currentRound();
        _distributor.roundStartBlock(10);

        // Perform the claim
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(_token);

        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = 1;

        _distributor.collectVestedRewards(nftIds, tokens, 10);

        vm.stopBroadcast();
    }
}

contract TestERC20 is ERC20 {
    constructor() ERC20("testToken", "TEST") {}

    function ForTest_mintTo(uint256 _amount, address _beneficiary) external {
        _mint(_beneficiary, _amount);
    }
}
