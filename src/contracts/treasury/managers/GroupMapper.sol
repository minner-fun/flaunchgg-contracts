// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import {ReentrancyGuardTransient} from '@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol';

import {ITreasuryManager} from '@flaunch-interfaces/ITreasuryManager.sol';
import {ITreasuryManagerFactory} from '@flaunch-interfaces/ITreasuryManagerFactory.sol';


/**
 * Allows for hierarchical group ownership and fee distribution among groups.
 *
 * The end user will need to undertake a 3 step process to deposit a group into the group mapper:
 * 1. `Deposit` the group into the group mapper
 * 2. Transfer ownership of the group to the group mapper (this contract)
 * 3. `Finalize` the deposit
 */
contract GroupMapper is ReentrancyGuardTransient {

    using EnumerableSet for EnumerableSet.AddressSet;

    error InvalidGroupImplementation();
    error InvalidParent();
    error InvalidParentShare();
    error GroupAlreadyDeposited();
    error GroupAlreadyFinalized();
    error GroupNotDeposited();
    error NotManagerOwner();
    error NotOriginalOwner();
    error NotValidCreator();
    error TimelockNotPassed();

    event Claimed(address indexed _child, address indexed _caller, uint _parentFees, address indexed _owner, uint _ownerFees);
    event Deposited(address indexed _child, address indexed _owner, address indexed _parent, uint _timelock, uint _parentShare);
    event DepositCancelled(address indexed _child, address indexed _owner, address indexed _parent);
    event DepositFinalized(address indexed _child);
    event Withdrawn(address indexed _child, address indexed _owner, address indexed _parent);

    /**
     * Data structure for a child group.
     *
     * @member parent The parent group of the child group
     * @member owner The owner of the child group
     * @member timelock The unix timestamp that the child group can be withdrawn (0 if no timelock)
     * @member parentShare The share of the fees that should go to the parent group (5dp)
     * @member finalized Whether the child group has been finalized by ownership transfer
     */
    struct ChildGroup {
        address parent;
        address owner;
        uint timelock;
        uint parentShare;
        bool finalized;
    }

    /// The minimum and maximum share that the parent group can take (5dp)
    uint public constant MIN_PARENT_SHARE = 1_00000;
    uint public constant MAX_PARENT_SHARE = 100_00000;

    /// Maps a group address to its group data
    mapping (address _group => ChildGroup _data) public childGroups;

    /// Maps a group address to a list of child groups
    mapping (address _parent => EnumerableSet.AddressSet _children) internal _childGroups;

    /// The factory contract that is used to create the groups
    ITreasuryManagerFactory public immutable treasuryManagerFactory;

    /**
     * Sets our required contract addresses.
     *
     * @param _treasuryManagerFactory The factory contract that defines TreasuryManager implementations.
     */
    constructor (ITreasuryManagerFactory _treasuryManagerFactory) {
        treasuryManagerFactory = _treasuryManagerFactory;
    }

    /**
     * Allow the group owner to deposit their group into the group mapper.
     *
     * @dev This function does not support group types not referenced by the {TreasuryManagerFactory}.
     *
     * @dev After the group has been deposited, the caller will then need to `transferManagerOwnership` to this contract. Once
     * this has been done, the group can be finalized by calling the `finalize` function.
     *
     * @param _child The child group to deposit
     * @param _parent The parent group to deposit the child group under
     * @param _timelock The timelock in seconds for the deposit
     * @param _parentShare The share of the fees that should go to the parent group (5dp)
     */
    function deposit(address _child, address _parent, uint _timelock, uint _parentShare) public {
        // Ensure that the parent group is not the same as the child group
        if (_parent == _child) {
            revert InvalidParent();
        }

        // Ensure that the parent share is a valid value
        if (_parentShare < MIN_PARENT_SHARE || _parentShare > MAX_PARENT_SHARE) {
            revert InvalidParentShare();
        }

        // Check if the group already exists
        if (childGroups[_child].parent != address(0)) {
            revert GroupAlreadyDeposited();
        }

        // Check that the child group is a recognised implementation
        if (treasuryManagerFactory.managerImplementation(_child) == address(0)) {
            revert InvalidGroupImplementation();
        }

        // Check that the caller is the `managerOwner` of the group
        if (msg.sender == ITreasuryManager(_child).managerOwner()) {
            revert NotManagerOwner();
        }

        // Check the permissions of the group to see if this creator can transfer it in
        if (!ITreasuryManager(_parent).isValidCreator(msg.sender, '')) {
            revert NotValidCreator();
        }

        // Store the child group data
        childGroups[_child] = ChildGroup({
            parent: _parent,
            owner: msg.sender,
            timelock: _timelock,
            parentShare: _parentShare,
            finalized: false
        });

        emit Deposited(_child, msg.sender, _parent, _timelock, _parentShare);
    }

    /**
     * Allows the original owner to remove their group ownership from the group.
     *
     * @dev Before the group is withdrawn, owner fees need to be claimed from the group and sent to the parent group
     *
     * @param _child The child group to withdraw
     */
    function withdraw(address _child) public {
        // Load our ChildGroup into storage
        ChildGroup storage childGroup = childGroups[_child];

        // Check that the group is deposited
        if (childGroup.parent == address(0)) {
            revert GroupNotDeposited();
        }

        // Check that the caller is the original owner
        if (childGroup.owner != msg.sender) {
            revert NotOriginalOwner();
        }

        // If the group has not been finalized, then we can immediately withdraw it without
        // any additional checks.
        if (!childGroup.finalized) {
            // Emit an event showing that we have cancelled the deposit flow
            emit DepositCancelled(_child, msg.sender, childGroup.parent);

            // Delete the child group from the group mapper
            delete childGroups[_child];
            return;
        }

        // Check that the timelock has passed if set
        if (childGroup.timelock != 0 && childGroup.timelock > block.timestamp) {
            revert TimelockNotPassed();
        }

        // Claim any outstanding fees for the parent group before transferring
        _claimFeesToParent(_child);

        // Transfer group ownership back to the original owner
        ITreasuryManager(_child).transferManagerOwnership(msg.sender);
        emit Withdrawn(_child, msg.sender, childGroup.parent);

        // Delete our mappings
        _childGroups[childGroup.parent].remove(_child);
        delete childGroups[_child];
    }

    /**
     * Returns the child groups of a parent group.
     *
     * @param _parent The parent group to get the child groups of
     *
     * @return The child groups of the parent group
     */
    function children(address _parent) public view returns (address[] memory) {
        return _childGroups[_parent].values();
    }

    /**
     * Allows the manager owner to finalize their deposit into the group mapper.
     *
     * @dev This function can only be called once the `deposit` function has been called and the caller has
     * `transferManagerOwnership`-ed to this contract. This function will then add the group to the parent
     * group's children and set the group to finalized.
     *
     * @param _child The child group to finalize
     */
    function finalize(address _child) public {
        // Load our ChildGroup into storage
        ChildGroup storage childGroup = childGroups[_child];

        // Check that the group is deposited
        if (childGroup.finalized) {
            revert GroupAlreadyFinalized();
        }

        // Check that the group exists by looking for a non-null parent
        if (childGroup.parent == address(0)) {
            revert GroupNotDeposited();
        }

        // Check that this contract is the manager owner
        if (address(this) != ITreasuryManager(_child).managerOwner()) {
            revert NotManagerOwner();
        }

        // Set the group to finalized
        childGroup.finalized = true;

        // Add the group to the parent group's children
        _childGroups[childGroup.parent].add(_child);

        emit DepositFinalized(_child);
    }

    /**
     * A public call allowing anyone to claim fees from the group and distribute them.
     *
     * @param _child The child group to claim fees from
     *
     * @return claimedFees_ The amount of fees claimed
     */
    function claim(address _child) public nonReentrant returns (uint claimedFees_) {
        // Check that the group is deposited
        if (childGroups[_child].parent == address(0)) {
            revert GroupNotDeposited();
        }

        // Claim any outstanding fees for the parent group
        claimedFees_ = _claimFeesToParent(_child);
    }

    /**
     * Allows the manager owner to claim fees from all their child groups.
     *
     * @return claimedFees_ The total amount of fees claimed
     */
    function claimAll(address _parent) public nonReentrant returns (uint claimedFees_) {
        // Get the child groups
        address[] memory _children = children(_parent);
        for (uint i = 0; i < _children.length; i++) {
            claimedFees_ += _claimFeesToParent(_children[i]);
        }
    }

    /**
     * Claims fees from the group and sends to the parent group.
     *
     * @param _child The child group to claim fees from
     *
     * @return claimedFees_ The amount of fees claimed
     */
    function _claimFeesToParent(address _child) internal returns (uint claimedFees_) {
        // Claim the fees into this contract and transfer them to the parent group
        uint startBalance = address(this).balance;
        ITreasuryManager(_child).claim();
        uint endBalance = address(this).balance;

        // If we have claimed fees, then we can transfer them to the parent group
        claimedFees_ = endBalance - startBalance;
        if (claimedFees_ != 0) {
            // Load our ChildGroup into memory
            ChildGroup memory childGroup = childGroups[_child];

            // Calculate the share of the fees that should go to the parent group and the owner
            uint parentFees = childGroup.parentShare * claimedFees_ / MAX_PARENT_SHARE;
            uint ownerFees = claimedFees_ - parentFees;

            // This direct ETH transfer will correctly allocate the fees to the parent group
            if (parentFees != 0) {
                payable(childGroup.parent).call{value: parentFees}('');
            }

            // The ETH allocation to the original owner will be added to the {FeeEscrow} contract
            if (ownerFees != 0) {
                payable(childGroup.owner).call{value: ownerFees}('');
            }

            emit Claimed(_child, childGroup.parent, parentFees, childGroup.owner, ownerFees);
        }
    }

    /**
     * Allows the contract to receive ETH from our owner claims.
     */
    receive() external payable {}

}
