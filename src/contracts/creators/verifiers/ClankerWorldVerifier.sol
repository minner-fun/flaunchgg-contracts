// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IImportVerifier} from '@flaunch-interfaces/IImportVerifier.sol';


interface IClanker {

    struct DeploymentInfo {
        address token;
        uint positionId;
        address locker;
    }

    function deploymentInfoForToken(address token) external view returns (DeploymentInfo memory);

}

interface IClankerToken {
    function admin() external view returns (address);
}


/**
 * Confirms that a memecoin has been deployed on Clanker World.
 */
contract ClankerWorldVerifier is IImportVerifier {
    
    /// The Clanker contract
    IClanker public immutable clanker;

    /**
     * Registers the Clanker contract.
     *
     * @param _clanker The address of the Clanker contract
     */
    constructor (address _clanker) {
        clanker = IClanker(_clanker);
    }

    /**
     * Checks if a token exists on Clanker World.
     *
     * @param _token The address of the token to verify
     * @param _sender The address of the sender
     *
     * @return bool True if the token exists on Clanker World, false otherwise
     */
    function isValid(address _token, address _sender) public view returns (bool) {
        // Confirm that the token is deployed on Clanker World
        if (clanker.deploymentInfoForToken(_token).token == address(0)) {
            return false;
        }

        // Confirm that the sender is the original creator of the token
        return IClankerToken(_token).admin() == _sender;
    }

}