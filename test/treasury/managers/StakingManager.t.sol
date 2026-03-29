// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from '@uniswap/v4-core/src/types/PoolId.sol';
import {ERC20Mock} from 'test/tokens/ERC20Mock.sol';

import {Flaunch} from '@flaunch/Flaunch.sol';
import {PositionManager} from '@flaunch/PositionManager.sol';
import {FeeEscrow} from '@flaunch/escrows/FeeEscrow.sol';
import {FeeEscrowRegistry} from '@flaunch/escrows/FeeEscrowRegistry.sol';
import {FeeSplitManager} from '@flaunch/treasury/managers/FeeSplitManager.sol';

import {StakingManager} from '@flaunch/treasury/managers/StakingManager.sol';
import {SupportsCreatorTokens} from '@flaunch/treasury/managers/SupportsCreatorTokens.sol';
import {SupportsOwnerFees} from '@flaunch/treasury/managers/SupportsOwnerFees.sol';
import {TreasuryManager} from '@flaunch/treasury/managers/TreasuryManager.sol';

import {ITreasuryManager} from '@flaunch-interfaces/ITreasuryManager.sol';

import {FlaunchTest} from 'test/FlaunchTest.sol';

contract StakingManagerTest is FlaunchTest {
    /// constants
    uint internal constant MAX_CREATOR_SHARE = 100_00000;
    uint internal constant MAX_OWNER_SHARE = 100_00000;
    uint internal constant VALID_TOTAL_SHARE = 100_00000;

    /// The staking manager
    StakingManager stakingManager;
    address managerImplementation;

    /// Store our flaunched tokenId
    uint tokenId;

    /// Define some helper addresses used during testing
    address payable owner = payable(address(123_000));
    address payable nonOwner = payable(address(456_000));

    address payable owner2 = payable(address(789_000));

    /// Set some default test parameters
    ERC20Mock stakingToken;
    uint minEscrowDuration = 30 days;
    uint minStakeDuration = 7 days;
    uint creatorShare = 10_00000;

    function setUp() public {
        // Deploy the Flaunch protocol
        _deployPlatform();

        // Deploy and approve our staking manager implementation
        managerImplementation = address(new StakingManager(address(treasuryManagerFactory), address(feeEscrowRegistry)));
        treasuryManagerFactory.approveManager(managerImplementation);

        // Deploy our {StakingManager} implementation
        vm.startPrank(owner);
        address payable implementation = treasuryManagerFactory.deployManager(managerImplementation);
        stakingManager = StakingManager(implementation);

        // Create a memecoin and approve the manager to take it
        tokenId = _createERC721(owner);
        flaunch.approve(address(stakingManager), tokenId);

        // Deploy a Token to stake for testing
        stakingToken = new ERC20Mock(owner);

        // Initialize a testing token
        stakingManager.initialize({
            _owner: owner,
            _data: abi.encode(
                StakingManager.InitializeParams(address(stakingToken), minEscrowDuration, minStakeDuration, creatorShare, 0)
            )
        });

        // deposit into the manager
        stakingManager.deposit({
            _flaunchToken: ITreasuryManager.FlaunchToken({flaunch: flaunch, tokenId: tokenId}),
            _creator: owner,
            _data: ''
        });

        vm.stopPrank();
    }

    /**
     * initialize
     */
    function test_CanInitializeSuccessfully(
        address _stakingToken,
        uint _minEscrowDuration,
        uint _minStakeDuration,
        uint _creatorShare
    ) public freshManager {
        // Ensure that the staking token is not a zero address
        vm.assume(_stakingToken != address(0));

        // Ensure that the creator split is valid
        vm.assume(_creatorShare <= MAX_CREATOR_SHARE);

        // Ensure that there's no overflow in tests when `escrowLockedUntil` is calculated
        vm.assume(_minEscrowDuration < type(uint).max - block.timestamp);

        // Create a memecoin and approve the manager to take it
        vm.startPrank(owner);
        uint newTokenId = _createERC721(owner);
        flaunch.approve(address(stakingManager), newTokenId);

        // Define our initialization parameters
        StakingManager.InitializeParams memory params = StakingManager.InitializeParams({
            stakingToken: _stakingToken,
            minEscrowDuration: _minEscrowDuration,
            minStakeDuration: _minStakeDuration,
            creatorShare: _creatorShare,
            ownerShare: 0
        });

        vm.expectEmit();
        emit StakingManager.ManagerInitialized(owner, params);

        // Initialize a testing token
        stakingManager.initialize({_owner: owner, _data: abi.encode(params)});

        vm.stopPrank();

        assertEq(address(stakingManager.stakingToken()), _stakingToken);
        assertEq(stakingManager.minEscrowDuration(), _minEscrowDuration);
        assertEq(stakingManager.minStakeDuration(), _minStakeDuration);
        assertEq(stakingManager.creatorShare(), _creatorShare);
        assertEq(stakingManager.ownerShare(), 0);
    }

    function test_CannotInitializeWithInvalidStakingToken() public freshManager {
        vm.startPrank(owner);
        vm.expectRevert(StakingManager.InvalidStakingToken.selector);
        stakingManager.initialize({
            _owner: owner,
            _data: abi.encode(
                StakingManager.InitializeParams(address(0), minEscrowDuration, minStakeDuration, creatorShare, 0)
            )
        });

        vm.stopPrank();
    }

    function test_CannotInitializeWithInvalidCreatorShare(
        uint _creatorShare
    ) public freshManager {
        // Ensure that the creator share is invalid
        vm.assume(_creatorShare > MAX_CREATOR_SHARE);

        // Create a memecoin and approve the manager to take it
        vm.startPrank(owner);
        uint newTokenId = _createERC721(owner);
        flaunch.approve(address(stakingManager), newTokenId);

        vm.expectRevert(SupportsCreatorTokens.InvalidCreatorShare.selector);
        stakingManager.initialize({
            _owner: owner,
            _data: abi.encode(
                StakingManager.InitializeParams(
                    address(stakingToken), minEscrowDuration, minStakeDuration, _creatorShare, 0
                )
            )
        });

        vm.stopPrank();
    }

    function test_CannotInitializeWithInvalidOwnerShare(
        uint _ownerShare
    ) public freshManager {
        // Ensure that the owner share is invalid
        vm.assume(_ownerShare > MAX_OWNER_SHARE);

        vm.startPrank(owner);
        vm.expectRevert(SupportsOwnerFees.InvalidOwnerShare.selector);
        stakingManager.initialize({
            _owner: owner,
            _data: abi.encode(
                StakingManager.InitializeParams(address(stakingToken), minEscrowDuration, minStakeDuration, 0, _ownerShare)
            )
        });
        vm.stopPrank();
    }

    function test_CannotInitializeWithInvalidShares(uint _creatorShare, uint _ownerShare) public freshManager {
        // Ensure that the combined shares are invalid
        _creatorShare = bound(_creatorShare, 0, MAX_CREATOR_SHARE);
        _ownerShare = bound(_ownerShare, 0, MAX_OWNER_SHARE);

        vm.assume(_creatorShare + _ownerShare > VALID_TOTAL_SHARE);

        vm.startPrank(owner);
        vm.expectRevert(FeeSplitManager.InvalidShareTotal.selector);
        stakingManager.initialize({
            _owner: owner,
            _data: abi.encode(
                StakingManager.InitializeParams(
                    address(stakingToken), minEscrowDuration, minStakeDuration, _creatorShare, _ownerShare
                )
            )
        });
        vm.stopPrank();
    }

    function test_CannotInitializeIfTokenIdAlreadySet() public {
        // Flaunch another memecoin to mint a tokenId
        uint newTokenId = _createERC721(address(this));

        // Deploy our {StakingManager} implementation and transfer our tokenId
        flaunch.approve(address(stakingManager), newTokenId);

        vm.expectRevert(TreasuryManager.AlreadyInitialized.selector);
        stakingManager.initialize({
            _owner: owner,
            _data: abi.encode(
                StakingManager.InitializeParams(address(stakingToken), minEscrowDuration, minStakeDuration, creatorShare, 0)
            )
        });
    }

    /**
     * deposit
     */
    function test_CanInitializeAndDepositSuccessfully(
        address _stakingToken,
        uint _minEscrowDuration,
        uint _minStakeDuration,
        uint _creatorShare
    ) public freshManager {
        // Ensure that the staking token is not a zero address
        vm.assume(_stakingToken != address(0));

        // Ensure that the creator split is valid
        vm.assume(_creatorShare <= MAX_CREATOR_SHARE);

        // Ensure that there's no overflow in tests when `escrowLockedUntil` is calculated
        vm.assume(_minEscrowDuration < type(uint).max - block.timestamp);

        // Create a memecoin and approve the manager to take it
        vm.startPrank(owner);
        uint newTokenId = _createERC721(owner);
        flaunch.approve(address(stakingManager), newTokenId);

        // Define our initialization parameters
        StakingManager.InitializeParams memory params = StakingManager.InitializeParams({
            stakingToken: _stakingToken,
            minEscrowDuration: _minEscrowDuration,
            minStakeDuration: _minStakeDuration,
            creatorShare: _creatorShare,
            ownerShare: 0
        });

        vm.expectEmit();
        emit StakingManager.ManagerInitialized(owner, params);

        // Initialize a testing token
        stakingManager.initialize({_owner: owner, _data: abi.encode(params)});

        // deposit into the manager
        stakingManager.deposit({
            _flaunchToken: ITreasuryManager.FlaunchToken({flaunch: flaunch, tokenId: newTokenId}),
            _creator: owner,
            _data: ''
        });

        vm.stopPrank();

        assertEq(stakingManager.creator(address(flaunch), newTokenId), owner);

        assertEq(address(stakingManager.stakingToken()), _stakingToken);
        assertEq(stakingManager.minEscrowDuration(), _minEscrowDuration);
        assertEq(stakingManager.minStakeDuration(), _minStakeDuration);
        assertEq(stakingManager.creatorShare(), _creatorShare);
        assertEq(stakingManager.tokenTimelock(address(flaunch), newTokenId), block.timestamp + _minEscrowDuration);
    }

    /**
     * escrowWithdraw
     */
    function test_CanEscrowWithdrawSuccessfully() public {
        vm.warp(stakingManager.tokenTimelock(address(flaunch), tokenId) + 1);

        vm.startPrank(owner);

        vm.expectEmit();
        emit TreasuryManager.TreasuryReclaimed(address(flaunch), tokenId, owner, owner);
        stakingManager.escrowWithdraw(ITreasuryManager.FlaunchToken({flaunch: flaunch, tokenId: tokenId}));

        vm.stopPrank();

        assertEq(flaunch.ownerOf(tokenId), owner);
    }

    function test_CannotEscrowWithdrawIfNotOwner() public {
        vm.warp(stakingManager.tokenTimelock(address(flaunch), tokenId) + 1);

        vm.startPrank(nonOwner);

        vm.expectRevert(SupportsCreatorTokens.InvalidCreatorAddress.selector);
        stakingManager.escrowWithdraw(ITreasuryManager.FlaunchToken({flaunch: flaunch, tokenId: tokenId}));

        vm.stopPrank();
    }

    function test_CannotEscrowWithdrawIfEscrowIsNotUnlocked() public {
        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                TreasuryManager.TokenTimelocked.selector, stakingManager.tokenTimelock(address(flaunch), tokenId)
            )
        );
        stakingManager.escrowWithdraw(ITreasuryManager.FlaunchToken({flaunch: flaunch, tokenId: tokenId}));
        vm.stopPrank();
    }

    /**
     * creatorClaim
     */
    function test_CanCreatorClaimSuccessfully() public {
        // Allocate fees to the user
        _allocateFees(10 ether);

        // Trigger fees to withdraw
        _mintTokensToStake(1 wei);
        stakingManager.stake(1 wei);

        vm.startPrank(owner);

        uint prevBalance = owner.balance;

        vm.expectEmit();
        emit StakingManager.Claim(owner, 1 ether); // 10% to creator
        stakingManager.claim();

        assertEq(owner.balance - prevBalance, 1 ether); // 10% to creator

        vm.stopPrank();
    }

    function test_CannotCreatorClaimIfNotOwner() public {
        vm.startPrank(nonOwner);

        uint prevBalance = nonOwner.balance;

        stakingManager.claim();

        assertEq(owner.balance - prevBalance, 0);

        vm.stopPrank();
    }

    /**
     * extendEscrowDuration
     */
    function test_CanExtendEscrowDurationSuccessfully() public {
        vm.startPrank(owner);

        uint prevEscrowLockedUntil = stakingManager.tokenTimelock(address(flaunch), tokenId);

        vm.expectEmit();
        emit StakingManager.EscrowDurationExtended(address(flaunch), tokenId, prevEscrowLockedUntil + 10 days);
        stakingManager.extendEscrowDuration(
            ITreasuryManager.FlaunchToken({flaunch: flaunch, tokenId: tokenId}), 10 days
        );

        vm.stopPrank();

        assertEq(stakingManager.tokenTimelock(address(flaunch), tokenId), prevEscrowLockedUntil + 10 days);
    }

    function test_CannotExtendEscrowDurationIfNotOwner() public {
        vm.startPrank(nonOwner);

        vm.expectRevert(SupportsCreatorTokens.InvalidCreatorAddress.selector);
        stakingManager.extendEscrowDuration(
            ITreasuryManager.FlaunchToken({flaunch: flaunch, tokenId: tokenId}), 10 days
        );

        vm.stopPrank();
    }

    /**
     * stake
     */
    function test_CanStakeSuccessfully(
        uint _amount
    ) public {
        vm.assume(_amount > 0);
        _mintTokensToStake(_amount);

        uint prevBalance = stakingToken.balanceOf(address(this));

        stakingManager.stake(_amount);

        assertEq(stakingManager.totalDeposited(), _amount);
        assertEq(stakingToken.balanceOf(address(this)), prevBalance - _amount);
        assertEq(stakingToken.balanceOf(address(stakingManager)), _amount);

        (uint amount, uint timelockedUntil, uint ethRewardsPerTokenSnapshotX128,) =
            stakingManager.userPositions(address(this));
        assertEq(amount, _amount);
        assertEq(timelockedUntil, block.timestamp + minStakeDuration);
        assertEq(ethRewardsPerTokenSnapshotX128, stakingManager.globalEthRewardsPerTokenX128());
    }

    function test_CannotStakeZeroAmount() public {
        vm.expectRevert(StakingManager.InvalidStakeAmount.selector);
        stakingManager.stake(0);
    }

    // Handle correctly setting `ethOwed`
    function test_CanStakeAgainSuccessfully(uint _amountFirstStake, uint _amountSecondStake) public {
        // Restrict amount to maintain precision during calculations
        vm.assume(_amountFirstStake > 0 && _amountFirstStake < type(uint128).max);
        vm.assume(_amountSecondStake > 0 && _amountSecondStake < type(uint128).max);
        // avoid overflow in tests
        vm.assume(_amountSecondStake < type(uint).max - _amountFirstStake);

        _mintTokensToStake(_amountFirstStake);
        stakingManager.stake(_amountFirstStake);

        (,,, uint ethOwed) = stakingManager.userPositions(address(this));
        assertEq(ethOwed, 0);

        // distribute rewards
        _allocateFees(10 ether);

        // stake again
        _mintTokensToStake(_amountSecondStake);
        stakingManager.stake(_amountSecondStake);

        (,,, ethOwed) = stakingManager.userPositions(address(this));
        // after deducting the creator's share
        assertApproxEqAbs(
            ethOwed,
            9 ether,
            1 wei // allow error upto few wei
        );
    }

    /**
     * unstake
     */
    function test_CanUnstakeSuccessfully(
        uint _amount
    ) public {
        vm.assume(_amount > 0);

        // Restrict amount to maintain precision during calculations
        vm.assume(_amount < type(uint128).max);

        _mintTokensToStake(_amount);
        stakingManager.stake(_amount);

        // distribute rewards
        _allocateFees(10 ether);

        // jump to make position unlocked
        (, uint timelockedUntil,,) = stakingManager.userPositions(address(this));
        vm.warp(timelockedUntil + 1);

        uint prevBalance = address(this).balance;

        stakingManager.unstake(_amount);

        assertEq(stakingToken.balanceOf(address(this)), _amount);
        assertEq(stakingToken.balanceOf(address(stakingManager)), 0);

        (uint amount,,,) = stakingManager.userPositions(address(this));
        assertEq(amount, 0);
        assertEq(stakingManager.totalDeposited(), 0);
        assertApproxEqAbs(
            address(this).balance - prevBalance,
            9 ether,
            1 wei // allow error upto few wei
        );
    }

    function test_CannotUnstakeZeroAmount() public {
        vm.expectRevert(StakingManager.InvalidUnstakeAmount.selector);
        stakingManager.unstake(0);
    }

    function test_CannotUnstakeIfStakeIsLocked(
        uint _amount
    ) public {
        vm.assume(_amount > 0);

        _mintTokensToStake(_amount);
        stakingManager.stake(_amount);

        vm.expectRevert(StakingManager.StakeLocked.selector);
        stakingManager.unstake(_amount);
    }

    function test_CannotUnstakeIfInsufficientBalance(
        uint _amount
    ) public {
        // We need to make sure that we aren't staking a zero value as this is calculated as
        // `_amount - 1` in the test.
        vm.assume(_amount > 1);

        // stake 1 less than the amount to unstake
        _mintTokensToStake(_amount - 1);
        stakingManager.stake(_amount - 1);

        // jump to make position unlocked
        (, uint timelockedUntil,,) = stakingManager.userPositions(address(this));
        vm.warp(timelockedUntil + 1);

        vm.expectRevert(StakingManager.InsufficientBalance.selector);
        stakingManager.unstake(_amount);
    }

    /**
     * claim
     */
    function test_CanClaimSuccessfully() public {
        // Mints 100 tokens to stake on the manager
        _mintTokensToStake(100 ether);

        // Stake 10 tokens
        stakingManager.stake(10 ether);

        // Distribute 10 ETH in fees. The StakingManager is set up so that the creator gets 10%
        // and then stakers get the remaining 90%.
        _allocateFees(10 ether);

        // Stake an additional 90 tokens, which will give us 100 tokens in total
        stakingManager.stake(90 ether);

        // Distribute an additional 90 ETH in fees, giving us 100 ETH in total
        _allocateFees(90 ether);

        // Jump to make position unlocked
        (, uint timelockedUntil,,) = stakingManager.userPositions(address(this));
        vm.warp(timelockedUntil + 1);

        // Find the current balance that we hold
        uint prevBalance = address(this).balance;

        vm.expectEmit();
        emit StakingManager.Claim(address(this), 90 ether - 2 wei);

        // Confirm the balance we have for our staking user and owner
        assertApproxEqAbs(stakingManager.balances(address(this)), 90 ether, 2 wei, 'Invalid balance for staking user');
        assertApproxEqAbs(stakingManager.balances(owner), 10 ether, 2 wei, 'Invalid balance for owner');

        // Trigger a claim. The `owner` address will have 10% of the fees allocated as the creator of the
        // Flaunched token. The remaining 10% should go to the test contract.
        stakingManager.claim();

        // Ensure that the user received 90 ether, after deducting the creator's share
        assertApproxEqAbs(
            address(this).balance - prevBalance,
            90 ether,
            2 wei // allow error upto few wei
        );

        // Confirm that the stake info no longer shows pending ETH rewards
        (,, uint pendingETHRewards) = stakingManager.getUserStakeInfo(address(this));
        assertEq(pendingETHRewards, 0);

        // Confirm that the snapshot of the user position is now synced with the global snapshot
        (,, uint ethRewardsPerTokenSnapshotX128,) = stakingManager.userPositions(address(this));
        assertEq(ethRewardsPerTokenSnapshotX128, stakingManager.globalEthRewardsPerTokenX128());

        // We should now be able to make the claim as the owner
        vm.startPrank(owner);

        vm.expectEmit();
        emit StakingManager.Claim(owner, 10 ether);
        stakingManager.claim();

        vm.stopPrank();
    }

    function test_CanMakeClaimAcrossMultipleSources() public freshManager {
        /**
         * Set up a user that is:
         * - A creator of 2 tokens
         * - A staker of multiple tokens
         * - The manager owner
         */

        // Define our creator and owner shares
        uint _creatorShare = 20_00000; // 20%
        uint _ownerShare = 10_00000; // 10%

        // Set up a new StakingManager
        stakingManager.initialize({
            _owner: owner,
            _data: abi.encode(
                StakingManager.InitializeParams(
                    address(stakingToken), minEscrowDuration, minStakeDuration, _creatorShare, _ownerShare
                )
            )
        });

        address creator1 = owner;
        address creator2 = payable(address(0x222));

        // Create 2 tokens
        uint tokenId1 = _createAndDepositERC721(creator1);
        uint tokenId2 = _createAndDepositERC721(creator1);

        // Create another token for another user
        uint tokenId3 = _createAndDepositERC721(creator2);

        // Stake tokens as creator1
        _mintTokensToStake(4 ether, creator1);
        vm.prank(creator1);
        stakingManager.stake(4 ether);

        // Stake tokens as creator2
        _mintTokensToStake(1 ether, creator2);
        vm.prank(creator2);
        stakingManager.stake(1 ether);

        // Transfer in ETH from a recognised pool (via FeeEscrow)
        _allocateFeesToToken(tokenId1, 10 ether); // creator1 token
        _allocateFeesToToken(tokenId2, 5 ether); // creator1 token
        _allocateFeesToToken(tokenId3, 10 ether); // creator2 token

        // Transfer in ETH from an unknown source
        deal(address(this), 10 ether);
        (bool _sent,) = payable(address(stakingManager)).call{value: 10 ether}('');
        require(_sent, 'ETH Transfer Failed');

        /**
         * Total amount in manager: 35 ether
         * Total creator fees: 20% of 35 ether = 7 ether
         * Total staker fees: 70% of 35 ether = 24.5 ether
         * Total owner fees: 10% of 35 ether = 3.5 ether
         *
         * We expect the following balances:
         *
         * +--------------+----------+-------------+------------+-------------+
         * | Address      | Creator  | Staker      | Owner      | Total       |
         * +--------------+----------+-------------+------------+-------------+
         * | creator1     | 3 ether  | 21.2 ether  | 3.5 ether  | 27.7 ether  |
         * | creator2     | 2 ether  |  5.3 ether  |   0 ether  |  7.3 ether  |
         * | nonOwner     | 0 ether  |    0 ether  |   0 ether  |    0 ether  |
         * +--------------+----------+-------------+------------+-------------+
         */

        // Get our current balances and ensure they match what we expect. We compensate for a
        // small dust rounding error.
        uint creator1Balance = stakingManager.balances(creator1);
        assertApproxEqAbs(creator1Balance, 27.7 ether, 1, 'Incorrect creator1Balance');

        uint creator2Balance = stakingManager.balances(creator2);
        assertApproxEqAbs(creator2Balance, 7.3 ether, 1, 'Incorrect creator2Balance');

        uint unknownBalance = stakingManager.balances(nonOwner);
        assertEq(unknownBalance, 0, 'Incorrect unknownBalance');

        // Claim as the three user balances from above
        vm.prank(creator1);
        stakingManager.claim();

        vm.prank(creator2);
        stakingManager.claim();

        vm.prank(nonOwner);
        stakingManager.claim();

        // Confirm the balances held by the creators
        assertApproxEqAbs(payable(creator1).balance, 27.7 ether, 1, 'Invalid creator1 balance');
        assertApproxEqAbs(payable(creator2).balance, 7.3 ether, 1, 'Invalid creator2 balance');
        assertEq(payable(nonOwner).balance, 0, 'Invalid nonOwner balance');

        // Confirm the balances held by the staking manager have been withdrawn
        assertEq(stakingManager.balances(creator1), 0, 'Invalid creator1 balance');
        assertEq(stakingManager.balances(creator2), 0, 'Invalid creator2 balance');
        assertEq(stakingManager.balances(nonOwner), 0, 'Invalid nonOwner balance');

        // Confirm that an additional claim won't result in any additional ETH being claimed

        // Claim as the three user balances from above
        vm.prank(creator1);
        stakingManager.claim();

        vm.prank(creator2);
        stakingManager.claim();

        vm.prank(nonOwner);
        stakingManager.claim();

        // Confirm the balances held by the creators are the same as before
        assertApproxEqAbs(payable(creator1).balance, 27.7 ether, 1, 'Invalid creator1 balance');
        assertApproxEqAbs(payable(creator2).balance, 7.3 ether, 1, 'Invalid creator2 balance');
        assertEq(payable(nonOwner).balance, 0, 'Invalid nonOwner balance');
    }

    /**
     * Multiple Flaunch Token Tests
     */
    function test_CanDepositMultipleFlaunchTokens() public {
        uint tokenId2 = _createAndDepositERC721(owner2);
        uint tokenId3 = _createAndDepositERC721(owner);

        // Verify all tokens are properly mapped
        assertEq(stakingManager.creator(address(flaunch), tokenId), owner);
        assertEq(stakingManager.creator(address(flaunch), tokenId2), owner2);
        assertEq(stakingManager.creator(address(flaunch), tokenId3), owner);

        // Verify timelocks are set
        assertEq(stakingManager.tokenTimelock(address(flaunch), tokenId), block.timestamp + minEscrowDuration);
        assertEq(stakingManager.tokenTimelock(address(flaunch), tokenId2), block.timestamp + minEscrowDuration);
        assertEq(stakingManager.tokenTimelock(address(flaunch), tokenId3), block.timestamp + minEscrowDuration);

        // Verify internal mappings
        assertGt(stakingManager.flaunchTokenInternalIds(address(flaunch), tokenId), 0);
        assertGt(stakingManager.flaunchTokenInternalIds(address(flaunch), tokenId2), 0);
        assertGt(stakingManager.flaunchTokenInternalIds(address(flaunch), tokenId3), 0);
    }

    function test_MultipleCreatorsCanWithdrawTheirTokensIndependently() public {
        // Setup multiple tokens
        uint tokenId2 = _createAndDepositERC721(owner2);

        // Fast forward past timelock
        vm.warp(stakingManager.tokenTimelock(address(flaunch), tokenId) + 1);

        // owner2 cannot withdraw owner's token
        vm.startPrank(owner2);
        vm.expectRevert(SupportsCreatorTokens.InvalidCreatorAddress.selector);
        stakingManager.escrowWithdraw(ITreasuryManager.FlaunchToken({flaunch: flaunch, tokenId: tokenId}));
        vm.stopPrank();

        // Owner cannot withdraw owner2's token
        vm.startPrank(owner);
        vm.expectRevert(SupportsCreatorTokens.InvalidCreatorAddress.selector);
        stakingManager.escrowWithdraw(ITreasuryManager.FlaunchToken({flaunch: flaunch, tokenId: tokenId2}));
        vm.stopPrank();

        // Each creator can withdraw their own token
        vm.startPrank(owner);
        stakingManager.escrowWithdraw(ITreasuryManager.FlaunchToken({flaunch: flaunch, tokenId: tokenId}));
        assertEq(flaunch.ownerOf(tokenId), owner);
        vm.stopPrank();

        vm.startPrank(owner2);
        stakingManager.escrowWithdraw(ITreasuryManager.FlaunchToken({flaunch: flaunch, tokenId: tokenId2}));
        assertEq(flaunch.ownerOf(tokenId2), owner2);
        vm.stopPrank();
    }

    function test_MultipleCreatorsCanExtendEscrowIndependently() public {
        // Setup multiple tokens
        uint tokenId2 = _createAndDepositERC721(owner2);

        uint originalTimelock1 = stakingManager.tokenTimelock(address(flaunch), tokenId);
        uint originalTimelock2 = stakingManager.tokenTimelock(address(flaunch), tokenId2);

        // Owner extends their token's escrow
        vm.startPrank(owner);
        stakingManager.extendEscrowDuration(
            ITreasuryManager.FlaunchToken({flaunch: flaunch, tokenId: tokenId}), 10 days
        );
        vm.stopPrank();

        // owner2 extends their token's escrow
        vm.startPrank(owner2);
        stakingManager.extendEscrowDuration(
            ITreasuryManager.FlaunchToken({flaunch: flaunch, tokenId: tokenId2}), 5 days
        );
        vm.stopPrank();

        // Verify independent extensions
        assertEq(stakingManager.tokenTimelock(address(flaunch), tokenId), originalTimelock1 + 10 days);
        assertEq(stakingManager.tokenTimelock(address(flaunch), tokenId2), originalTimelock2 + 5 days);
    }

    function test_StakingRewardsDistributedFromMultipleTokens() public {
        // Setup multiple tokens with different creators
        uint tokenId2 = _createAndDepositERC721(owner2);

        // Stake tokens
        _mintTokensToStake(100 ether);
        stakingManager.stake(100 ether);

        // Allocate fees to both tokens
        _allocateFees(10 ether); // tokenId (owner's token)
        _allocateFeesToToken(tokenId2, 20 ether); // tokenId2 (owner2's token)

        // Jump to unlock staking
        (, uint timelockedUntil,,) = stakingManager.userPositions(address(this));
        vm.warp(timelockedUntil + 1);

        // Claim as staker - should get rewards from both tokens minus creator shares
        uint prevBalance = address(this).balance;
        stakingManager.claim();

        // Total fees: 30 ether, creator share: 10% = 3 ether to creators, 27 ether to stakers
        assertApproxEqAbs(
            address(this).balance - prevBalance,
            27 ether,
            3 wei // allow small rounding errors
        );
    }

    function test_MultipleCreatorsCanClaimIndependently() public {
        // Setup multiple tokens with different creators
        uint tokenId2 = _createAndDepositERC721(owner2);

        // Add some staking to trigger fee withdrawal
        _mintTokensToStake(1 wei);
        stakingManager.stake(1 wei);

        // Allocate different amounts to each token
        _allocateFees(10 ether); // tokenId (owner's token)
        _allocateFeesToToken(tokenId2, 20 ether); // tokenId2 (owner2's token)

        // Owner claims their creator fees
        vm.startPrank(owner);
        uint ownerPrevBalance = owner.balance;
        stakingManager.claim();
        uint ownerCreatorFees = owner.balance - ownerPrevBalance;
        vm.stopPrank();

        // owner2 claims their creator fees
        vm.startPrank(owner2);
        uint owner2PrevBalance = owner2.balance;
        stakingManager.claim();
        uint owner2CreatorFees = owner2.balance - owner2PrevBalance;
        vm.stopPrank();

        // Verify each creator got their proportional share
        // Owner: 10% of 10 ether = 1 ether
        // owner2: 10% of 20 ether = 2 ether
        assertApproxEqAbs(ownerCreatorFees, 1 ether, 1 wei);
        assertApproxEqAbs(owner2CreatorFees, 2 ether, 1 wei);
    }

    function test_CreatorWithMultipleTokensClaimsAll() public {
        // Owner creates multiple tokens
        uint tokenId2 = _createAndDepositERC721(owner);
        uint tokenId3 = _createAndDepositERC721(owner);

        // Add some staking to trigger fee withdrawal
        _mintTokensToStake(1 wei);
        stakingManager.stake(1 wei);

        // Allocate fees to all three tokens
        _allocateFees(10 ether); // tokenId
        _allocateFeesToToken(tokenId2, 15 ether); // tokenId2
        _allocateFeesToToken(tokenId3, 25 ether); // tokenId3

        // Owner claims - should get creator fees from all their tokens
        vm.startPrank(owner);
        uint prevBalance = owner.balance;
        stakingManager.claim();
        uint totalCreatorFees = owner.balance - prevBalance;
        vm.stopPrank();

        // Total fees for owner's tokens: 50 ether, creator share: 10% = 5 ether
        assertApproxEqAbs(totalCreatorFees, 5 ether, 3 wei);
    }

    function test_StakerAndCreatorCanClaimSimultaneously() public {
        // Make the test contract both a staker and creator
        uint myTokenId = _createAndDepositERC721(address(this));

        // Stake tokens
        _mintTokensToStake(100 ether);
        stakingManager.stake(100 ether);

        // Allocate fees to both tokens
        _allocateFees(20 ether); // owner's token
        _allocateFeesToToken(myTokenId, 30 ether); // my token

        // Jump to unlock staking
        (, uint timelockedUntil,,) = stakingManager.userPositions(address(this));
        vm.warp(timelockedUntil + 1);

        // Claim - should get both staker rewards and creator fees
        uint prevBalance = address(this).balance;
        stakingManager.claim();
        uint totalClaimed = address(this).balance - prevBalance;

        // Total fees: 50 ether
        // Creator fees: 10% of 50 ether = 5 ether (but only 3 ether from my token)
        // Staker fees: 90% of 50 ether = 45 ether
        // My total: 3 ether (creator) + 45 ether (staker) = 48 ether
        assertApproxEqAbs(totalClaimed, 48 ether, 5 wei);
    }

    function test_PendingCreatorFeesCalculatedCorrectly() public {
        // Setup multiple tokens with different creators
        uint tokenId2 = _createAndDepositERC721(owner2);

        // Owner creates second token
        uint tokenId3 = _createAndDepositERC721(owner);

        // Allocate fees to tokens
        _allocateFees(10 ether); // tokenId (owner)
        _allocateFeesToToken(tokenId2, 20 ether); // tokenId2 (owner2)
        _allocateFeesToToken(tokenId3, 15 ether); // tokenId3 (owner)

        // Check pending creator fees
        uint ownerPending = stakingManager.pendingCreatorFees(owner);
        uint owner2Pending = stakingManager.pendingCreatorFees(owner2);

        // Owner has 2 tokens: 10 + 15 = 25 ether, 10% = 2.5 ether
        // owner2 has 1 token: 20 ether, 10% = 2 ether
        assertApproxEqAbs(ownerPending, 2.5 ether, 2 wei);
        assertApproxEqAbs(owner2Pending, 2 ether, 1 wei);
    }

    function test_TokensViewFunctionReturnsCorrectTokens() public {
        // Setup multiple tokens for owner
        uint tokenId2 = _createAndDepositERC721(owner);
        // Setup token for different creator
        uint tokenId3 = _createAndDepositERC721(owner2);

        // Get tokens for owner
        ITreasuryManager.FlaunchToken[] memory ownerTokens = stakingManager.tokens(owner);
        assertEq(ownerTokens.length, 2);

        // Verify tokens belong to owner (order might vary)
        bool foundToken1 = false;
        bool foundToken2 = false;
        for (uint i = 0; i < ownerTokens.length; i++) {
            if (ownerTokens[i].tokenId == tokenId) {
                foundToken1 = true;
            }
            if (ownerTokens[i].tokenId == tokenId2) {
                foundToken2 = true;
            }
        }
        assertTrue(foundToken1);
        assertTrue(foundToken2);

        // Get tokens for owner2
        ITreasuryManager.FlaunchToken[] memory owner2Tokens = stakingManager.tokens(owner2);
        assertEq(owner2Tokens.length, 1);
        assertEq(owner2Tokens[0].tokenId, tokenId3);
    }

    function test_BalancesViewFunctionWorksWithMultipleTokens() public {
        // Setup multiple tokens and staking
        uint tokenId2 = _createAndDepositERC721(owner2);

        // Stake as test contract
        _mintTokensToStake(100 ether);
        stakingManager.stake(100 ether);

        // Allocate fees
        _allocateFees(10 ether); // owner's token
        _allocateFeesToToken(tokenId2, 20 ether); // owner2's token

        // Check balances
        uint stakerBalance = stakingManager.balances(address(this));
        uint ownerBalance = stakingManager.balances(owner);
        uint owner2Balance = stakingManager.balances(owner2);

        // Staker gets 90% of total fees: 27 ether
        // Owner gets 10% of 10 ether: 1 ether
        // owner2 gets 10% of 20 ether: 2 ether
        assertApproxEqAbs(stakerBalance, 27 ether, 3 wei);
        assertApproxEqAbs(ownerBalance, 1 ether, 1 wei);
        assertApproxEqAbs(owner2Balance, 2 ether, 1 wei);
    }

    function test_InvestigateClaimThreeIssue() public forkBaseBlock(36273176) {
        // Deploy an updated FeeEscrowRegistry and add the existing FeeEscrow contract references
        FeeEscrowRegistry feeEscrowRegistry = new FeeEscrowRegistry();
        feeEscrowRegistry.addFeeEscrow(0x72e6f7948b1B1A343B477F39aAbd2E35E6D27dde, false);
        feeEscrowRegistry.addFeeEscrow(0x51Bba15255406Cfe7099a42183302640ba7dAFDC, true);

        // Define our two testing users
        address user1 = 0xfE64bafe6663a3c76EB2A82F99740847B588190b;
        address user2 = 0x498E93Bc04955fCBAC04BCF1a3BA792f01Dbaa96;

        // Deploy the updated StakingManager
        deployCodeTo(
            'StakingManager.sol:StakingManager',
            abi.encode(0x48af8b28DDC5e5A86c4906212fc35Fa808CA8763, address(feeEscrowRegistry)),
            0xc5EeC15Afb5aE342F6F8B1EcAAaCe5BeEA10d149
        );

        stakingManager = StakingManager(payable(0xc5EeC15Afb5aE342F6F8B1EcAAaCe5BeEA10d149));

        // Get some basic information around the StakingManager and check it's fee distribution
        assertEq(stakingManager.managerFees(), 1694598456939686, 'managerFees');
        assertEq(stakingManager.claimableOwnerFees(), 338919691387937, 'claimableOwnerFees');

        // From V1 tokens, we cannot calculate the poolId so no creator fees can be taken
        assertEq(stakingManager.pendingCreatorFees(user1), 0, 'pendingCreatorFees(user1)');
        assertEq(stakingManager.pendingCreatorFees(user2), 0, 'pendingCreatorFees(user2)');

        vm.startPrank(user1);

        // Find the balance of our two testing users
        uint balance1 = stakingManager.balances(user1);
        uint balance2 = stakingManager.balances(user2);

        assertEq(balance1, 1010066023437557, 'balance1');
        assertEq(balance2, 1023452124890065, 'balance2');

        // Find the stake balance of our two testing users
        {
            (uint tokensStaked1,, uint stakeBalance1) = stakingManager.getUserStakeInfo(user1);
            (uint tokensStaked2,, uint stakeBalance2) = stakingManager.getUserStakeInfo(user2);

            assertEq(tokensStaked1, 737778062136427780979805425, 'tokensStaked1');
            assertEq(tokensStaked2, 500000000534573575222153652, 'tokensStaked2');

            assertEq(stakeBalance1, 1010066023437557, 'stakeBalance1');
            assertEq(stakeBalance2, 684532433502128, 'stakeBalance2');
        }

        // Make our claim and confirm the amount that was received. This claim is made as `user1`
        stakingManager.claim();

        // Check the balance after the claim
        uint balance1After = stakingManager.balances(user1);
        uint balance2After = stakingManager.balances(user2);

        assertEq(balance1After, 0, 'balance1After');
        assertEq(balance2After, 1023452124890065, 'balance2After');

        // Check the stake balance after the claim
        {
            (uint tokensStaked1After,, uint stakeBalance1After) = stakingManager.getUserStakeInfo(user1);
            (uint tokensStaked2After,, uint stakeBalance2After) = stakingManager.getUserStakeInfo(user2);

            assertEq(tokensStaked1After, 737778062136427780979805425, 'tokensStaked1After');
            assertEq(tokensStaked2After, 500000000534573575222153652, 'tokensStaked2After');

            assertEq(stakeBalance1After, 0, 'stakeBalance1After');
            assertEq(stakeBalance2After, 684532433502128, 'stakeBalance2After');
        }

        vm.stopPrank();

        vm.startPrank(user2);

        // Now make a claim as `user2`
        stakingManager.claim();

        // Check the balance after the claim
        uint balance1After2 = stakingManager.balances(user1);
        uint balance2After2 = stakingManager.balances(user2);

        assertEq(balance1After2, 0, 'balance1After2');
        assertEq(balance2After2, 0, 'balance2After2');

        // Check the stake balance after the claim
        {
            (uint tokensStaked1After2,, uint stakeBalance1After2) = stakingManager.getUserStakeInfo(user1);
            (uint tokensStaked2After2,, uint stakeBalance2After2) = stakingManager.getUserStakeInfo(user2);

            assertEq(tokensStaked1After2, 737778062136427780979805425, 'tokensStaked1After2');
            assertEq(tokensStaked2After2, 500000000534573575222153652, 'tokensStaked2After2');

            assertEq(stakeBalance1After2, 0, 'stakeBalance1After2');
            assertEq(stakeBalance2After2, 0, 'stakeBalance2After2');
        }

        vm.stopPrank();
    }

    function test_Receive_DifferentSources() public {
        // Set up and define a range of FeeEscrow contracts
        address LEGACY_FEE_ESCROW = address(new FeeEscrow(address(flETH), address(indexer)));
        address MODERN_FEE_ESCROW = address(new FeeEscrow(address(flETH), address(indexer)));
        address UNKNOWN_FEE_ESCROW = address(new FeeEscrow(address(flETH), address(indexer)));

        // Create a new FeeEscrowRegistry with our test FeeEscrow contracts
        feeEscrowRegistry = new FeeEscrowRegistry();
        feeEscrowRegistry.addFeeEscrow(LEGACY_FEE_ESCROW, true);
        feeEscrowRegistry.addFeeEscrow(MODERN_FEE_ESCROW, false);

        // We need to deploy a new StakingManager with our test FeeEscrowRegistry
        managerImplementation = address(new StakingManager(address(treasuryManagerFactory), address(feeEscrowRegistry)));
        treasuryManagerFactory.approveManager(managerImplementation);

        // Deploy our {StakingManager} implementation
        vm.startPrank(owner);
        address payable implementation = treasuryManagerFactory.deployManager(managerImplementation);
        stakingManager = StakingManager(implementation);

        // Create a memecoin and approve the manager to take it
        tokenId = _createERC721(owner);
        flaunch.approve(address(stakingManager), tokenId);

        // Deploy a Token to stake for testing
        stakingToken = new ERC20Mock(owner);

        // Initialize a testing token.
        // 60% split fees
        // 30% creator share
        // 10% owner share
        stakingManager.initialize({
            _owner: owner,
            _data: abi.encode(
                StakingManager.InitializeParams(
                    address(stakingToken), minEscrowDuration, minStakeDuration, 30_00000, 10_00000
                )
            )
        });

        // deposit into the manager
        stakingManager.deposit({
            _flaunchToken: ITreasuryManager.FlaunchToken({flaunch: flaunch, tokenId: tokenId}),
            _creator: owner,
            _data: ''
        });

        vm.stopPrank();

        // Provide our FeeEscrow contracts with some ETH
        deal(LEGACY_FEE_ESCROW, 10 ether);
        deal(MODERN_FEE_ESCROW, 10 ether);
        deal(UNKNOWN_FEE_ESCROW, 10 ether);

        // Make a deposit from each and calculate the expected fees distributed across the manager
        vm.prank(LEGACY_FEE_ESCROW);
        address(stakingManager).call{value: 10 ether}('');

        vm.prank(MODERN_FEE_ESCROW);
        address(stakingManager).call{value: 10 ether}('');

        vm.prank(UNKNOWN_FEE_ESCROW);
        address(stakingManager).call{value: 10 ether}('');

        // Capture the stored fee amounts
        uint splitFees = stakingManager.splitFees();
        uint creatorFees = stakingManager.creatorFees();
        uint ownerFees = stakingManager.claimableOwnerFees();

        // Verify that the fees are correct
        assertEq(splitFees, 24 ether, 'Incorrect split fees');
        assertEq(creatorFees, 3 ether, 'Incorrect creator fees');
        assertEq(ownerFees, 3 ether, 'Incorrect owner fees');

        // Verify that the total fees are 30 ether
        assertEq(splitFees + creatorFees + ownerFees, 30 ether, 'Total fees should be 30 ether');
    }

    /**
     * Internal Helpers
     */
    function _createERC721(
        address _recipient
    ) internal returns (uint tokenId_) {
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
                initialPriceParams: abi.encode(5000e6),
                feeCalculatorParams: abi.encode(1_000)
            })
        );

        // Get the tokenId from the memecoin address
        return flaunch.tokenId(memecoin);
    }

    function _createAndDepositERC721(
        address _owner
    ) internal returns (uint tokenId_) {
        vm.startPrank(_owner);
        tokenId_ = _createERC721(_owner);
        flaunch.approve(address(stakingManager), tokenId_);

        // Deposit second token
        stakingManager.deposit({
            _flaunchToken: ITreasuryManager.FlaunchToken({flaunch: flaunch, tokenId: tokenId_}),
            _creator: _owner,
            _data: ''
        });
        vm.stopPrank();
    }

    function _allocateFees(
        uint _amount
    ) internal {
        // Mint ETH to the flETH contract to facilitate unwrapping
        deal(address(this), _amount);
        WETH.deposit{value: _amount}();
        WETH.transfer(address(positionManager), _amount);

        PoolId poolId = flaunch.poolId(tokenId);
        positionManager.allocateFeesMock(poolId, address(stakingManager), _amount);
    }

    /**
     * Helper function to allocate fees to a specific token
     */
    function _allocateFeesToToken(uint _tokenId, uint _amount) internal {
        // Mint ETH to the flETH contract to facilitate unwrapping
        deal(address(this), _amount);
        WETH.deposit{value: _amount}();
        WETH.transfer(address(positionManager), _amount);

        PoolId poolId = flaunch.poolId(_tokenId);
        positionManager.allocateFeesMock(poolId, address(stakingManager), _amount);
    }

    function _mintTokensToStake(
        uint _amount
    ) internal {
        stakingToken.mint(address(this), _amount);
        stakingToken.approve(address(stakingManager), type(uint).max);
    }

    function _mintTokensToStake(uint _amount, address _staker) internal {
        vm.startPrank(_staker);
        stakingToken.mint(_staker, _amount);
        stakingToken.approve(address(stakingManager), type(uint).max);
        vm.stopPrank();
    }

    /**
     * Deploys a fresh {StakingManager} so that we the tokenId won't already be set.
     */
    modifier freshManager() {
        // Deploy a new {StakingManager} implementation as we will be using a new tokenId
        stakingManager = StakingManager(treasuryManagerFactory.deployManager(managerImplementation));

        _;
    }
}
