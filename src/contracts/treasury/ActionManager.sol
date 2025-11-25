// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from '@solady/auth/Ownable.sol';


/**
 * Allows the contract owner to manage approved {ITreasuryAction} contracts.
 * 允许合约所有者管理批准的{ITreasuryAction}合约。
 */
contract TreasuryActionManager is Ownable {

    event ActionApproved(address indexed _action);
    event ActionUnapproved(address indexed _action);

    // Mapping to store approved action contract addresses
    mapping (address _action => bool _approved) public approvedActions;

    /**
     * Sets the contract owner.
     * 设置合约所有者。
     * @dev This contract should be created in the {PositionManager} constructor call.
     */
    constructor (address _protocolOwner) {
        _initializeOwner(_protocolOwner);
    }

    /**
     * Approves an action contract.
     * 批准一个操作合约。
     * @param _action {ITreasuryAction} contract address
     */
    function approveAction(address _action) external onlyOwner {
        approvedActions[_action] = true;
        emit ActionApproved(_action);
    }

    /**
     * Remove an action contract from approval.
     * 移除一个操作合约的批准。
     * @param _action {ITreasuryAction} contract address
     */
    function unapproveAction(address _action) external onlyOwner {
        approvedActions[_action] = false;
        emit ActionUnapproved(_action);
    }

    /**
     * Override to return true to make `_initializeOwner` prevent double-initialization.
     * 重写以返回true，使`_initializeOwner`防止双重初始化。
     * @return bool Set to `true` to prevent owner being reinitialized.
     */
    function _guardInitializeOwner() internal pure override returns (bool) {
        return true;
    }

}
