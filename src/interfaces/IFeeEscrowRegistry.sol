// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IFeeEscrowRegistry {
    function feeEscrows() external view returns (address[] memory feeEscrows_);

    function isLegacy(
        address _feeEscrow
    ) external view returns (bool);

    function addFeeEscrow(address _feeEscrow, bool _isLegacy) external;

    function removeFeeEscrow(
        address _feeEscrow
    ) external;
}
