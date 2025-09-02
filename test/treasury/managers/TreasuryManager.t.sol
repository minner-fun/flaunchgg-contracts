// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ClosedPermissions} from '@flaunch/treasury/permissions/Closed.sol';
import {Flaunch} from '@flaunch/Flaunch.sol';
import {PositionManager} from '@flaunch/PositionManager.sol';
import {RevenueManager} from '@flaunch/treasury/managers/RevenueManager.sol';
import {TreasuryManager} from '@flaunch/treasury/managers/TreasuryManager.sol';
import {TreasuryManagerFactory} from '@flaunch/treasury/managers/TreasuryManagerFactory.sol';
import {WhitelistedPermissions} from '@flaunch/treasury/permissions/Whitelisted.sol';

import {ITreasuryManager} from '@flaunch-interfaces/ITreasuryManager.sol';
import {ITreasuryManagerFactory} from '@flaunch-interfaces/ITreasuryManagerFactory.sol';

import {FlaunchTest} from 'test/FlaunchTest.sol';


/**
 * Tests core TreasuryManager functionality, using the RevenueManager as an example.
 */
contract TreasuryManagerTest is FlaunchTest {

    /// Set our treasury manager contracts
    RevenueManager revenueManager;

    /// Set our permissions contracts
    address closedPermissions;
    address whitelistedPermissions;

    /// Define some useful testing addresses
    address payable internal owner = payable(address(0x123));

    function setUp() public {
        // Deploy our platform
        _deployPlatform();

        address managerImplementation = address(new RevenueManager(address(treasuryManagerFactory)));
        treasuryManagerFactory.approveManager(managerImplementation);

        // Deploy our {RevenueManager} implementation and initialize
        address payable implementation = treasuryManagerFactory.deployAndInitializeManager({
            _managerImplementation: managerImplementation,
            _owner: owner,
            _data: abi.encode(
                RevenueManager.InitializeParams(owner, 50_00)
            )
        });

        // Set our revenue manager
        revenueManager = RevenueManager(implementation);

        // Deploy our permissions contracts as the owner address
        vm.startPrank(owner);
        closedPermissions = address(new ClosedPermissions());
        whitelistedPermissions = address(new WhitelistedPermissions(ITreasuryManagerFactory(treasuryManagerFactory)));
        vm.stopPrank();

        // Confirm that the default permissions are set to open
        assertEq(address(revenueManager.permissions()), address(0));
    }

    function test_ManagerOwner_CanDepositWhenOpen() public {
        // Confirm that the owner can deposit a token without error
        _depositToken(owner, false);
    }

    function test_ManagerOwner_CanDepositWhenProtected() public {
        // Set the group permissions to protected
        _setPermissions(whitelistedPermissions);

        // Confirm that the owner can deposit a token without error
        _depositToken(owner, false);
    }

    function test_ManagerOwner_CanDepositWhenClosed() public {
        // Set the group permissions to closed
        _setPermissions(closedPermissions);

        // Confirm that the owner can deposit a token without error
        _depositToken(owner, false);
    }

    function test_Creator_CanDepositWhenOpen(address _caller, bool _approved) public {
        // Ensure that the caller is not the zero address
        vm.assume(_caller != address(0));

        // Approve our creator if the fuzzing requests it
        if (_approved) {
            _approveCreator(_caller);
        }

        // Confirm that a creator that is either approved or unapproved can deposit a
        // token without error.
        _depositToken(_caller, false);
    }

    function test_Creator_Whitelisted_CanDepositWhenProtected(address _caller) public {
        // Ensure that the caller is not the zero address
        vm.assume(_caller != address(0));

        // Approve our creator
        _approveCreator(_caller);

        // Set the group permissions to protected
        _setPermissions(whitelistedPermissions);

        // Confirm that an creator that is approved can deposit a token without error
        _depositToken(_caller, false);
    }

    function test_Creator_NotWhitelisted_CannotDepositWhenProtected(address _caller) public {
        // Ensure that the caller is not the owner, as this would bypass the approval requirement
        vm.assume(_caller != owner);

        // Ensure that the caller is not the zero address
        vm.assume(_caller != address(0));

        // Set the group permissions to protected
        _setPermissions(whitelistedPermissions);

        // Confirm that a creator that is not approved cannot deposit a token, and throws an error
        _depositToken(_caller, true);
    }

    function test_Creator_CannotApproveCreatorsIfNotManagerOwner(address _caller) public {
        // Ensure that the caller is not the owner
        vm.assume(_caller != owner);

        // Ensure that the caller is not the zero address
        vm.assume(_caller != address(0));

        // Build an array of creators to approve
        address[] memory _creators = new address[](3);
        _creators[0] = address(0x123);
        _creators[1] = address(0x456);
        _creators[2] = address(0x789);

        vm.startPrank(_caller);

        // We should be reverted when trying to set the approved creators with anyone other than
        // the approved manager owner address.
        vm.expectRevert(UNAUTHORIZED);
        WhitelistedPermissions(whitelistedPermissions).setApprovedCreators(address(revenueManager), _creators, true);

        vm.stopPrank();
    }

    function test_Creator_CannotDepositWhenClosed(address _caller, bool _approved) public {
        // Ensure that the caller is not the owner, as this would bypass the approval requirement
        vm.assume(_caller != owner);

        // Ensure that the caller is not the zero address
        vm.assume(_caller != address(0));

        // Approve our creator if the fuzzing requests it
        if (_approved) {
            _approveCreator(_caller);
        }

        // Set the group permissions to closed
        _setPermissions(closedPermissions);

        // Confirm that a creator that is either approved or unapproved cannot deposit a token, and
        // throws an error.
        _depositToken(_caller, true);

    }

    function test_CanSetPermissionsIfManagerOwner() public {
        _setPermissions(whitelistedPermissions);
        _setPermissions(closedPermissions);
        _setPermissions(address(0));
    }

    function test_CannotSetPermissionsIfNotManagerOwner(address _caller) public {
        // Ensure that the caller is not the owner
        vm.assume(_caller != owner);

        vm.startPrank(_caller);

        // We should be reverted when trying to set the group permissions with anyone other than
        // the approved manager owner address.
        vm.expectRevert(abi.encodeWithSelector(TreasuryManager.NotManagerOwner.selector, _caller));
        revenueManager.setPermissions(whitelistedPermissions);

        vm.stopPrank();
    }

    function test_CanSetApprovedCreatorsIfManagerOwner() public {
        // Set our group to protected, so that all of our creators aren't just returned
        // as valid.
        _setPermissions(whitelistedPermissions);

        // Build an array of creators to approve
        address[] memory _creators = new address[](3);
        _creators[0] = address(0x123);
        _creators[1] = address(0x456);
        _creators[2] = address(0x789);

        // Ensure that the creators are approved
        assertEq(revenueManager.isValidCreator(_creators[0], ''), true);
        assertEq(revenueManager.isValidCreator(_creators[1], ''), false);
        assertEq(revenueManager.isValidCreator(_creators[2], ''), false);

        // Ensure that the event is emitted
        vm.expectEmit();
        emit WhitelistedPermissions.ApprovedCreatorAdded(address(revenueManager), _creators[0]);
        emit WhitelistedPermissions.ApprovedCreatorAdded(address(revenueManager), _creators[1]);
        emit WhitelistedPermissions.ApprovedCreatorAdded(address(revenueManager), _creators[2]);

        // Set the approved creators
        vm.prank(owner, owner);
        WhitelistedPermissions(whitelistedPermissions).setApprovedCreators(address(revenueManager), _creators, true);

        // Ensure that the creators are approved
        assertEq(revenueManager.isValidCreator(_creators[0], ''), true);
        assertEq(revenueManager.isValidCreator(_creators[1], ''), true);
        assertEq(revenueManager.isValidCreator(_creators[2], ''), true);

        // Test some creators that were not approved
        assertEq(revenueManager.isValidCreator(address(0xAAA), ''), false);
        assertEq(revenueManager.isValidCreator(address(0xBBB), ''), false);
        assertEq(revenueManager.isValidCreator(address(0xCCC), ''), false);

        // We can now remove some of the creators
        vm.expectEmit();
        emit WhitelistedPermissions.ApprovedCreatorRemoved(address(revenueManager), _creators[0]);
        emit WhitelistedPermissions.ApprovedCreatorRemoved(address(revenueManager), _creators[1]);
        emit WhitelistedPermissions.ApprovedCreatorRemoved(address(revenueManager), _creators[2]);

        // Remove the creators
        vm.prank(owner, owner);
        WhitelistedPermissions(whitelistedPermissions).setApprovedCreators(address(revenueManager), _creators, false);

        // Ensure that the creators are not approved
        assertEq(revenueManager.isValidCreator(_creators[0], ''), true);
        assertEq(revenueManager.isValidCreator(_creators[1], ''), false);
        assertEq(revenueManager.isValidCreator(_creators[2], ''), false);
    }

    function test_CannotSetApprovedCreatorsIfNotManagerOwner(address _caller) public {
        // Ensure that the caller is not the owner
        vm.assume(_caller != owner);

        vm.startPrank(_caller);

        // Build an array of creators to approve
        address[] memory _creators = new address[](3);
        _creators[0] = address(0x123);
        _creators[1] = address(0x456);
        _creators[2] = address(0x789);

        // We should be reverted when trying to set the approved creators with anyone other than
        // the approved manager owner address.
        vm.expectRevert(UNAUTHORIZED);
        WhitelistedPermissions(whitelistedPermissions).setApprovedCreators(address(revenueManager), _creators, true);

        vm.stopPrank();
    }

    function test_Creator_CannotDepositOnBehalfOfApprovedCreator(address _approvedCreator, address _caller) public {
        // Ensure that the caller is not the zero address
        vm.assume(_caller != address(0));
        vm.assume(_approvedCreator != address(0));

        // Ensure that the caller is not the approved creator
        vm.assume(_caller != _approvedCreator);

        // Approve our creator
        _approveCreator(_approvedCreator);

        // Set the group permissions to protected
        _setPermissions(whitelistedPermissions);

        // Confirm that a creator that is approved cannot deposit a token, and throws an error
        vm.startPrank(_caller);

        uint tokenId = _createERC721(_caller);
        flaunch.approve(address(revenueManager), tokenId);

        vm.expectRevert(abi.encodeWithSelector(TreasuryManager.InvalidCreator.selector, _caller));
        revenueManager.deposit({
            _flaunchToken: ITreasuryManager.FlaunchToken(flaunch, tokenId),
            _creator: _approvedCreator,
            _data: abi.encode('')
        });

        vm.stopPrank();
    }

    function test_Owner_CanDepositApprovedTokenWithAnyPermissions() public {
        // Set the group permissions to closed
        _setPermissions(closedPermissions);

        // Flaunch a token as a third party, non-approved creator
        address creator = address(0x1234567890);
        vm.startPrank(creator);

        uint tokenId = _createERC721(creator);
        flaunch.approve(address(revenueManager), tokenId);

        // Confirm that we cannot deposit the token as the creator
        vm.expectRevert(abi.encodeWithSelector(TreasuryManager.InvalidCreator.selector, creator));
        revenueManager.deposit({
            _flaunchToken: ITreasuryManager.FlaunchToken(flaunch, tokenId),
            _creator: creator,
            _data: abi.encode('')
        });

        vm.stopPrank();

        // However, we can now deposit the token as the owner as it is approved to be deposited
        // by the creator and the owner bypasses the `isValidCreator` check in the permissions contract.
        vm.startPrank(owner, owner);
        revenueManager.deposit({
            _flaunchToken: ITreasuryManager.FlaunchToken(flaunch, tokenId),
            _creator: creator,
            _data: abi.encode('')
        });
        vm.stopPrank();
    }

    function _setPermissions(address _permissions) internal {
        vm.startPrank(owner);

        // Ensure that the event is emitted
        vm.expectEmit();
        emit TreasuryManager.PermissionsUpdated(_permissions);

        // Set the permission for the group
        revenueManager.setPermissions(_permissions);

        // Ensure that the permissions are set correctly
        assertEq(address(revenueManager.permissions()), _permissions);

        vm.stopPrank();
    }

    function _approveCreator(address _creator) internal {
        vm.startPrank(owner);

        // Set the approved creator
        address[] memory _creators = new address[](1);
        _creators[0] = _creator;
        WhitelistedPermissions(whitelistedPermissions).setApprovedCreators(address(revenueManager), _creators, true);

        vm.stopPrank();
    }

    function _createERC721(address _recipient) internal returns (uint tokenId_) {
        // Flaunch another memecoin to mint a tokenId
        address memecoin = positionManager.flaunch(
            PositionManager.FlaunchParams({
                name: 'Token Name',
                symbol: 'TOKEN',
                tokenUri: 'https://flaunch.gg/',
                initialTokenFairLaunch: supplyShare(50),
                fairLaunchDuration: 30 minutes,
                premineAmount: 0,
                creator: _recipient,
                creatorFeeAllocation: 0,
                flaunchAt: 0,
                initialPriceParams: abi.encode(''),
                feeCalculatorParams: abi.encode(1_000)
            })
        );

        // Get the tokenId from the memecoin address
        return flaunch.tokenId(memecoin);
    }

    function _depositToken(address _creator, bool _expectError) internal returns (uint tokenId_) {
        // Set the `msg.sender` and `tx.origin` to the creator
        vm.startPrank(_creator, _creator);

        // Flaunch another memecoin to mint a tokenId
        tokenId_ = _createERC721(_creator);
        flaunch.approve(address(revenueManager), tokenId_);

        if (_expectError) {
            vm.expectRevert(abi.encodeWithSelector(TreasuryManager.InvalidCreator.selector, _creator));
        }

        // Deposit each of our tokens to a range of user EOAs
        revenueManager.deposit({
            _flaunchToken: ITreasuryManager.FlaunchToken(flaunch, tokenId_),
            _creator: _creator,
            _data: abi.encode('')
        });

        vm.stopPrank();
    }

}
