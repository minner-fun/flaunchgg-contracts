// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import {IManagerPermissions} from '@flaunch-interfaces/IManagerPermissions.sol';
import {ITreasuryManager} from '@flaunch-interfaces/ITreasuryManager.sol';
import {ITreasuryManagerFactory} from '@flaunch-interfaces/ITreasuryManagerFactory.sol';


/**
 * Allows only whitelisted creators to deposit tokens into the group.
 */
contract WhitelistedPermissions is IManagerPermissions {

    using EnumerableSet for EnumerableSet.AddressSet;

    error Unauthorized();

    event ApprovedCreatorAdded(address indexed _group, address indexed _creator);
    event ApprovedCreatorRemoved(address indexed _group, address indexed _creator);

    /// The approved creators for each group
    mapping (address _group => EnumerableSet.AddressSet _approvedCreators) internal _approvedCreators;

    /// The factory that creates the treasury managers
    ITreasuryManagerFactory public immutable treasuryManagerFactory;

    /**
     * Sets the {TreasuryManagerFactory} that will be used to validate the `setApprovedCreators` call.
     *
     * @param _treasuryManagerFactory The factory that creates the treasury managers
     */
    constructor (ITreasuryManagerFactory _treasuryManagerFactory) {
        treasuryManagerFactory = _treasuryManagerFactory;
    }

    /**
     * Checks if the specified address is a valid creator and can deposit tokens into the group.
     *
     * @dev The group is inferred by the `msg.sender`.
     *
     * @param _creator The address to check
     *
     * @return `true` if the address is a valid creator, `false` otherwise
     */
    function isValidCreator(address _creator, bytes calldata) public view returns (bool) {
        return _approvedCreators[msg.sender].contains(_creator);
    }

    /**
     * Sets the approved creators that can deposit tokens into the group.
     *
     * @dev Only the manager owner of the group can call this function. Ths group must be recognised by the
     * {TreasuryManagerFactory} that was passed to the constructor.
     *
     * @param _group The group to set the approved creators for
     * @param _creators The addresses to whitelist
     * @param _approved Whether to whitelist or blacklist the creators
     */
    function setApprovedCreators(address _group, address[] calldata _creators, bool _approved) public {
        // Ensure that the group is recognised by the {TreasuryManagerFactory}
        if (treasuryManagerFactory.managerImplementation(_group) == address(0)) {
            revert Unauthorized();
        }

        // Get the manager owner of the group from the address passed and confirm that the caller
        // is the authorized manager owner.
        if (ITreasuryManager(_group).managerOwner() != msg.sender) {
            revert Unauthorized();
        }

        // Iterate over the creators and add or remove them from the approved creators
        for (uint i = 0; i < _creators.length; ++i) {
            if (_approved) {
                if (_approvedCreators[_group].add(_creators[i])) {
                    emit ApprovedCreatorAdded(_group, _creators[i]);
                }
            } else {
                if (_approvedCreators[_group].remove(_creators[i])) {
                    emit ApprovedCreatorRemoved(_group, _creators[i]);
                }
            }
        }
    }

}
