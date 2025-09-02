// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeTransferLib} from '@solady/utils/SafeTransferLib.sol';

import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {FullMath} from '@uniswap/v4-core/src/libraries/FullMath.sol';
import {FixedPoint128} from '@uniswap/v4-core/src/libraries/FixedPoint128.sol';

import {FeeSplitManager} from '@flaunch/treasury/managers/FeeSplitManager.sol';
import {Flaunch} from '@flaunch/Flaunch.sol';


/**
 * Allows Flaunch tokens to be locked inside a staking manager. The users can stake a defined ERC20
 * token and earn their share of ETH rewards from the memestreams.
 * 
 * The creator can specify the split % between themselves, the stakers and the creators.
 * 
 * The NFT and tokens are locked, based on the values set by the creator.
 */
contract StakingManager is FeeSplitManager {

    using EnumerableSet for EnumerableSet.UintSet;

    error InsufficientBalance();
    error InvalidStakeAmount();
    error InvalidStakingToken();
    error InvalidUnstakeAmount();
    error StakeLocked();

    event Claim(address _sender, uint _amount);
    event EscrowDurationExtended(address _flaunch, uint _tokenId, uint _newDuration);
    event ManagerInitialized(address _owner, InitializeParams _params);
    event Stake(address _sender, uint _amount, Position _position);
    event Unstake(address _sender, uint _amount, Position _position);

    /**
     * Parameters passed during manager initialization.
     * 
     * @member stakingToken The address of the token to be staked
     * @member minEscrowDuration The minimum duration that the creator's NFT is locked for
     * @member minStakeDuration The minimum duration that the user's tokens are locked for
     * @member creatorShare The share that a creator will earn from their token
     * @member ownerShare The share that the manager owner will earn from their token
     */
    struct InitializeParams {
        address stakingToken;
        uint minEscrowDuration;
        uint minStakeDuration;
        uint creatorShare;
        uint ownerShare;
    }

    /**
     * A struct that represents a user's position in the staking manager.
     * 
     * @member amount The amount of tokens staked
     * @member timelockedUntil The timestamp until which the stake is locked
     * @member ethRewardsPerTokenSnapshotX128 The global ETH rewards per token snapshot,
     *         updated whenever a user stakes, unstakes or claims
     * @member ethOwed The pending ETH rewards for the user, before the last snapshot
     */
    struct Position {
        uint amount;
        uint timelockedUntil;
        uint ethRewardsPerTokenSnapshotX128;
        uint ethOwed;
    }

    /// The address of the token to be staked
    IERC20 public stakingToken;

    /// The minimum duration that the creator's NFT is locked for
    uint public minEscrowDuration;

    /// The minimum duration that the user's tokens are locked for
    uint public minStakeDuration;

    /// The total amount of ERC20 tokens deposited
    uint public totalDeposited;

    /// The global ETH rewards per token snapshot
    uint public globalEthRewardsPerTokenX128;

    /// Store the balance after last withdraw by the manager
    uint internal _lastWithdrawBalance;

    /// A mapping of user addresses to their position in the staking manager
    mapping (address user => Position position) public userPositions;

    /**
     * Sets up the contract with the initial required contract addresses.
     *
     * @param _treasuryManagerFactory The {TreasuryManagerFactory} that will launch this implementation
     */
    constructor (address _treasuryManagerFactory) FeeSplitManager(_treasuryManagerFactory) {
        // ..
    }

    /**
     * Registers the owner of the manager and sets the initial configurations.
     *
     * @param _owner Owner of the manager
     * @param _data Staking manager variables
     */
    function _initialize(address _owner, bytes calldata _data) internal override {
        // Unpack our initial manager settings
        (InitializeParams memory params) = abi.decode(_data, (InitializeParams));

        // Prevent the staking token from being a zero address
        if (params.stakingToken == address(0)) {
            revert InvalidStakingToken();
        }

        // Set our initial variables. We don't want to validate value ranges for
        // `minEscrowDuration` and `minStakeDuration` as we want to offer flexibility.
        stakingToken = IERC20(params.stakingToken);
        minEscrowDuration = params.minEscrowDuration;
        minStakeDuration = params.minStakeDuration;

        // Validate and set our creator share
        _setShares(params.creatorShare, params.ownerShare);

        // Emit an event that shows our initial data
        emit ManagerInitialized(_owner, params);
    }

    /**
     * Sets the staking status to active after a successful deposit.
     *
     * @param _flaunchToken The token to deposit
     * @param _creator The creator of the token
     * @param _data Additional data for the deposit
     */
    function _deposit(FlaunchToken calldata _flaunchToken, address _creator, bytes calldata _data) internal override {
        // Assign the token to the creator
        _setCreatorToken(_flaunchToken, _creator, _data);

        // Set the timestamp for the escrow lock
        uint escrowDuration = block.timestamp + minEscrowDuration;
        tokenTimelock[address(_flaunchToken.flaunch)][_flaunchToken.tokenId] = escrowDuration;

        // Emit our escrow duration extended event
        emit EscrowDurationExtended(
            address(_flaunchToken.flaunch),
            _flaunchToken.tokenId,
            escrowDuration
        );
    }

    /**
     * Allows the creator to withdraw their NFT, once the escrow lock has passed.
     * 
     * @dev This function is only callable by the creator of the token.
     * 
     * @param _flaunchToken The token to withdraw
     */
    function escrowWithdraw(FlaunchToken calldata _flaunchToken) public {
        // Get the creator of the Flaunch token and ensure they are the caller
        address tokenCreator = _onlyTokenCreator(_flaunchToken);

        // Ensure that the token is either not timelocked (zero value) or the timelock has passed
        uint unlockedAt = tokenTimelock[address(_flaunchToken.flaunch)][_flaunchToken.tokenId];
        if (block.timestamp < unlockedAt) {
            revert TokenTimelocked(unlockedAt);
        }

        // Remove the timelock on the token
        delete tokenTimelock[address(_flaunchToken.flaunch)][_flaunchToken.tokenId];

        // Transfer the token to the recipient from the contract. If the token is not held by
        // this contract then this call will revert.
        _flaunchToken.flaunch.transferFrom(address(this), tokenCreator, _flaunchToken.tokenId);

        emit TreasuryReclaimed(address(_flaunchToken.flaunch), _flaunchToken.tokenId, tokenCreator, tokenCreator);
    }

    /**
     * Allows the creator to extend their escrow lock duration.
     * 
     * @dev This function is only callable by the creator of the token.
     * 
     * @param _flaunchToken The token to extend the escrow lock for
     * @param _extendBy The amount of time to extend the escrow by
     */
    function extendEscrowDuration(FlaunchToken calldata _flaunchToken, uint _extendBy) external {
        // Get the creator of the Flaunch token and ensure they are the caller
        _onlyTokenCreator(_flaunchToken);

        // Extend the escrow lock duration
        tokenTimelock[address(_flaunchToken.flaunch)][_flaunchToken.tokenId] += _extendBy;

        // Emit our escrow duration extended event
        emit EscrowDurationExtended(
            address(_flaunchToken.flaunch),
            _flaunchToken.tokenId,
            tokenTimelock[address(_flaunchToken.flaunch)][_flaunchToken.tokenId]
        );
    }

    /**
     * Allows a user to stake their tokens into the staking manager.
     * 
     * @param _amount The amount of tokens to stake
     */
    function stake(uint _amount) external nonReentrant {
        // Prevent a zero amount stake
        if (_amount == 0) {
            revert InvalidStakeAmount();
        }

        // Account for the fees owed to previous ERC20 staking users
        _withdrawFees();

        // Transfer the tokens from the `msg.sender` to the contract
        SafeTransferLib.safeTransferFrom(address(stakingToken), msg.sender, address(this), _amount);
        totalDeposited += _amount;

        // Update the user's position
        Position storage position = userPositions[msg.sender];

        // If the user has an existing position, calculate the ETH owed till now
        if (position.amount != 0) {
            position.ethOwed = _getTotalEthOwed(position);
        }

        // Set rest of the position data
        position.amount += _amount;
        position.timelockedUntil = block.timestamp + minStakeDuration;
        position.ethRewardsPerTokenSnapshotX128 = globalEthRewardsPerTokenX128;

        // Emit our stake event
        emit Stake(msg.sender, _amount, position);
    }

    /**
     * Allows a user to unstake their tokens from the staking manager.
     * 
     * @dev Claims any pending ETH rewards before unstaking as well.
     * 
     * @dev Nonrentrant is enacted via the internally called`claim` function.
     * 
     * @param _amount The amount of tokens to unstake
     */
    function unstake(uint _amount) external {
        // Prevent a zero amount unstake
        if (_amount == 0) {
            revert InvalidUnstakeAmount();
        }

        // Get the user's position
        Position storage position = userPositions[msg.sender];

        // Ensure that the stake is not locked
        if (block.timestamp < position.timelockedUntil) revert StakeLocked();

        // Ensure that the user has enough balance
        if (_amount > position.amount) revert InsufficientBalance();

        // Claim any pending rewards for the caller
        claim();

        // Update the positions data
        position.amount -= _amount;
        totalDeposited -= _amount;

        // Transfer the tokens from the contract to the msg.sender
        SafeTransferLib.safeTransfer(address(stakingToken), msg.sender, _amount);

        // Emit our unstake event
        emit Unstake(msg.sender, _amount, position);
    }

    /**
     * Allows a user to claim their pending ETH rewards.
     *
     * @dev This bypasses the `FeeSplitManager` claim logic to implement it's own custom
     * claiming flow. This is because although the flow is relatively simple, it requires
     * some additional logic in the fee withdrawal.
     */
    function claim() public nonReentrant returns (uint) {
        // Account for any fees owed to the sender and other depositors
        _withdrawFees();

        // Find the balances available to the caller
        (uint stakeBalance, uint creatorBalance, uint ownerBalance) = _balances(msg.sender);

        // Add the balances together to get the total ETH owed. If there is no ETH owed from any
        // source, then we can exit early.
        uint ethOwed = stakeBalance + creatorBalance + ownerBalance;
        if (ethOwed == 0) {
            return 0;
        }

        // If the user has ETH owed from staking, then we need to update their position data
        if (stakeBalance != 0) {
            // Update the user's position data to remove any pending ETH owed and update
            // their rewards per token snapshot.
            Position storage position = userPositions[msg.sender];
            position.ethOwed = 0;
            position.ethRewardsPerTokenSnapshotX128 = globalEthRewardsPerTokenX128;
        }

        // If the recipient has a creator balance to claim, then action the claim against their
        // tokens and then increase their allocation by the balance.
        if (creatorBalance != 0) {
            // Iterate over the tokens that the user created to register the claim
            for (uint i; i < _creatorTokens[msg.sender].length(); ++i) {
                _creatorClaim(internalIds[_creatorTokens[msg.sender].at(i)]);
            }
        }

        // If the recipient has an owner balance to claim, then action the claim against their
        // owner share and then increase their allocation by the balance.
        if (ownerBalance != 0) {
            _claimedOwnerFees += ownerBalance;
        }

        // Transfer the ETH to the user
        SafeTransferLib.safeTransferETH(msg.sender, ethOwed);

        // Emit our claim event
        emit Claim(msg.sender, ethOwed);

        return ethOwed;
    }

    /**
     * View the stake information for a user.
     * 
     * @param _user The address of the user to view the stake information for
     * 
     * @return amount_ The amount of tokens staked
     * @return timelockedUntil_ The timestamp until which the stake is locked
     * @return pendingETHRewards_ The pending ETH rewards for the user
     */
    function getUserStakeInfo(address _user) external view returns (
        uint amount_,
        uint timelockedUntil_,
        uint pendingETHRewards_
    ) {
        Position memory position = userPositions[_user];
        return (position.amount, position.timelockedUntil, _getTotalEthOwed(position));
    }

    /**
     * Finds the ETH balance that is claimable by the `_recipient` from both staking fees and
     * creator fees.
     *
     * @param _recipient The account to find the balance of
     *
     * @return balance_ The amount of ETH available to claim by the `_recipient`
     */
    function balances(address _recipient) public view override returns (uint balance_) {
        // We don't use `_balances()` internally as it relies on `globalEthRewardsPerTokenX128`,
        // which is not updated until `_withdrawFees()` is called.

        // Capture our availableFees that are waiting to be claimed from the {FeeEscrow}. This also
        // accounts for any ETH fees that were sent directly and are attributed to the manager.
        uint availableFees = managerFees() - _lastWithdrawBalance;

        // Get the existing eth owed to the caller
        Position memory position = userPositions[_recipient];
        uint stakeBalance = position.ethOwed;

        // Only calculate the `latestGlobalEthRewardsPerTokenX128` if totalDeposited != 0
        if (totalDeposited != 0) {
            // Get the total ETH owed to the user from their staked position, calculating the
            // latest `globalEthRewardsPerTokenX128` based on the available fees balance. The
            // `availableFees` already reduces the fees allocated to creators and the owner.
            uint latestGlobalEthRewardsPerTokenX128 = globalEthRewardsPerTokenX128 + FullMath.mulDiv(
                availableFees,
                FixedPoint128.Q128,
                totalDeposited
            );

            // Calculate the stake balance based on the latest `globalEthRewardsPerTokenX128`
            stakeBalance += FullMath.mulDiv(
                latestGlobalEthRewardsPerTokenX128 - position.ethRewardsPerTokenSnapshotX128,
                position.amount,
                FixedPoint128.Q128
            );
        }

        // We then need to check if the `_recipient` is the creator of any tokens, and if they
        // are then we need to find out the available amounts to claim.
        uint creatorBalance = pendingCreatorFees(_recipient);

        // We then need to check if the `_recipient` is the owner of the manager, and if they
        // are then we need to find out the available amounts to claim.
        uint ownerBalance;
        if (_recipient == managerOwner) {
            ownerBalance = claimableOwnerFees();
        }

        balance_ = stakeBalance + creatorBalance + ownerBalance;
    }

    /**
     * Finds a breakdown of balances available to the recipient for both their share and also
     * the allocation from any tokens that they are the creator of.
     *
     * @param _recipient The account to find the balances of
     *
     * @return stakeBalance_ The balance available from the `recipientShare`
     * @return creatorBalance_ The balance available from creator fees
     * @return ownerBalance_ The balance available from owner fees
     */
    function _balances(address _recipient) internal view returns (uint stakeBalance_, uint creatorBalance_, uint ownerBalance_) {
        // Get the total ETH owed to the user from their staked position
        stakeBalance_ = _getTotalEthOwed(userPositions[_recipient]);

        // We then need to check if the `_recipient` is the creator of any tokens, and if they
        // are then we need to find out the available amounts to claim.
        creatorBalance_ = pendingCreatorFees(_recipient);

        // We then need to check if the `_recipient` is the owner of the manager, and if they
        // are then we need to find out the available amounts to claim.
        if (_recipient == managerOwner) {
            ownerBalance_ = claimableOwnerFees();
        }
    }

    /**
     * Allows the contract to withdraw any pending ETH fees.
     * 
     * @dev This function is called before each operation: stake, unstake, and claim.
     */
    function _withdrawFees() internal {
        // Withdraw the fees for the manager. The amounts are captured inside of `creatorFees` and
        // `splitFees` from the {FeeSplitManager} contract.
        treasuryManagerFactory.feeEscrow().withdrawFees(address(this), true);

        // Check if we have fees available, calculated in our `receive` function
        uint availableFees = managerFees() - _lastWithdrawBalance;

        // Early return if there are no fees to distribute
        if (availableFees == 0) {
            return;
        }

        // Update the last claimed amount
        _lastWithdrawBalance = availableFees;

        // If there were no staked ERC20 token deposits, all fees go to the creator(s) so we don't
        // need to update our `globalEthRewardsPerTokenX128` value.
        if (totalDeposited == 0) {
            return;
        }

        // Update the global ETH rewards per token snapshot, after deducting the creator's share
        globalEthRewardsPerTokenX128 += FullMath.mulDiv(availableFees, FixedPoint128.Q128, totalDeposited);
    }

    /**
     * Calculates the total ETH owed to a user, based on their position and the global ETH rewards per token snapshot.
     * 
     * @param _position The user's position in the staking manager
     *
     * @return The total ETH owed to the user
     */
    function _getTotalEthOwed(Position memory _position) internal view returns (uint) {
        return FullMath.mulDiv(
            globalEthRewardsPerTokenX128 - _position.ethRewardsPerTokenSnapshotX128,
            _position.amount,
            FixedPoint128.Q128
        ) + _position.ethOwed;
    }

    /**
     * Checks if the caller is the creator of the token.
     * 
     * @dev This function will revert if the caller is not the creator of the token.

     * @param _flaunchToken The token to check the creator of
     * 
     * @return tokenCreator The address of the token creator
     */
    function _onlyTokenCreator(FlaunchToken calldata _flaunchToken) internal view returns (address tokenCreator) {
        tokenCreator = creator[address(_flaunchToken.flaunch)][_flaunchToken.tokenId];
        if (msg.sender != tokenCreator) {
            revert InvalidCreatorAddress();
        }
    }

}