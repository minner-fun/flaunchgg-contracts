// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FairLaunch} from '@flaunch/hooks/FairLaunch.sol';


interface IPositionManager {
    function fairLaunch() external view returns (FairLaunch);
}