// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from '@solady/auth/Ownable.sol';
import {SafeTransferLib} from '@solady/utils/SafeTransferLib.sol';

import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';

import {PoolId} from '@uniswap/v4-core/src/types/PoolId.sol';

import {IndexerSubscriber} from '@flaunch/subscribers/Indexer.sol';

import {IFLETH} from '@flaunch-interfaces/IFLETH.sol';


/**
 * Escrow contract that receives fees from multiple PositionManagers, that allows the recipient
 * to withdraw them in a single transaction. 
 * 收取费用的合约，允许接收者在一个交易中提取它们。
 */
contract FeeEscrow is Ownable {

    error InvalidRecipient();
    error PoolIdNotIndexed();
    error RecipientZeroAddress();

    /// Emitted when fees are added to a payee 收取费用的事件
    event Deposit(PoolId indexed _poolId, address _payee, address _token, uint _amount);

    /// Emitted when fees are withdrawn to a payee 提取费用的事件
    event Withdrawal(address _sender, address _recipient, address _token, uint _amount);
    
    /// The native token address 原生代币地址
    address public immutable nativeToken;

    /// The {IndexerSubscriber} subscriber 索引器订阅者
    IndexerSubscriber public indexer;

    /// Maps a user to an ETH equivalent token balance available in escrow 映射用户到ETH等价的代币余额
    mapping (address _recipient => uint _amount) public balances;

    /// Maps the total fees that a PoolId has accrued 映射池id到累计费用
    mapping (PoolId _poolId => uint _amount) public totalFeesAllocated;

    /**
     * Constructor to initialize the PoolSwap contract address. 
     * 构造函数初始化PoolSwap合约地址。
     * @param _nativeToken The native token used by the Flaunch protocol 原生代币地址
     * @param _indexer The {IndexerSubscriber} contract address 索引器合约地址
     */
    constructor (address _nativeToken, address _indexer) {
        nativeToken = _nativeToken;
        indexer = IndexerSubscriber(_indexer);

        _initializeOwner(msg.sender);
    }

    /**
     * Allows a deposit to be made against a user. The amount is stored within the
     * escrow contract to be claimed later. 
     * 允许对用户进行存款。金额存储在escrow合约中，稍后可以提取。
     * @param _poolId The PoolId that the deposit came from 存款来源的池id
     * @param _recipient The recipient of the transferred token 接收者地址
     * @param _amount The amount of the token to be transferred 转账数量
     */
    function allocateFees(PoolId _poolId, address _recipient, uint _amount) external {
        // If we don't have fees to allocate, exit early 如果没有费用要分配，则退出
        if (_amount == 0) return;

        // Ensure we aren't trying to allocate fees to a zero address 确保我们不是试图分配费用到零地址
        if (_recipient == address(0)) revert RecipientZeroAddress();

        // Increase the balance available for the recipient to claim 增加接收者可提取的余额
        balances[_recipient] += _amount;

        // Increase the fee tracking for the PoolId, only if the recipient matches the PoolId
        // that has also been passed in. This will prevent users from being misallocated and 增加池id的累计费用，只有接收者与池id匹配时才增加
        // external contracts that depend on this figure from being misinformed. 防止用户被错误分配，外部合约因错误信息而受到影响。
        (address flaunch,,, uint tokenId) = indexer.poolIndex(_poolId);
        if (tokenId != 0 && IERC721(flaunch).ownerOf(tokenId) == _recipient) {
            totalFeesAllocated[_poolId] += _amount;
        }

        // Transfer flETH from the sender into this escrow
        IFLETH(nativeToken).transferFrom(msg.sender, address(this), _amount);

        emit Deposit(_poolId, _recipient, nativeToken, _amount);
    }

    /**
     * Allows fees to be withdrawn from escrowed fee positions.
     *
     * @param _recipient The recipient of the holder's withdraw
     * @param _unwrap If we want to unwrap the balance from flETH into ETH
     */
    function withdrawFees(address _recipient, bool _unwrap) public {
        // Get the amount of token that is stored in escrow
        uint amount = balances[msg.sender];

        // If there are no fees to withdraw, exit early
        if (amount == 0) return;

        // Reset our user's balance to prevent reentry
        balances[msg.sender] = 0;

        // Convert the flETH balance held into native ETH
        if (_unwrap) {
            // Handle a withdraw of the withdrawn ETH
            IFLETH(nativeToken).withdraw(amount);
            (bool _sent,) = payable(_recipient).call{value: amount}('');
            require(_sent, 'ETH Transfer Failed');
            emit Withdrawal(msg.sender, _recipient, address(0), amount);
        }
        // Transfer flETH token without unwrapping
        else {
            SafeTransferLib.safeTransfer(nativeToken, _recipient, amount);
            emit Withdrawal(msg.sender, _recipient, nativeToken, amount);
        }
    }

    /**
     * Allows the owner to update the {IndexerSubscriber}.
     *
     * @param _indexer The new {IndexerSubscriber} contract address
     */
    function setIndexer(address _indexer) public onlyOwner {
        indexer = IndexerSubscriber(_indexer);
    }

    /**
     * Allows the contract to receive ETH when withdrawn from the flETH token.
     */
    receive () external payable {}
}
