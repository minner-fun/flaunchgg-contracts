// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IManagerPermissions} from '@flaunch-interfaces/IManagerPermissions.sol';

/**
 * Prevents anyone except the manager owner from depositing tokens into the treasury manager.
 * 防止任何人除了管理器所有者之外存入代币到资金库管理器。
 */
contract ClosedPermissions is IManagerPermissions {
    /**
     * Always returns false, preventing anyone except the manager owner from depositing tokens
     * into the treasury manager.
     * 总是返回false，防止任何人除了管理器所有者之外存入代币到资金库管理器。
     * @return Always returns `false`
     */
    function isValidCreator(address, bytes calldata) public pure returns (bool) {
        return false;
    }
}
