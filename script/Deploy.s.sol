// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../src/JBERC20TerminalDeployer.sol";
import "../src/JB721StakingDelegateDeployer.sol";

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
    IJBSingleTokenPaymentTerminalStore JBsingleTokenPaymentStore = IJBSingleTokenPaymentTerminalStore(0x101cA528F6c2E35664529eB8aa0419Ae1f724b49);
    IJBSplitsStore JBSplitsStore = IJBSplitsStore(0xce2Ce2F37fE5B2C2Dd047908B2F61c9c3f707272);
    IJBProjects JBProjects = IJBProjects(0x21263a042aFE4bAE34F08Bb318056C181bD96D3b);
    IJBDelegatesRegistry registry = IJBDelegatesRegistry(0xCe3Ebe8A7339D1f7703bAF363d26cD2b15D23C23); 

    IERC20Metadata stakingToken = IERC20Metadata(0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6); // WETH on Goerli

    //JBERC20TerminalDeployer terminalDeployer;
    JB721StakingDelegateDeployer delegateDeployer = JB721StakingDelegateDeployer(0xDDff310472a5328B62FFC7cD0471744b7a3dfF40);

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // // Deploy the terminal deployer
        // terminalDeployer = new JBERC20TerminalDeployer();

        // // Deploy the delegate deployer
        // delegateDeployer = new JB721StakingDelegateDeployer(
        //     JBController, 
        //     JBDirectory,
        //     JBProjects,
        //     JBOperatorStore,
        //     JBsingleTokenPaymentStore,
        //     JBSplitsStore,
        //     terminalDeployer,
        //     registry
        // );

        // Deploy the test project
        delegateDeployer.deployStakingProject(
            JBProjectMetadata({content: 'bafkreig2nxunu6oxhmj6grsam5e7rzs5l6geulbcdukbila43dq2gyofny', domain: 0}),
            stakingToken,
            IJBTokenUriResolver(address(0)),
            "WETH Governance",
            "WETHDAO",
            "",
            "",
            bytes32(0x536f0f21ac9c3ca5106e7459bca9ade08069b709e184510931644733db2720fa),
            1 ether,
            5
        );

        vm.stopBroadcast();
    }
}
