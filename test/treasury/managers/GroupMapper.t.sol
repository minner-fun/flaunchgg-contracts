// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {GroupMapper} from '@flaunch/treasury/managers/GroupMapper.sol';
import {TreasuryManagerFactory} from '@flaunch/treasury/managers/TreasuryManagerFactory.sol';
import {TreasuryManagerMock} from 'test/mocks/TreasuryManagerMock.sol';

import {IManagerPermissions} from '@flaunch-interfaces/IManagerPermissions.sol';
import {ITreasuryManager} from '@flaunch-interfaces/ITreasuryManager.sol';
import {ITreasuryManagerFactory} from '@flaunch-interfaces/ITreasuryManagerFactory.sol';

import {FlaunchTest} from 'test/FlaunchTest.sol';


contract GroupMapperTest is FlaunchTest {

    address internal constant OWNER = address(0xA11CE);
    address internal constant NOT_OWNER = address(0xB0B);
    address internal constant STRANGER = address(0xBAD);
    uint internal constant TIMELOCK = 0;
    uint internal constant PARENT_SHARE = 1_00000; // 1%

    address internal parent;
    address internal child;
    GroupMapper internal groupMapper;
    TreasuryManagerMock internal managerMockImplementation;

    function setUp() public {
        _deployPlatform();

        // Deploy the mock implementation and approve it in the {TreasuryManagerFactory}
        managerMockImplementation = new TreasuryManagerMock(address(treasuryManagerFactory));    
        treasuryManagerFactory.approveManager(address(managerMockImplementation));
        
        // Set up our managers with the `OWNER` as the `managerOwner` for both mocks
        parent = treasuryManagerFactory.deployAndInitializeManager(address(managerMockImplementation), OWNER, '');
        child = treasuryManagerFactory.deployAndInitializeManager(address(managerMockImplementation), OWNER, '');

        // Set up our {GroupMapper} contract to manager the hierarchy of managers
        groupMapper = new GroupMapper(ITreasuryManagerFactory(address(treasuryManagerFactory)));
    }

    function test_CanDeposit() public {
        // Only owner can deposit
        vm.startPrank(OWNER);

        // User must first transfer ownership of the child manager to the GroupMapper contract
        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));

        // Confirm that the `managerOwner` of the child is now the {GroupMapper}, but that the GroupChild data
        // is not yet set.
        assertEq(ITreasuryManager(child).managerOwner(), address(groupMapper));

        (address _parent, address _owner, uint _timelock, uint _parentShare, bool _finalized) = groupMapper.childGroups(child);
        assertEq(_parent, address(0));
        assertEq(_owner, address(0));
        assertEq(_timelock, 0);
        assertEq(_parentShare, 0);
        assertEq(_finalized, false);

        // Deposit the child group into the group mapper
        vm.expectEmit();
        emit GroupMapper.Deposited(child, OWNER, parent, TIMELOCK, PARENT_SHARE);
        groupMapper.deposit(child, parent, TIMELOCK, PARENT_SHARE);
        
        // Check that the child group is now deposited in the group mapper
        (_parent, _owner, _timelock, _parentShare, _finalized) = groupMapper.childGroups(child);
        assertEq(_parent, parent);
        assertEq(_owner, OWNER);
        assertEq(_timelock, TIMELOCK);
        assertEq(_parentShare, PARENT_SHARE);
        assertEq(_finalized, false);

        // Check that the child group is now a child of the parent group
        address[] memory childrenArr = groupMapper.children(parent);
        assertEq(childrenArr.length, 0);
        
        // Check that the `managerOwner` of the child is still the {GroupMapper}
        assertEq(ITreasuryManager(child).managerOwner(), address(groupMapper));
        vm.stopPrank();
    }

    function test_CannotDepositWithInvalidParent() public {
        vm.startPrank(OWNER);

        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));
        
        vm.expectRevert(GroupMapper.InvalidParent.selector);
        groupMapper.deposit(child, child, TIMELOCK, PARENT_SHARE);
        
        vm.stopPrank();
    }

    function test_CannotDepositWithInvalidParentShare(uint _invalidParentShare) public {
        // Ensure that the parent share is invalid
        vm.assume(_invalidParentShare < groupMapper.MIN_PARENT_SHARE() || _invalidParentShare > groupMapper.MAX_PARENT_SHARE());

        vm.startPrank(OWNER);

        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));
        
        vm.expectRevert(GroupMapper.InvalidParentShare.selector);
        groupMapper.deposit(child, parent, TIMELOCK, _invalidParentShare);
        
        vm.stopPrank();
    }

    function test_CannotDepositWithInvalidGroupImplementation() public {
        // Unapproved child implementation
        address fakeChild = address(0x1234);
        
        vm.startPrank(OWNER);

        // Simulate transfer of ownership (not needed for fakeChild, but for completeness)
        vm.expectRevert(GroupMapper.InvalidGroupImplementation.selector);
        groupMapper.deposit(fakeChild, parent, TIMELOCK, PARENT_SHARE);

        vm.stopPrank();
    }

    function test_CannotDepositWithNotManagerOwner() public {
        // Do NOT transfer manager ownership to GroupMapper
        vm.startPrank(OWNER);

        // GroupMapper is not the manager owner, so should revert
        vm.expectRevert(GroupMapper.NotManagerOwner.selector);
        groupMapper.deposit(child, parent, TIMELOCK, PARENT_SHARE);

        vm.stopPrank();
    }

    function test_CannotDepositWithGroupAlreadyDeposited() public {
        vm.startPrank(OWNER);

        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));
        
        groupMapper.deposit(child, parent, TIMELOCK, PARENT_SHARE);
        
        // Try to deposit again
        vm.expectRevert(GroupMapper.GroupAlreadyDeposited.selector);
        groupMapper.deposit(child, parent, TIMELOCK, PARENT_SHARE);
        
        vm.stopPrank();
    }

    function test_CanWithdraw() public {
        // Deposit first
        vm.startPrank(OWNER);

        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));
        
        groupMapper.deposit(child, parent, TIMELOCK, PARENT_SHARE);
        groupMapper.finalize(child);

        // Confirm state before withdrawal
        (address _parent, address _owner, uint _timelock, uint _parentShare, bool _finalized) = groupMapper.childGroups(child);
        assertEq(_parent, parent);
        assertEq(_owner, OWNER);
        assertEq(_timelock, TIMELOCK);
        assertEq(_parentShare, PARENT_SHARE);
        assertEq(_finalized, true);

        address[] memory childrenBefore = groupMapper.children(parent);
        assertEq(childrenBefore.length, 1);
        assertEq(childrenBefore[0], child);
        assertEq(ITreasuryManager(child).managerOwner(), address(groupMapper));

        // Withdraw
        vm.expectEmit();
        emit GroupMapper.Withdrawn(child, OWNER, parent);
        groupMapper.withdraw(child);

        // Confirm state after withdrawal
        (_parent, _owner, _timelock, _parentShare, _finalized) = groupMapper.childGroups(child);
        assertEq(_parent, address(0));
        assertEq(_owner, address(0));
        assertEq(_timelock, 0);
        assertEq(_parentShare, 0);
        assertEq(_finalized, false);

        address[] memory childrenAfter = groupMapper.children(parent);
        assertEq(childrenAfter.length, 0);
        
        // Ownership returned to original owner
        assertEq(ITreasuryManager(child).managerOwner(), OWNER);
        
        vm.stopPrank();
    }

    function test_CannotWithdrawWithNotDeposited() public {
        // Confirm not deposited
        (address _parent, address _owner, uint _timelock, uint _parentShare, bool _finalized) = groupMapper.childGroups(child);
        assertEq(_parent, address(0));
        assertEq(_owner, address(0));
        assertEq(_timelock, 0);
        assertEq(_parentShare, 0);
        assertEq(_finalized, false);

        // Attempt withdrawal
        vm.startPrank(OWNER);

        vm.expectRevert(GroupMapper.GroupNotDeposited.selector);
        groupMapper.withdraw(child);

        vm.stopPrank();
    }

    function test_CannotWithdrawWithNotOriginalOwner() public {
        // Deposit as owner
        vm.startPrank(OWNER);

        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));
        
        groupMapper.deposit(child, parent, TIMELOCK, PARENT_SHARE);
        
        vm.stopPrank();
        
        // Confirm deposited
        (address _parent, address _owner, uint _timelock, uint _parentShare, bool _finalized) = groupMapper.childGroups(child);
        assertEq(_parent, parent);
        assertEq(_owner, OWNER);
        assertEq(_timelock, TIMELOCK);
        assertEq(_parentShare, PARENT_SHARE);
        assertEq(_finalized, false);

        // Attempt withdrawal as notOwner
        vm.startPrank(NOT_OWNER);

        vm.expectRevert(GroupMapper.NotOriginalOwner.selector);
        groupMapper.withdraw(child);

        vm.stopPrank();
    }

    function test_CannotWithdrawWithTimelockNotPassed(uint _futureTimelock) public {
        // Ensure that the future timelock is in the future
        vm.assume(_futureTimelock > block.timestamp);

        vm.startPrank(OWNER);

        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));
        
        groupMapper.deposit(child, parent, _futureTimelock, PARENT_SHARE);
        groupMapper.finalize(child);

        // Confirm deposited
        (address _parent, address _owner, uint _timelock, uint _parentShare, bool _finalized) = groupMapper.childGroups(child);
        assertEq(_parent, parent);
        assertEq(_owner, OWNER);
        assertEq(_timelock, _futureTimelock);
        assertEq(_parentShare, PARENT_SHARE);
        assertEq(_finalized, true);

        // Attempt withdrawal before timelock
        vm.expectRevert(GroupMapper.TimelockNotPassed.selector);
        groupMapper.withdraw(child);

        vm.stopPrank();
    }

    function test_CannotClaimWithNotDeposited() public {
        vm.expectRevert(GroupMapper.GroupNotDeposited.selector);
        groupMapper.claim(child);
    }

    function test_CanClaimWithNoFees() public {
        vm.startPrank(OWNER);

        // Transfer manager ownership to GroupMapper before deposit
        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));
        groupMapper.deposit(child, parent, TIMELOCK, PARENT_SHARE);

        // No fees to claim, but should not revert
        groupMapper.claim(child);

        vm.stopPrank();
    }

    function test_CanGetChildrenWhenEmpty() public view {
        address[] memory children = groupMapper.children(parent);
        assertEq(children.length, 0);
    }

    function test_CanGetChildrenAfterDepositAndWithdraw() public {
        vm.startPrank(OWNER);

        // Transfer manager ownership to GroupMapper before deposit
        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));
        groupMapper.deposit(child, parent, TIMELOCK, PARENT_SHARE);

        address[] memory children = groupMapper.children(parent);
        assertEq(children.length, 0);

        // Finalize
        groupMapper.finalize(child);
        children = groupMapper.children(parent);
        assertEq(children.length, 1);

        groupMapper.withdraw(child);
        children = groupMapper.children(parent);
        assertEq(children.length, 0);

        vm.stopPrank();
    }

    // Fee distribution logic: test _claimFeesToParent with ETH
    function test_CanDistributeFees() public {
        // Deploy the mock implementation and approve it in the {TreasuryManagerFactory}
        FeeMockManager feeMockManager = new FeeMockManager(OWNER);
        treasuryManagerFactory.approveManager(address(feeMockManager));
        
        // Set up our managers with the `OWNER` as the `managerOwner` for both mocks
        address feeChild = treasuryManagerFactory.deployAndInitializeManager(address(feeMockManager), OWNER, '');
        
        vm.startPrank(OWNER);

        // Transfer manager ownership to GroupMapper before deposit
        ITreasuryManager(feeChild).transferManagerOwnership(address(groupMapper));
        groupMapper.deposit(feeChild, parent, TIMELOCK, 75_00000); // 75% to parent

        // Send ETH to feeChild so claim() can forward it
        vm.deal(address(groupMapper), 0);
        vm.deal(feeChild, 1 ether);

        // Expect event
        vm.expectEmit();
        emit GroupMapper.Claimed(feeChild, parent, 0.75 ether, OWNER, 0.25 ether);

        // Call claim (should forward 0.75 ETH to parent, 0.25 ETH to owner)
        groupMapper.claim(feeChild);

        // Check balances
        assertEq(parent.balance, 0.75 ether);
        assertEq(OWNER.balance, 0.25 ether);

        vm.stopPrank();
    }

    function test_CannotDepositWithNotValidCreator() public {
        // Deploy NotValidCreatorMock for parent
        NotValidCreatorMock notValidParent = new NotValidCreatorMock(OWNER);
        treasuryManagerFactory.approveManager(address(notValidParent));
       
        // Try to deposit with parent that rejects creator
        vm.startPrank(OWNER);

        // Set up child as usual
        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));

        // Try to deposit with parent that rejects creator
        vm.expectRevert(GroupMapper.NotValidCreator.selector);
        groupMapper.deposit(child, address(notValidParent), TIMELOCK, PARENT_SHARE);
       
        vm.stopPrank();
    }

    function test_CannotWithdrawTwice() public {
        vm.startPrank(OWNER);
       
        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));
        groupMapper.deposit(child, parent, TIMELOCK, PARENT_SHARE);
        
        groupMapper.withdraw(child);
        
        // Try to withdraw again
        vm.expectRevert(GroupMapper.GroupNotDeposited.selector);
        groupMapper.withdraw(child);
        
        vm.stopPrank();
    }

    function test_CannotClaimAfterWithdraw() public {
        vm.startPrank(OWNER);
        
        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));
        groupMapper.deposit(child, parent, TIMELOCK, PARENT_SHARE);
        
        groupMapper.withdraw(child);
        
        // Try to claim after withdraw
        vm.expectRevert(GroupMapper.GroupNotDeposited.selector);
        groupMapper.claim(child);
        
        vm.stopPrank();
    }

    function test_ReceiveETH(uint _amount) public {
        // Provide enough ETH to this contract to cover the test
        deal(address(this), _amount);

        // Send ETH directly to GroupMapper
        (bool sent,) = address(groupMapper).call{value: _amount}('');
        assertTrue(sent);

        // Check contract balance
        assertEq(address(groupMapper).balance, _amount);
    }

    function test_CanDepositAndFinalize() public {
        vm.startPrank(OWNER);
        
        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));
        
        groupMapper.deposit(child, parent, TIMELOCK, PARENT_SHARE);
        
        // State after deposit, before finalize
        (address _parent, address _owner, uint _timelock, uint _parentShare, bool _finalized) = groupMapper.childGroups(child);
        assertEq(_parent, parent);
        assertEq(_owner, OWNER);
        assertEq(_timelock, TIMELOCK);
        assertEq(_parentShare, PARENT_SHARE);
        assertEq(_finalized, false);
        
        address[] memory childrenArr = groupMapper.children(parent);
        assertEq(childrenArr.length, 0); // Not added until finalize
        
        // Finalize
        vm.expectEmit();
        emit GroupMapper.DepositFinalized(child);
        groupMapper.finalize(child);
        
        // State after finalize
        (, , , , _finalized) = groupMapper.childGroups(child);
        assertEq(_finalized, true);
        
        childrenArr = groupMapper.children(parent);
        
        assertEq(childrenArr.length, 1);
        assertEq(childrenArr[0], child);
        
        vm.stopPrank();
    }

    function test_CannotFinalizeTwice() public {
        vm.startPrank(OWNER);
        
        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));
        
        groupMapper.deposit(child, parent, TIMELOCK, PARENT_SHARE);
        groupMapper.finalize(child);
        
        // Try to finalize again
        vm.expectRevert(GroupMapper.GroupAlreadyFinalized.selector);
        groupMapper.finalize(child);
        
        vm.stopPrank();
    }

    function test_CanWithdrawBeforeFinalize() public {
        vm.startPrank(OWNER);
        
        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));
        
        groupMapper.deposit(child, parent, TIMELOCK, PARENT_SHARE);
        
        // Try to withdraw before finalize
        vm.expectEmit();
        emit GroupMapper.DepositCancelled(child, OWNER, parent);
        groupMapper.withdraw(child);
        
        vm.stopPrank();
    }

    function test_CanWithdrawAfterFinalize() public {
        vm.startPrank(OWNER);
        
        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));
        
        groupMapper.deposit(child, parent, TIMELOCK, PARENT_SHARE);
        groupMapper.finalize(child);
        
        // Now withdraw should succeed
        vm.expectEmit();
        emit GroupMapper.Withdrawn(child, OWNER, parent);
        groupMapper.withdraw(child);
        
        // State after withdrawal
        (address _parent, address _owner, uint _timelock, uint _parentShare, bool _finalized) = groupMapper.childGroups(child);
        assertEq(_parent, address(0));
        assertEq(_owner, address(0));
        assertEq(_timelock, 0);
        assertEq(_parentShare, 0);
        assertEq(_finalized, false);
        
        address[] memory childrenArr = groupMapper.children(parent);
        assertEq(childrenArr.length, 0);
        assertEq(ITreasuryManager(child).managerOwner(), OWNER);
        
        vm.stopPrank();
    }

    function test_CanClaimAfterFinalize() public {
        vm.startPrank(OWNER);
        
        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));
        
        groupMapper.deposit(child, parent, TIMELOCK, PARENT_SHARE);
        groupMapper.finalize(child);
        
        // No fees to claim, should return 0
        uint claimed = groupMapper.claim(child);
        assertEq(claimed, 0);
        
        vm.stopPrank();
    }

    function test_CanClaimBeforeFinalize() public {
        vm.startPrank(OWNER);

        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));
        
        groupMapper.deposit(child, parent, TIMELOCK, PARENT_SHARE);
        
        // Try to claim before finalize
        groupMapper.claim(child);
        
        vm.stopPrank();
    }

    function test_CanDistributeFees_ReturnsClaimed() public {
        // Deploy the mock implementation and approve it in the {TreasuryManagerFactory}
        FeeMockManager feeMockManager = new FeeMockManager(OWNER);
        treasuryManagerFactory.approveManager(address(feeMockManager));
        
        address feeChild = treasuryManagerFactory.deployAndInitializeManager(address(feeMockManager), OWNER, "");
        
        vm.startPrank(OWNER);
        
        ITreasuryManager(feeChild).transferManagerOwnership(address(groupMapper));
        
        groupMapper.deposit(feeChild, parent, TIMELOCK, 50_00000); // 50% to parent
        groupMapper.finalize(feeChild);
        
        // Send ETH to feeChild so claim() can forward it
        vm.deal(address(groupMapper), 0);
        vm.deal(feeChild, 1 ether);
        
        // Call claim and check return value
        uint claimed = groupMapper.claim(feeChild);
        assertEq(claimed, 1 ether);
        
        vm.stopPrank();
    }

    // --- claimAll tests ---
    function test_ClaimAll_NoGroups() public {
        // No groups deposited/finalized
        uint claimed = groupMapper.claimAll(parent);
        assertEq(claimed, 0);
    }

    function test_ClaimAll_OneGroup() public {
        // Set up one group with fees
        FeeMockManager feeMockManager = new FeeMockManager(OWNER);
        treasuryManagerFactory.approveManager(address(feeMockManager));
        
        address feeChild = treasuryManagerFactory.deployAndInitializeManager(address(feeMockManager), OWNER, "");
        
        vm.startPrank(OWNER);
        
        ITreasuryManager(feeChild).transferManagerOwnership(address(groupMapper));
        
        groupMapper.deposit(feeChild, parent, TIMELOCK, 50_00000);
        groupMapper.finalize(feeChild);
        
        vm.deal(address(groupMapper), 0);
        vm.deal(feeChild, 2 ether);
        
        // Call claimAll and check return value
        uint claimed = groupMapper.claimAll(parent);
        assertEq(claimed, 2 ether);
        
        // Check balances
        assertEq(payable(parent).balance, 1 ether);
        assertEq(payable(OWNER).balance, 1 ether);

        vm.stopPrank();
    }

    function test_ClaimAll_MultipleGroups() public {
        // Set up multiple groups with fees
        FeeMockManager feeMockManager = new FeeMockManager(OWNER);
        
        treasuryManagerFactory.approveManager(address(feeMockManager));
        
        address feeChild1 = treasuryManagerFactory.deployAndInitializeManager(address(feeMockManager), OWNER, "");
        address feeChild2 = treasuryManagerFactory.deployAndInitializeManager(address(feeMockManager), OWNER, "");
        
        vm.startPrank(OWNER);

        ITreasuryManager(feeChild1).transferManagerOwnership(address(groupMapper));
        ITreasuryManager(feeChild2).transferManagerOwnership(address(groupMapper));
        
        groupMapper.deposit(feeChild1, parent, TIMELOCK, 50_00000);
        groupMapper.deposit(feeChild2, parent, TIMELOCK, 50_00000);
        groupMapper.finalize(feeChild1);
        groupMapper.finalize(feeChild2);
        
        vm.deal(address(groupMapper), 0);
        vm.deal(feeChild1, 1 ether);
        vm.deal(feeChild2, 3 ether);
        
        // Call claimAll and check return value
        uint claimed = groupMapper.claimAll(parent);
        assertEq(claimed, 4 ether);
        
        // Check balances
        assertEq(payable(parent).balance, 2 ether);
        assertEq(payable(OWNER).balance, 2 ether);

        vm.stopPrank();
    }

    function test_CanCancelDepositBeforeFinalize() public {
        vm.startPrank(OWNER);
        
        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));
        
        groupMapper.deposit(child, parent, TIMELOCK, PARENT_SHARE);
        
        // Withdraw before finalize should emit DepositCancelled and remove group
        vm.expectEmit();
        emit GroupMapper.DepositCancelled(child, OWNER, parent);
        groupMapper.withdraw(child);
        
        // State after cancellation
        (address _parent, address _owner, uint _timelock, uint _parentShare, bool _finalized) = groupMapper.childGroups(child);
        assertEq(_parent, address(0));
        assertEq(_owner, address(0));
        assertEq(_timelock, 0);
        assertEq(_parentShare, 0);
        assertEq(_finalized, false);
        
        address[] memory childrenArr = groupMapper.children(parent);
        assertEq(childrenArr.length, 0);
        
        vm.stopPrank();
    }

    function test_CannotWithdrawAfterCancel() public {
        vm.startPrank(OWNER);
        
        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));
        
        groupMapper.deposit(child, parent, TIMELOCK, PARENT_SHARE);
        groupMapper.withdraw(child); // cancel
        
        // Try to withdraw again
        vm.expectRevert(GroupMapper.GroupNotDeposited.selector);
        groupMapper.withdraw(child);
        
        vm.stopPrank();
    }

    function test_CannotFinalizeAfterCancel() public {
        vm.startPrank(OWNER);
        
        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));
        
        groupMapper.deposit(child, parent, TIMELOCK, PARENT_SHARE);
        groupMapper.withdraw(child); // cancel
        
        // Try to finalize after cancel
        vm.expectRevert(GroupMapper.GroupNotDeposited.selector);
        groupMapper.finalize(child);
        
        vm.stopPrank();
    }

    function test_CannotClaimAfterCancel() public {
        vm.startPrank(OWNER);
        
        ITreasuryManager(child).transferManagerOwnership(address(groupMapper));
        
        groupMapper.deposit(child, parent, TIMELOCK, PARENT_SHARE);
        groupMapper.withdraw(child); // cancel
        
        // Try to claim after cancel
        vm.expectRevert(GroupMapper.GroupNotDeposited.selector);
        groupMapper.claim(child);
        
        vm.stopPrank();
    }
}

