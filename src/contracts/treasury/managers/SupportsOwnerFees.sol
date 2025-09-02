// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TreasuryManagerFactory} from '@flaunch/treasury/managers/TreasuryManagerFactory.sol';
import {FullMath} from '@uniswap/v4-core/src/libraries/FullMath.sol';


/**
 * Extends functionality to allow the manager to allocate fees to the manager owner.
 */
abstract contract SupportsOwnerFees {

    error OwnerShareAlreadyInitialized();
    error InvalidOwnerShare();

    event OwnerShareInitialized(uint _ownerShare);

    /// The valid share that the split must equal
    uint public constant MAX_OWNER_SHARE = 100_00000;

    /// The amount that a owner will receive before other recipients
    uint public ownerShare;

    /// The total fees that have been allocated to the owner
    uint internal _ownerFees;

    /// The total fees that have been claimed by the owner
    uint internal _claimedOwnerFees;

    /// Whether the owner share has been initialized
    bool internal _ownerShareInitialized;

    /// The {TreasuryManagerFactory} contract
    TreasuryManagerFactory internal immutable __treasuryManagerFactory;

    /**
     * Sets up the contract with the initial required contract addresses.
     *
     * @param treasuryManagerFactory The {TreasuryManagerFactory} that will launch this implementation
     */
    constructor (address treasuryManagerFactory) {
        __treasuryManagerFactory = TreasuryManagerFactory(treasuryManagerFactory);
    }

    /**
     * Validates and sets the owner share being set.
     *
     * @param _ownerShare The percentage that owners will receive from their fees (5dp)
     */
    function _setOwnerShare(uint _ownerShare) internal {
        // Ensure that the owner share has not already been initialized
        if (_ownerShareInitialized) {
            revert OwnerShareAlreadyInitialized();
        }

        // Ensure that the owner share is valid
        if (_ownerShare > MAX_OWNER_SHARE) {
            revert InvalidOwnerShare();
        }

        // Set the owner share and mark it as initialized
        ownerShare = _ownerShare;
        _ownerShareInitialized = true;

        // Emit the event that the owner share has been initialized
        emit OwnerShareInitialized(_ownerShare);
    }

    /**
     * Shows the amount of fees that are available to claim by the owner.
     *
     * @return uint The amount of ETH available to claim by the owner
     */
    function pendingOwnerFees() public view returns (uint) {
        return getOwnerFee(__treasuryManagerFactory.feeEscrow().balances(address(this)));
    }

    /**
     * Gets the total amount of fees allocated to the owner, including any fees that are pending
     * against the manager.
     *
     * @return uint The fees pending for the owner
     */
    function ownerFees() public view returns (uint) {
        return _ownerFees + pendingOwnerFees();
    }

    /**
     * Gets the amount of fees that are available to claim by the owner.
     *
     * @return uint The amount of ETH available to claim by the owner
     */
    function claimableOwnerFees() public view returns (uint) {
        return ownerFees() - _claimedOwnerFees;
    }

    /**
     * Calculates the protocol fee that will be taken from the amount passed in.

     * @dev This function will always return a rounded down value.
     * @dev Uses FullMath for overflow protection and precision.
     *
     * @param _amount The amount to calculate the owner fee from
     *
     * @return ownerFee_ The owner fee to be taken from the amount
     */
    function getOwnerFee(uint _amount) public view returns (uint ownerFee_) {
        // If the owner has no share, then we can exit early
        if (ownerShare == 0) {
            return 0;
        }

        return FullMath.mulDiv(_amount, ownerShare, MAX_OWNER_SHARE);
    }

}
