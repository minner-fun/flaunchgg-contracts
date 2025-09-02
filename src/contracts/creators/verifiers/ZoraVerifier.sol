// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from '@solady/auth/Ownable.sol';

import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import {ProxyCheck} from '@flaunch/libraries/ProxyCheck.sol';

import {IImportVerifier} from '@flaunch-interfaces/IImportVerifier.sol';


/**
 * Interface for the Zora Coin contract.
 */
interface IZoraCoin {
    function isOwner(address _owner) external view returns (bool);
}


/**
 * Confirms that a memecoin has been defined in the Zora Airlock.
 */
contract ZoraVerifier is IImportVerifier, Ownable {

    using EnumerableSet for EnumerableSet.AddressSet;

    error ZeroAddress();

    event ZoraCoinImplementationSet(address indexed _zoraCoinImplementation, bool _valid);

    /// The Zora token implementation contract
    EnumerableSet.AddressSet internal _zoraCoinImplementations;

    /**
     * Registers the Zora token implementation contract.
     */
    constructor () {
        // Set the owner to the deployer
        _initializeOwner(msg.sender);
    }

    /**
     * Checks if a token was deployed from a supported Zora Coin implementation.
     *
     * @param _token The address of the token to verify
     * @param _sender The address of the sender
     *
     * @return bool True if the token is a Zora token, false otherwise
     */
    function isValid(address _token, address _sender) public view returns (bool) {
        // If the token is not a Zora token, then it is not valid
        if (!_zoraCoinImplementations.contains(ProxyCheck.getImplementation(_token))) {
            return false;
        }

        // Confirm that the sender is an owner of the Zora coin
        return IZoraCoin(_token).isOwner(_sender);
    }

    /**
     * Sets or removes a Zora coin implementation address.
     *
     * @param _zoraCoinImplementation The address of the Zora coin implementation
     * @param _valid Whether the implementation is valid
     */
    function setZoraCoinImplementation(address _zoraCoinImplementation, bool _valid) external onlyOwner {
        // Ensure that the Zora coin implementation is not a zero address
        if (_zoraCoinImplementation == address(0)) {
            revert ZeroAddress();
        }

        // Add or remove the Zora coin implementation
        if (_valid) {
            _zoraCoinImplementations.add(_zoraCoinImplementation);
        } else {
            _zoraCoinImplementations.remove(_zoraCoinImplementation);
        }

        emit ZoraCoinImplementationSet(_zoraCoinImplementation, _valid);
    }

}