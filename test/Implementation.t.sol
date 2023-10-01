// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./utils/DSTestFull.sol";

import "../src/JB721StakingDelegate.sol";
import "../src/JB721StakingDelegateDeployer.sol";
import "../src/distributor/JB721StakingDistributor.sol";

import "../src/JB721StakingUriResolver.sol";

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DelegateTest_Implementation is Test {
    string constant SVG_PATH = "./template.svg";

    function test_tokenUriOf() public {
        // Deploy the tokenResolver and dependencies
        string memory _template = vm.readFile(SVG_PATH);
        address _templatePointer = SSTORE2.write(bytes(_template));

        JB721StakingUriResolver _resolver = new JB721StakingUriResolver(_templatePointer);

        // Deploy the delegate
        JB721StakingDelegate _delegate = new JB721StakingDelegate(
            1, IERC20Metadata(address(0)), IJBDirectory(address(0)), _resolver, "test", "test", "", "", "", 1 gwei, 59
        );

        // Perform the call and check that it returns a string with content
        // (20 is an arbitrary number, but this resolver should never return less than 20 bytes)
        assert(bytes(_delegate.tokenURI(1)).length > 20);
    }
}
