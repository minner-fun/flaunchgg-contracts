// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import {PoolId} from '@uniswap/v4-core/src/types/PoolId.sol';

import {ProtocolRoles} from '@flaunch/libraries/ProtocolRoles.sol';
import {TreasuryManagerFactory} from '@flaunch/treasury/managers/TreasuryManagerFactory.sol';

import {IFeeEscrow} from '@flaunch-interfaces/IFeeEscrow.sol';
import {IFeeEscrowRegistry} from '@flaunch-interfaces/IFeeEscrowRegistry.sol';
import {ITreasuryManager} from '@flaunch-interfaces/ITreasuryManager.sol';
import {IManagerPermissions} from '@flaunch-interfaces/IManagerPermissions.sol';


/**
 * Acts as a middleware for revenue claims, allowing external protocols to build on top of Flaunch
 * and be able to have more granular control over the revenue yielded.
 */
abstract contract TreasuryManager is ITreasuryManager {

    using EnumerableSet for EnumerableSet.AddressSet;

    error AlreadyInitialized();
    error FlaunchContractNotValid();
    error InvalidCreator();
    error NotInitialized();
    error NotManagerOwner();
    error TokenTimelocked(uint _unlockedAt);
    error UnknownFlaunchToken();

    event ManagerOwnershipTransferred(address indexed _previousOwner, address indexed _newOwner);
    event PermissionsUpdated(address _permissions);
    event TreasuryEscrowed(address indexed _flaunch, uint indexed _tokenId, address _owner, address _sender);
    event TreasuryReclaimed(address indexed _flaunch, uint indexed _tokenId, address _sender, address _recipient);
    event TreasuryTimelocked(address indexed _flaunch, uint indexed _tokenId, uint _unlockedAt);

    /// The permissions contract for the group, defaulting to OPEN if a zero address
    IManagerPermissions public permissions;

    /// The whitelisted creators that can deposit tokens into the treasury manager
    EnumerableSet.AddressSet private _approvedCreators;

    /// The {TreasuryManagerFactory} that will launch this implementation
    TreasuryManagerFactory public immutable treasuryManagerFactory;

    /// The {FeeEscrowRegistry} that will be used to withdraw fees
    IFeeEscrowRegistry public immutable feeEscrowRegistry;

    /// The owner of the tokens that are depositted
    address public managerOwner;

    /// If the manager has been initialized
    bool public initialized;

    /// Creates a standardised timelock mechanism for tokens
    mapping (address _flaunch => mapping (uint _tokenId => uint _unlockedAt)) public tokenTimelock;

    /**
     * Sets up the contract with the initial required contract addresses.
     *
     * @param _treasuryManagerFactory The {TreasuryManagerFactory} that will launch this implementation
     */
    constructor (address _treasuryManagerFactory, address _feeEscrowRegistry) {
        feeEscrowRegistry = IFeeEscrowRegistry(_feeEscrowRegistry);
        treasuryManagerFactory = TreasuryManagerFactory(_treasuryManagerFactory);
    }

    /**
     * Initialize the manager contract.
     *
     * @param _owner The address to have ownership over the tokens
     * @param _data Additional manager initialization data
     */
    function initialize(address _owner, bytes calldata _data) public {
        // Check if the manager has already been initialized
        if (initialized) revert AlreadyInitialized();

        // Mark the manager as initialized
        initialized = true;

        // Set the owner of the manager
        managerOwner = _owner;

        // Allow the manager to perform additional logic
        _initialize(_owner, _data);
    }

    /**
     * Once the contract has been initialized, subsequent tokens should be sent via this function.
     * 一旦合约被初始化，后续的代币应该通过这个函数发送。
     * @param _flaunchToken The FlaunchToken being depositted
     * @param _creator The creator of the FlaunchToken
     * @param _data Additional deposit data for the manager
     */
    function deposit(FlaunchToken calldata _flaunchToken, address _creator, bytes calldata _data) public {
        // Check if the manager has been initialized 检查管理器是否已初始化
        if (!initialized) revert NotInitialized();

        // Validate the Flaunch contract
        if (!_isValidFlaunchContract(address(_flaunchToken.flaunch))) {
            revert FlaunchContractNotValid();
        }

        // Validate that the token can be deposited into by the caller
        if (!isValidCreator(msg.sender, _data)) {
            revert InvalidCreator();
        }

        // Transfer the token from the holder of the `FlaunchToken` to the contract. This will allow for approved tokens to
        // or tokens held by the caller to be deposited.
        _flaunchToken.flaunch.transferFrom({
            from: _flaunchToken.flaunch.ownerOf(_flaunchToken.tokenId),
            to: address(this),
            id: _flaunchToken.tokenId
        });

        emit TreasuryEscrowed(address(_flaunchToken.flaunch), _flaunchToken.tokenId, _creator, msg.sender);

        _deposit(_flaunchToken, _creator, _data);
    }

    /**
     * An internal initialization function that is overwritten by the managers that extend
     * this contract.
     *
     * @param _data Additional data bytes that can be unpacked
     */
    function _initialize(address _owner, bytes calldata _data) internal virtual {
        // ..
    }

    /**
     * An internal deposit function that is overwritten by the managers that extend this
     * contract.
     *
     * @param _flaunchToken The token to deposit
     * @param _creator The creator of the FlaunchToken
     * @param _data Additional data bytes that can be unpacked
     */
    function _deposit(FlaunchToken calldata _flaunchToken, address _creator, bytes calldata _data) internal virtual {
        // ..
    }

    /**
     * Rescues the ERC721, extracting it from the manager and transferring it to a recipient.
     *
     * @dev Only the owner can make this call.
     *
     * @param _flaunchToken The token to rescue
     * @param _recipient The recipient to receive the ERC721
     */
    function rescue(FlaunchToken calldata _flaunchToken, address _recipient) public virtual onlyManagerOwner {
        // Validate the Flaunch contract
        if (!_isValidFlaunchContract(address(_flaunchToken.flaunch))) {
            revert FlaunchContractNotValid();
        }

        // Ensure that the token is either not timelocked (zero value) or the timelock has passed
        uint unlockedAt = tokenTimelock[address(_flaunchToken.flaunch)][_flaunchToken.tokenId];
        if (block.timestamp < unlockedAt) {
            revert TokenTimelocked(unlockedAt);
        }

        // Remove the timelock on the token
        delete tokenTimelock[address(_flaunchToken.flaunch)][_flaunchToken.tokenId];

        // Transfer the token to the recipient from the contract. If the token is not held by
        // this contract then this call will revert.
        _flaunchToken.flaunch.transferFrom(address(this), _recipient, _flaunchToken.tokenId);

        emit TreasuryReclaimed(address(_flaunchToken.flaunch), _flaunchToken.tokenId, managerOwner, _recipient);
    }

    /**
     * Transfers ownership of the contract to a new account (`newOwner`).
     *
     * @dev Can only be called by the current owner.
     *
     * @param _newManagerOwner The new address that will become the owner
     */
    function transferManagerOwnership(address _newManagerOwner) public onlyManagerOwner {
        emit ManagerOwnershipTransferred(managerOwner, _newManagerOwner);
        managerOwner = _newManagerOwner;
    }

    /**
     * Checks if the specified address is a valid creator and can deposit tokens into the
     * treasury manager.
     *
     * @param _creator The address to check
     * @param _data Additional data bytes that can be unpacked
     *
     * @return `true` if the address is a valid creator, `false` otherwise
     */
    function isValidCreator(address _creator, bytes calldata _data) public view returns (bool) {
        // If the creator is the manager owner, then they are always valid
        if (_creator == managerOwner) {
            return true;
        }

        // If no permissions are set, then the creator is always valid
        if (address(permissions) == address(0)) {
            return true;
        }

        return permissions.isValidCreator(_creator, _data);
    }

    /**
     * Sets the deposit permissions contract for the treasury manager.
     *
     * @dev Only the manager owner can call this function.
     *
     * @param _permissions The new deposit permissions contract
     */
    function setPermissions(address _permissions) public onlyManagerOwner {
        permissions = IManagerPermissions(_permissions);
        emit PermissionsUpdated(_permissions);
    }

    /**
     * Checks if the specified address is a valid Flaunch contract.
     *
     * @param _flaunch The address to check
     *
     * @return `true` if the address is a valid Flaunch contract, `false` otherwise
     */
    function _isValidFlaunchContract(address _flaunch) internal view returns (bool) {
        return treasuryManagerFactory.hasRole(ProtocolRoles.FLAUNCH, _flaunch);
    }

    /**
     * Helper function to find the PoolId for a given FlaunchToken.
     *
     * @dev We cannot rely on the Flaunch contract to have the `poolId` function as this was introduced
     * in Flaunch 1.1. For this reason, we must manually apply the same helper function logic to determine it.
     *
     * @param _flaunchToken The FlaunchToken to find the PoolId for
     *
     * @return PoolId The PoolId for the FlaunchToken
     */
    function _getFlaunchTokenPoolId(FlaunchToken calldata _flaunchToken) internal view returns (PoolId) {
        return _flaunchToken.flaunch.positionManager().poolKey(_flaunchToken.flaunch.memecoin(_flaunchToken.tokenId)).toId();
    }

    /**
     * Withdraws fees from all known sources.
     *
     * @param _recipient The recipient of the fees
     * @param _unwrap If we want to unwrap the balance from flETH into ETH
     */
    function _withdrawAllFees(address _recipient, bool _unwrap) internal {
        address[] memory feeEscrows = feeEscrowRegistry.feeEscrows();
        for (uint i; i < feeEscrows.length; ++i) {
            IFeeEscrow(feeEscrows[i]).withdrawFees(_recipient, _unwrap);
        }
    }

    /**
     * Allows for protected calls that only the manager owner can make.
     */
    modifier onlyManagerOwner {
        if (msg.sender != managerOwner) {
            revert NotManagerOwner();
        }

        _;
    }

    /**
     * Allows the contract to receive ETH when withdrawn from the flETH token.
     */
    receive () external virtual payable {}

}
