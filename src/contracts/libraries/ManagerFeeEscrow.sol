// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from '@uniswap/v4-core/src/types/PoolId.sol';

import {IFeeEscrow} from '@flaunch-interfaces/IFeeEscrow.sol';
import {IFeeEscrowRegistry} from '@flaunch-interfaces/IFeeEscrowRegistry.sol';
import {ITreasuryManager} from '@flaunch-interfaces/ITreasuryManager.sol';

/**
 * Library that provides functionality for managing fee escrows.
 */
library ManagerFeeEscrow {
    /**
     * Checks if the specified address is a valid fee escrow.
     *
     * @param _address The address to check
     *
     * @return isFeeEscrow_ True if the address is a valid fee escrow, false otherwise
     * @return isLegacy_ True if the address is a legacy fee escrow, false otherwise
     */
    function isFeeEscrow(
        address _address
    ) internal view returns (bool isFeeEscrow_, bool isLegacy_) {
        // Get the list of all valid {FeeEscrow} contracts
        address[] memory feeEscrows = ITreasuryManager(address(this)).feeEscrowRegistry().feeEscrows();

        // Iterate over all valid {FeeEscrow} contracts and check if the specified address is a valid fee escrow
        for (uint i; i < feeEscrows.length; ++i) {
            // If the specified address is a valid fee escrow, then return true
            if (_address == feeEscrows[i]) {
                return (true, ITreasuryManager(address(this)).feeEscrowRegistry().isLegacy(feeEscrows[i]));
            }
        }

        // If the specified address is not a valid fee escrow, then return false
        return (false, false);
    }

    /**
     * Returns the balance of the specified manager from all valid fee escrows.
     *
     * @param _manager The manager to check the balance of
     *
     * @return balance_ The balance of the specified manager from all valid fee escrows
     */
    function feeEscrowBalance(
        address _manager
    ) internal view returns (uint balance_) {
        // Get the list of all valid {FeeEscrow} contracts
        address[] memory feeEscrows = ITreasuryManager(address(this)).feeEscrowRegistry().feeEscrows();

        // Iterate over all valid {FeeEscrow} contracts and sum the balance of the specified manager address
        for (uint i; i < feeEscrows.length; ++i) {
            balance_ += IFeeEscrow(feeEscrows[i]).balances(_manager);
        }
    }

    /**
     * Returns the total fees allocated to the specified pool from all valid fee escrows.
     *
     * @param _poolId The pool to check the total fees of
     *
     * @return balance_ The total fees allocated to the specified pool from all valid fee escrows
     */
    function totalPoolFees(
        PoolId _poolId
    ) internal view returns (uint balance_) {
        // Get the {FeeEscrowRegistry} contract
        IFeeEscrowRegistry feeEscrowRegistry = ITreasuryManager(address(this)).feeEscrowRegistry();

        // Get the list of all valid {FeeEscrow} contracts
        address[] memory feeEscrows = feeEscrowRegistry.feeEscrows();

        // Iterate over all valid {FeeEscrow} contracts and sum the total fees allocated to the specified pool
        for (uint i; i < feeEscrows.length; ++i) {
            // If we have a legacy {FeeEscrow}, then we cannot use the `totalFeesAllocated` function, so we therefore
            // cannot allocate fees
            // to a pool specifically. For this reason, we need to bypass this and return 0.
            if (feeEscrowRegistry.isLegacy(feeEscrows[i])) {
                continue;
            }

            // Otherwise, we can sum the total fees allocated to the specified pool
            balance_ += IFeeEscrow(feeEscrows[i]).totalFeesAllocated(_poolId);
        }
    }
}
