// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./JB721StakingDelegate.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract JB721StakingDelegateDeployer {
    /** 
    @notice 
    The delegate implementation
  */
    JB721StakingDelegate public immutable delegateImplementation;

    constructor(JB721StakingDelegate _delegateImplementation) {
        delegateImplementation = _delegateImplementation;
    }

    /**
     * @notice deploy a staking delegate for a project
     * 
     * @param _projectId the prooject to deploy it for
     * @param _directory the JBDirecory to use
     * @param _name the name of the nft
     * @param _symbol the symbol of the nft
     */
    function deploy(
        uint256 _projectId,
        IJBDirectory _directory,
        IJBTokenUriResolver _uriResolver,
        string memory _name,
        string memory _symbol,
        string memory _contractURI,
        string memory _baseURI,
        bytes32 _encodedIPFSUri
    ) external returns (JB721StakingDelegate newDelegate) {
        newDelegate = JB721StakingDelegate(
            Clones.clone(address(delegateImplementation))
        );

        newDelegate.initialize(_projectId, _directory, _uriResolver, _name, _symbol, _contractURI, _baseURI, _encodedIPFSUri);
    }
}
