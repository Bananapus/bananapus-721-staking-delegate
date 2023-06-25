// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {Base64} from "lib/solady/src/utils/Base64.sol";
import "lib/solady/src/utils/LibString.sol";

import "../src/JB721StakingUriResolver.sol";

contract DefaultSVGResolverTest is Test {
    using LibString for string;

    string constant SVG_PATH = "./template.svg";
    JB721StakingUriResolver public resolver;

    function setUp() public {
        string memory _template = vm.readFile(SVG_PATH);
        address _templatePointer = SSTORE2.write(bytes(_template));

        resolver = new JB721StakingUriResolver(_templatePointer);
    }

    function run() public {
        // The tier ID to generate for
        uint256 _tier = 53;

        // Generate the URI
        string memory _uri = resolver.tokenUri(_tier * 1_000_000_000);
        // Get the base64 from the JSON
        _uri = _uri.slice(_uri.indexOf(",") + 1, bytes(_uri).length);

        // Get the base64 image part and decode it
        string memory _metadata = string(Base64.decode(_uri));
        string memory _svg = string(Base64.decode(_metadata.slice(_metadata.indexOf("base64,") + 7, _metadata.lastIndexOf("}") - 1)));

        // Write the image to a file       
        vm.writeFile("./out/image.svg", _svg);
    }
}
