// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {BalanceDelta} from '@uniswap/v4-core/src/types/BalanceDelta.sol';

import {PoolId, PoolIdLibrary} from '@uniswap/v4-core/src/types/PoolId.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';

import {IFeeCalculator} from '@flaunch-interfaces/IFeeCalculator.sol';
import {IPositionManager} from '@flaunch-interfaces/IPositionManager.sol';
import {FairLaunch} from '@flaunch/hooks/FairLaunch.sol';

/**
 * This implementation of the {IFeeCalculator} just returns the same base swapFee that
 * is assinged in the FeeDistribution struct.
 */
contract StaticFeeCalculator is IFeeCalculator {
    using PoolIdLibrary for PoolKey;

    /**
     * For a static value we simply return the `_baseFee` that was passed in with no
     * additional multipliers or calculations.
     *
     * @param _baseFee The base swap fee
     *
     * @return swapFee_ The calculated swap fee to use
     */
    function determineSwapFee(
        PoolKey memory, /* _poolKey */
        IPoolManager.SwapParams memory, /* _params */
        uint24 _baseFee
    ) public pure returns (uint24 swapFee_) {
        return _baseFee;
    }

    /**
     * Tracks information regarding ongoing swaps for pools. For post-fair launch swaps,
     * we need to verify that the fair launch verification was properly handled.
     *
     * @dev This function will only be called by the PositionManager if the fair launch
     * has ended.
     *
     * @param _sender The address of the sender of the swap
     * @param _poolKey The pool key of the pool that was swapped
     * @param _params The parameters of the swap
     * @param _delta The balance delta of the swap
     * @param _hookData The hook data of the swap
     */
    function trackSwap(
        address _sender,
        PoolKey calldata _poolKey,
        IPoolManager.SwapParams calldata _params,
        BalanceDelta _delta,
        bytes calldata _hookData
    ) public {
        // Get the fair launch information for the pool
        PoolId poolId = _poolKey.toId();

        // Get the PositionManager instance
        IPositionManager positionManager = IPositionManager(msg.sender);

        // Get the fair launch information to check if it ended at the current block timestamp
        FairLaunch.FairLaunchInfo memory fairLaunchInfo = positionManager.fairLaunch().fairLaunchInfo(poolId);

        // If the fair launch ended at the same timestamp as the current block, we need to
        // verify the transaction using the fair launch calculator
        if (fairLaunchInfo.endsAt == block.timestamp) {
            // Get the Fair Launch calculator from the PositionManager
            IFeeCalculator fairLaunchCalculator = positionManager.getFeeCalculator(true);

            // Call trackSwap against this calculator with the same parameters to ensure
            // that we pass verifications
            if (address(fairLaunchCalculator) != address(0) && address(fairLaunchCalculator) != address(this)) {
                fairLaunchCalculator.trackSwap(_sender, _poolKey, _params, _delta, _hookData);
            }
        }
    }

    /**
     * We don't need any specific Flaunch parameters to be assigned to this calculator, so we
     * can just provide empty logic.
     */
    function setFlaunchParams(PoolId _poolId, bytes calldata _params) external override {
        // ..
    }
}
