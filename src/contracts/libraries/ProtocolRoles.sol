// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * Holds definitions for known `AccessControl` roles.
 */
library ProtocolRoles {
    bytes32 public constant FLAUNCH = keccak256('Flaunch'); // 协议
    bytes32 public constant NOTIFIER = keccak256('Notifier'); // 通知者
    bytes32 public constant POSITION_MANAGER = keccak256('PositionManager'); // 位置管理器
}