// Custom mock to simulate fee payout
contract FeeMockManager is ITreasuryManager {
    address public override managerOwner;
    constructor(address _owner) { managerOwner = _owner; }
    function initialize(address, bytes calldata) external {}
    function deposit(FlaunchToken calldata, address, bytes calldata) external {}
    function rescue(FlaunchToken calldata, address) external {}
    function isValidCreator(address, bytes calldata) external pure override returns (bool) { return true; }
    function transferManagerOwnership(address newOwner) external override { managerOwner = newOwner; }
    function balances(address) external pure override returns (uint) { return 0; }
    function claim() external override returns (uint) {
        // Send all ETH to caller (GroupMapper)
        uint bal = address(this).balance;
        if (bal > 0) {
            (bool sent,) = msg.sender.call{value: bal}('');
            require(sent, 'send fail');
        }
        return bal;
    }
    function permissions() external pure override returns (IManagerPermissions) { return IManagerPermissions(address(0)); }
    function setPermissions(address) external override {}
    receive() external payable {}
}

// Custom mock to simulate NotValidCreator
contract NotValidCreatorMock is ITreasuryManager {
    address public override managerOwner;
    constructor(address _owner) { managerOwner = _owner; }
    function initialize(address, bytes calldata) external {}
    function deposit(FlaunchToken calldata, address, bytes calldata) external {}
    function rescue(FlaunchToken calldata, address) external {}
    function isValidCreator(address, bytes calldata) external pure override returns (bool) { return false; }
    function transferManagerOwnership(address newOwner) external override { managerOwner = newOwner; }
    function balances(address) external pure override returns (uint) { return 0; }
    function claim() external pure override returns (uint) { return 0; }
    function permissions() external pure override returns (IManagerPermissions) { return IManagerPermissions(address(0)); }
    function setPermissions(address) external override {}
    receive() external payable {}
}
