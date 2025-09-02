// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from '@solady/auth/Ownable.sol';
import {ReentrancyGuard} from '@solady/utils/ReentrancyGuard.sol';

import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import {ECDSA} from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';

import {BalanceDelta} from '@uniswap/v4-core/src/types/BalanceDelta.sol';
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import {PoolId} from '@uniswap/v4-core/src/types/PoolId.sol';
import {TickMath} from '@uniswap/v4-core/src/libraries/TickMath.sol';
import {FullMath} from '@uniswap/v4-core/src/libraries/FullMath.sol';

import {FairLaunch} from '@flaunch/hooks/FairLaunch.sol';

import {IFeeCalculator} from '@flaunch-interfaces/IFeeCalculator.sol';
import {IMsgSender} from '@flaunch-interfaces/IMsgSender.sol';
import {IMemecoin} from '@flaunch-interfaces/IMemecoin.sol';
import {IPositionManager} from '@flaunch-interfaces/IPositionManager.sol';


/**
 * This implementation of the {IFeeCalculator} returns the same base swapFee that
 * is assigned in the FeeDistribution struct, but also verifies that the transaction
 * is authorized by a trusted signer.
 */
contract TrustedSignerFeeCalculator is IFeeCalculator, Ownable, ReentrancyGuard {

    using EnumerableSet for EnumerableSet.AddressSet;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    error CallerNotPositionManager();
    error DeadlineExpired(uint _deadline);
    error InvalidPoolKey();
    error InvalidSigner(address _invalidSigner);
    error SignatureAlreadyUsed();
    error SignerAlreadyAdded(address _signer);
    error SignerDoesNotExist(address _signer);
    error TransactionCapExceeded(uint _requestedAmount, uint _maxTokensOut);

    event PoolKeySignerUpdated(PoolId _poolId, address indexed _signer);
    event PoolKeyFairLaunchSettingsUpdated(PoolId _poolId, FairLaunchSettings _settings);
    event TrustedSignerUpdated(address indexed _signer, bool _isTrusted);

    /**
     * This struct is used to store and represent the signed message.
     * 
     * @param deadline The deadline of the signed message
     * @param signature The signature of the signed message
     */
    struct SignedMessage {
        uint deadline;
        bytes signature;
    }

    /**
     * This struct is used to store and represent the trusted signer for a specific PoolKey.
     *
     * @dev If the `signer` is set to the zero address, then the PoolKey will not be able to disable
     * any trusted signer checks for their pool.
     * 
     * @param signer The signer of the PoolKey
     * @param enabled Whether the signer is enabled
     */
    struct TrustedPoolKeySigner {
        address signer;
        bool enabled;
    }

    /**
     * This struct is used to store and represent the fair launch settings for a specific PoolKey.
     *
     * @dev If the `enabled` is set to `false`, then verified signature checks will not be applied.
     * 
     * @param enabled Whether we should verify the signature of the transaction
     * @param walletCap The cap for the per wallet
     * @param txCap The cap for the per transaction (per tx)
     */
    struct FairLaunchSettings {
        bool enabled;
        uint walletCap;
        uint txCap;
    }

    /// Stores the trusted signers that we can validate against
    EnumerableSet.AddressSet internal _trustedSigners;

    /// Stores the amount of the token that a wallet has purchased
    mapping (PoolId _poolId => mapping (address _wallet => uint _amount)) public walletPurchasedAmount;

    /// Stores a signer override for a specific PoolKey
    mapping (PoolId _poolId => TrustedPoolKeySigner _signer) public trustedPoolKeySigner;

    /// Stores the fair launch settings for a specific PoolKey
    mapping (PoolId _poolId => FairLaunchSettings _settings) public fairLaunchSettings;

    /// Stores the signatures that have been used
    mapping (bytes32 _signature => bool _used) internal _usedSignatures;

    /// The native token used by Flaunch
    address public immutable nativeToken;

    /// The {PositionManager} contract address
    address public immutable positionManager;

    /**
     * Registers the owner of the contract as the sender.
     *
     * @param _nativeToken The native token used by Flaunch
     * @param _positionManager The {PositionManager} contract address
     */
    constructor (address _nativeToken, address _positionManager) {
        nativeToken = _nativeToken;
        positionManager = _positionManager;

        _initializeOwner(msg.sender);
    }

    /**
     * Returns the `_baseFee` that was passed in with no additional multipliers or calculations.
     *
     * @param _baseFee The base swap fee
     *
     * @return swapFee_ The calculated swap fee to use
     */
    function determineSwapFee(
        PoolKey memory /* _poolKey */,
        IPoolManager.SwapParams memory /* _params */,
        uint24 _baseFee
    ) public pure returns (uint24 swapFee_) {
        return _baseFee;
    }

    /**
     * During the flaunching of our token, we try to decode the parameters that are passed in to determine
     * the `FairLaunchSettings`.
     * 
     * If we are not able to decode the parameters, then we will set the `FairLaunchSettings` to `false`. This will
     * disable the fair launch settings for the PoolKey.
     * 
     * @param _poolId The pool id of the flaunch
     * @param _params The parameters that were passed in to the flaunch
     */
    function setFlaunchParams(PoolId _poolId, bytes calldata _params) external override {
        // Ensure that this call is coming from the {PositionManager}
        if (msg.sender != positionManager) {
            revert CallerNotPositionManager();
        }

        // Unpack the parameters. To avoid the `abi.decode` reverting, we ensure that the passed data is not empty
        bool enabled;
        uint walletCap;
        uint txCap;

        if (_params.length != 0) {
            (enabled, walletCap, txCap) = abi.decode(_params, (bool, uint, uint));
        }

        // Set the fair launch settings
        fairLaunchSettings[_poolId] = FairLaunchSettings({
            enabled: enabled,
            walletCap: walletCap,
            txCap: txCap
        });

        emit PoolKeyFairLaunchSettingsUpdated(_poolId, fairLaunchSettings[_poolId]);
    }

    /**
     * Takes the first address parameter and uses ECDSA to recover the signer
     * of the message `keccak256(bytes(msg.sender)).toEthSignedMessageHash()`.
     * The signer is checked against an EnumerableSet of trusted signers.
     *
     * @param _poolKey The pool key of the swap
     * @param _params The parameters of the swap
     * @param _hookData The hook data of the swap
     */
    function trackSwap(
        address _sender,
        PoolKey calldata _poolKey,
        IPoolManager.SwapParams calldata _params,
        BalanceDelta /* _delta */,
        bytes calldata _hookData
    ) public nonReentrant {
        // Ensure that this call is coming from the {PositionManager}
        if (msg.sender != positionManager) {
            revert CallerNotPositionManager();
        }

        PoolId poolId = _poolKey.toId();

        // If the PoolKey was not enabled during flaunching, then we don't need to verify the signature
        FairLaunchSettings memory _fairLaunchSettings = fairLaunchSettings[poolId];
        if (!_fairLaunchSettings.enabled) {
            return;
        }

        // Unpack our _hookData to find the signature. We bypass the initial `referrer` address.
        (, SignedMessage memory signedMessage) = abi.decode(_hookData, (address, SignedMessage));

        // If the PoolKey is enabled and has a zero address signer, then we bypass the signature check
        TrustedPoolKeySigner memory _trustedPoolKeySigner = trustedPoolKeySigner[poolId];
        if (_trustedPoolKeySigner.enabled && _trustedPoolKeySigner.signer == address(0)) {
            return;
        }

        // Verify the deadline is not expired
        if (block.timestamp > signedMessage.deadline) {
            revert DeadlineExpired(signedMessage.deadline);
        }

        // We may be able to determine the sender from the router by using their `msgSender` wrapper, so lets
        // attempt to do that rather than only relying on `tx.origin`. We use a low-level call to check if the
        // function exists first.
        address origin = _determineOrigin(_sender);

        // Create the message hash from the `origin`
        bytes32 messageHash = keccak256(abi.encodePacked(origin, signedMessage.deadline));

        // Generate the message hash
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        if (_usedSignatures[ethSignedMessageHash]) {
            revert SignatureAlreadyUsed();
        }

    	// Recover the signer and confirm that it is a trusted signer
    	(address recoveredSigner,,) = ethSignedMessageHash.tryRecover(signedMessage.signature);

        // Check if the PoolKey has a specific non-zero address signer, then validate against this signer
        if (_trustedPoolKeySigner.enabled) {
            if (recoveredSigner != _trustedPoolKeySigner.signer) {
                revert InvalidSigner(recoveredSigner);
            }
        }
        // If there is no specific PoolKey signer, then we verify that the signer is a trusted signer
        else if (!isTrustedSigner(recoveredSigner)) {
            revert InvalidSigner(recoveredSigner);
        }

        // Check if this is a flipped pool. This call will revert if the PoolKey is invalid.
        (, bool isFlipped) = _discoverMemecoin(_poolKey);

        /**
         * The BalanceDelta will only have a value if we surpassed the fair launch, as we fill the position
         * internally and therefore UniSwap does not have context of the value passed. This poses a problem
         * as if ETH is the `amountSpecified` then we won't have a concrete value to work with.
         * 
         * To remedy this, we need to make a similar estimation as we do in the FairLaunch contract to
         * determine the amount of tokens that the caller will be receiving from their swap.
         */
        uint transactionAmount = _estimateReceivedTokens({
            _poolKey: _poolKey,
            _amountSpecified: _params.amountSpecified,
            _nativeIsZero: !isFlipped
        });

        // If the tx cap is set and the transaction amount has exceeded the cap, then we revert
        (bool hasCap, uint _maxTokensOut) = maxTokensOut(poolId, origin);
        if (hasCap && transactionAmount > _maxTokensOut) {
            revert TransactionCapExceeded(transactionAmount, _maxTokensOut);
        }

        // Increase the amount of the token that the wallet has purchased
        walletPurchasedAmount[poolId][origin] += transactionAmount;

        // Mark the signature as used
        _usedSignatures[ethSignedMessageHash] = true;
    }

    /**
     * Adds a signer to the trusted signers list.
     * 
     * @param _signer The address to add as a trusted signer
     */
    function addTrustedSigner(address _signer) external onlyOwner {
        // Verify that the signer is not the zero address
        if (_signer == address(0)) {
            revert InvalidSigner(_signer);
        }

        // Verify that the signer is not already in the list. If this call returns `true` then it
        // will have been added successfully.
        if (!_trustedSigners.add(_signer)) {
            revert SignerAlreadyAdded(_signer);
        }
        
        emit TrustedSignerUpdated(_signer, true);
    }

    /**
     * Removes a signer from the trusted signers list.
     * 
     * @param _signer The address to remove as a trusted signer
     */
    function removeTrustedSigner(address _signer) external onlyOwner {
        if (!_trustedSigners.remove(_signer)) {
            revert SignerDoesNotExist(_signer);
        }

        emit TrustedSignerUpdated(_signer, false);
    }

    /**
     * Sets a signer against a specific PoolKey.
     * 
     * @dev This function is used to set a signer against a specific PoolKey. If this happens,
     * then the PoolKey will not be able to use any globally trusted signers, and instead must
     * depend on this specific signer.
     * 
     * @dev It is possible for a non-Flaunch PoolKey to be added to our mapping, but this wouldn't
     * be a problem as we only validate this when flaunching.
     *
     * @param _poolKey The pool key to set the signer for
     * @param _signer The address to set as the signer
     */
    function setTrustedPoolKeySigner(PoolKey calldata _poolKey, address _signer) external nonReentrant {
        // Find the memecoin address by finding the alternative to the native token
        (address memecoin,) = _discoverMemecoin(_poolKey);

        // Verify that the caller is the creator of the memecoin
        if (IMemecoin(memecoin).creator() != msg.sender) {
            revert Unauthorized();
        }

        // Set the trusted signer for the PoolKey
        PoolId poolId = _poolKey.toId();
        trustedPoolKeySigner[poolId] = TrustedPoolKeySigner({
            signer: _signer,
            enabled: true
        });

        emit PoolKeySignerUpdated(poolId, _signer);
    }

    /**
     * Checks if an address is a trusted signer.
     * 
     * @param _signer The address to check
     *
     * @return valid_ `True` if the address is a trusted signer, `false` otherwise
     */
    function isTrustedSigner(address _signer) public view returns (bool valid_) {
        valid_ = _trustedSigners.contains(_signer);
    }

    /**
     * Determines the maximum amount of tokens that the caller can purchase based on either the transaction
     * cap or the remaining wallet cap, whichever is lower.
     *
     * @param _poolId The PoolId of the pool
     * @param _origin The origin of the transaction
     *
     * @return hasCap_ If there is a maximum cap imposed
     * @return maxTokensOut_ The maximum amount of tokens that the caller can purchase
     */
    function maxTokensOut(PoolId _poolId, address _origin) public view returns (bool hasCap_, uint maxTokensOut_) {
        // Set our default maximum tokens as the transaction cap
        FairLaunchSettings memory _fairLaunchSettings = fairLaunchSettings[_poolId];
        maxTokensOut_ = _fairLaunchSettings.txCap;

        // Determine if we have a cap set by checking if either cap setting is non-zero
        hasCap_ = _fairLaunchSettings.walletCap != 0 || _fairLaunchSettings.txCap != 0;

        // If a wallet cap is set, then we need to also check the remaining wallet cap available
        if (_fairLaunchSettings.walletCap != 0) {
            uint remainingWalletAmount = _fairLaunchSettings.walletCap - walletPurchasedAmount[_poolId][_origin];

            // If the remaining wallet cap is less than the maximum tokens out, then we update the maximum
            // tokens out to the remaining wallet cap.
            if (maxTokensOut_ == 0 || remainingWalletAmount < maxTokensOut_) {
                maxTokensOut_ = remainingWalletAmount;
            }
        }
    }

    /**
     * Discovers the memecoin address from a PoolKey.
     * 
     * @dev If the memecoin address cannot be found, then the call will revert.

     * @param _poolKey The pool key to discover the memecoin for
     *
     * @return memecoin_ The memecoin address
     * @return isFlipped_ If the memecoin is `currency0`
     */
    function _discoverMemecoin(PoolKey calldata _poolKey) internal view returns (address memecoin_, bool isFlipped_) {
        if (nativeToken == Currency.unwrap(_poolKey.currency0)) {
            memecoin_ = Currency.unwrap(_poolKey.currency1);
        } else if (nativeToken == Currency.unwrap(_poolKey.currency1)) {
            memecoin_ = Currency.unwrap(_poolKey.currency0);
            isFlipped_ = true;
        }

        // If we couldn't discover a memecoin, then the PoolKey is invalid
        if (memecoin_ == address(0)) {
            revert InvalidPoolKey();
        }
    }

    /**
     * When we are filling from our Fair Launch position, we will always be buying tokens
     * with ETH. The amount specified that is passed in, however, could be positive or negative.
     *
     * @dev This is the same logic as `FairLaunch.fillFromPosition`, but with some logic removed.
     *
     * @param _poolKey The PoolKey we are filling from
     * @param _amountSpecified The amount specified in the swap
     * @param _nativeIsZero If our native token is `currency0`
     *
     * @return tokensOut_ The amount of tokens that we will get for the amount specified
     */
    function _estimateReceivedTokens(
        PoolKey memory _poolKey,
        int _amountSpecified,
        bool _nativeIsZero
    ) internal view returns (
        uint tokensOut_
    ) {
        // No tokens, no fun.
        if (_amountSpecified == 0) {
            return 0;
        }

        PoolId poolId = _poolKey.toId();
        FairLaunch.FairLaunchInfo memory info = IPositionManager(positionManager).fairLaunch().fairLaunchInfo(poolId);

        // If we have a negative amount specified, then we have an ETH amount passed in and want
        // to buy as many tokens as we can for that price.
        if (_amountSpecified < 0) {
            tokensOut_ = _getQuoteAtTick(
                info.initialTick,
                uint(-_amountSpecified),
                Currency.unwrap(_nativeIsZero ? _poolKey.currency0 : _poolKey.currency1),
                Currency.unwrap(_nativeIsZero ? _poolKey.currency1 : _poolKey.currency0)
            );
        }
        // Otherwise, if we have a positive amount specified, then we know the number of tokens that
        // are being purchased and need to calculate the amount of ETH required.
        else {
            tokensOut_ = uint(_amountSpecified);
        }

        // If the user has requested more tokens than are available in the fair launch, then we
        // need to strip back the amount that we can fulfill.
        if (tokensOut_ > info.supply) {
            tokensOut_ = info.supply;
        }
    }

    /**
     * Given a tick and a token amount, calculates the amount of token received in exchange.
     *
     * @dev Forked from the `Uniswap/v3-periphery` {OracleLibrary} contract.
     *
     * @param _tick Tick value used to calculate the quote
     * @param _baseAmount Amount of token to be converted
     * @param _baseToken Address of an ERC20 token contract used as the baseAmount denomination
     * @param _quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
     *
     * @return quoteAmount_ Amount of quoteToken received for baseAmount of baseToken
     */
    function _getQuoteAtTick(
        int24 _tick,
        uint _baseAmount,
        address _baseToken,
        address _quoteToken
    ) internal pure returns (
        uint quoteAmount_
    ) {
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(_tick);

        // Calculate `quoteAmount` with better precision if it doesn't overflow when multiplied
        // by itself.
        if (sqrtPriceX96 <= type(uint128).max) {
            uint ratioX192 = uint(sqrtPriceX96) * sqrtPriceX96;
            quoteAmount_ = _baseToken < _quoteToken
                ? FullMath.mulDiv(ratioX192, _baseAmount, 1 << 192)
                : FullMath.mulDiv(1 << 192, _baseAmount, ratioX192);
        } else {
            uint ratioX128 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 64);
            quoteAmount_ = _baseToken < _quoteToken
                ? FullMath.mulDiv(ratioX128, _baseAmount, 1 << 128)
                : FullMath.mulDiv(1 << 128, _baseAmount, ratioX128);
        }
    }

    /**
     * Determines the origin of the transaction.
     * 
     * @param _sender The sender of the transaction
     *
     * @return origin_ The origin of the transaction
     */
    function _determineOrigin(address _sender) internal returns (address origin_) {
        // Set our default origin to the `tx.origin`
        origin_ = tx.origin;

        // If the sender has a `msgSender` function, then we use that to determine the origin
        (bool success, bytes memory data) = _sender.call(abi.encodeWithSignature('msgSender()'));
        if (success && data.length >= 32) {
            origin_ = abi.decode(data, (address));
        }
    }

}