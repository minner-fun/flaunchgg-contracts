// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IManagerPermissions} from '@flaunch-interfaces/IManagerPermissions.sol';


/**
 * Prevents anyone except the manager owner from depositing tokens into the treasury manager.
 */
contract ClosedPermissions is IManagerPermissions {

    /**
     * Always returns false, preventing anyone except the manager owner from depositing tokens
     * into the treasury manager.
     *
     * @return Always returns `false`
     */
    function isValidCreator(address, bytes calldata) public pure returns (bool) {
        return false;
    }

}
