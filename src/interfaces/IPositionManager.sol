// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IFeeCalculator} from '@flaunch-interfaces/IFeeCalculator.sol';
import {FairLaunch} from '@flaunch/hooks/FairLaunch.sol';

interface IPositionManager {
    function fairLaunch() external view returns (FairLaunch);
    function getFeeCalculator(
        bool _isFairLaunch
    ) external view returns (IFeeCalculator);
}
