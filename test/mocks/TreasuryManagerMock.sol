// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TreasuryManager} from '@flaunch/treasury/managers/TreasuryManager.sol';

contract TreasuryManagerMock is TreasuryManager {
    constructor(
        address _treasuryManagerFactory,
        address _feeEscrowRegistry
    ) TreasuryManager(_treasuryManagerFactory, _feeEscrowRegistry) {}

    function _initialize(address _owner, bytes calldata) internal override {
        // ..
    }

    function claim() external pure returns (uint) {
        return 0;
    }

    function balances(
        address _recipient
    ) external pure returns (uint) {
        return 0;
    }
}
