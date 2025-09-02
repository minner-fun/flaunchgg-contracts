// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {TickMath} from '@uniswap/v4-core/src/libraries/TickMath.sol';
import {toBalanceDelta} from '@uniswap/v4-core/src/types/BalanceDelta.sol';
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';

import {PositionManager} from '@flaunch/PositionManager.sol';
import {TrustedSignerFeeCalculator} from '@flaunch/fees/TrustedSignerFeeCalculator.sol';

import {FlaunchTest} from '../FlaunchTest.sol';


contract TrustedSignerFeeCalculatorTest is FlaunchTest {

    /// Store the `tx.origin` we expect in tests
    address internal constant TX_ORIGIN = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

    /// Store a memecoin address that we can test with. This will need to be flaunched during
    /// the flow so that we can test against a valid PoolKey.
    address internal memecoin;
    address internal memecoin2;

    /// The fee calculator we will be testing
    TrustedSignerFeeCalculator feeCalculator;

    /// The PoolKey we will be swapping against
    PoolKey internal poolKey;
    PoolKey internal secondPoolKey;

    /// The signer we will be using
    address internal signer;
    uint internal signerPrivateKey;

    function setUp() public {
        _deployPlatform();

        feeCalculator = new TrustedSignerFeeCalculator(address(flETH), address(positionManager));

        positionManager.setFairLaunchFeeCalculator(feeCalculator);

        // The signer we will be using
        (signer, signerPrivateKey) = makeAddrAndKey('signer');
    }

    /**
     * We need to test that we can add multiple trusted signers and that they can be verified.
     */
    function test_CanAddTrustedSigner() public {
        // Confirm that we cannot add a zero address signer
        vm.expectRevert(abi.encodeWithSelector(TrustedSignerFeeCalculator.InvalidSigner.selector, address(0)));
        feeCalculator.addTrustedSigner(address(0));

        // Confirm that the signer is not already in the list
        assertFalse(feeCalculator.isTrustedSigner(address(1)));

        // Confirm that we can add a valid signer
        vm.expectEmit();
        emit TrustedSignerFeeCalculator.TrustedSignerUpdated(address(1), true);
        feeCalculator.addTrustedSigner(address(1));

        // Confirm that the signer is now in the list
        assertTrue(feeCalculator.isTrustedSigner(address(1)));

        // Confirm that we cannot add the same signer again
        vm.expectRevert(abi.encodeWithSelector(TrustedSignerFeeCalculator.SignerAlreadyAdded.selector, address(1)));
        feeCalculator.addTrustedSigner(address(1));

        // Confirm that we can add a different signer
        vm.expectEmit();
        emit TrustedSignerFeeCalculator.TrustedSignerUpdated(address(2), true);
        feeCalculator.addTrustedSigner(address(2));

        // Confirm that the signer is now in the list
        assertTrue(feeCalculator.isTrustedSigner(address(2)));
    }

    /**
     * We need to test that we can remove trusted signers and that they can no longer be verified.
     */
    function test_CanRemoveTrustedSigner() public {
        // Confirm that we cannot remove a signer that is not in the list
        vm.expectRevert(abi.encodeWithSelector(TrustedSignerFeeCalculator.SignerDoesNotExist.selector, address(1)));
        feeCalculator.removeTrustedSigner(address(1));

        // Confirm that we can add a signer
        feeCalculator.addTrustedSigner(address(1));
        assertTrue(feeCalculator.isTrustedSigner(address(1)));

        // Confirm that we can remove the signer
        vm.expectEmit();
        emit TrustedSignerFeeCalculator.TrustedSignerUpdated(address(1), false);
        feeCalculator.removeTrustedSigner(address(1));

        // Confirm that the signer is no longer in the list
        assertFalse(feeCalculator.isTrustedSigner(address(1)));
    }

    /**
     * We need to test that we can set a signer against a specific PoolKey.
     */
    function test_CanSetPoolKeySigner() public {
        // Flaunch a memecoin
        (poolKey, memecoin) = _flaunchToken(true, 0, 0);

        // Make sure that the signer is not already set
        (address _signer, bool enabled) = feeCalculator.trustedPoolKeySigner(poolKey.toId());
        assertEq(_signer, address(0));
        assertFalse(enabled);

        vm.expectEmit();
        emit TrustedSignerFeeCalculator.PoolKeySignerUpdated(poolKey.toId(), signer);

        // Set the signer
        feeCalculator.setTrustedPoolKeySigner(poolKey, signer);

        // Confirm that the signer is set
        (_signer, enabled) = feeCalculator.trustedPoolKeySigner(poolKey.toId());
        assertEq(_signer, signer);
        assertTrue(enabled);

        // Confirm that the signer is not a globally verified signer
        assertFalse(feeCalculator.isTrustedSigner(_signer));

        // Define our hookData that we will use for our swaps
        uint deadline = 1748952660;
        bytes memory signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);
        bytes memory hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // Flaunch a second memecoin that won't have the trusted signer
        (secondPoolKey, memecoin2) = _flaunchToken(true, 0, 0);

        // Confirm that we cannot swap against a PoolKey that doesn't have the trusted signer
        vm.expectRevert(abi.encodeWithSelector(TrustedSignerFeeCalculator.InvalidSigner.selector, signer));
        _trackSwap(secondPoolKey, 3 ether, hookData, TX_ORIGIN);
    }

    /**
     * We need to test that we cannot set a signer against a PoolKey if the caller is not the creator.
     */
    function test_CannotSetPoolKeySignerIfNotCreator() public {
        // Flaunch a memecoin
        (poolKey, memecoin) = _flaunchToken(true, 0, 0);

        // Prank a user that is not the creator
        vm.startPrank(address(1));

        // Confirm that we cannot set a signer if the caller is not the creator
        vm.expectRevert(UNAUTHORIZED);
        feeCalculator.setTrustedPoolKeySigner(poolKey, signer);

        vm.stopPrank();
    }

    /**
     * We need to test that we cannot set a signer against a PoolKey if the PoolKey is not using flETH.
     */
    function test_CannotSetPoolKeySignerIfNotFlethPoolKey() public {
        // Flaunch a memecoin
        (poolKey, memecoin) = _flaunchToken(true, 0, 0);

        // Modify the PoolKey to use a different currency
        poolKey.currency0 = Currency.wrap(address(3));

        // Confirm that we cannot set a signer against a PoolKey that doesn't use flETH
        vm.expectRevert(abi.encodeWithSelector(TrustedSignerFeeCalculator.InvalidPoolKey.selector));
        feeCalculator.setTrustedPoolKeySigner(poolKey, signer);
    }

    /**
     * Test that we can swap with a valid signer.
     */
    function test_CanSwapWithValidSigner() public {
        // Flaunch a memecoin
        (poolKey, memecoin) = _flaunchToken(true, 0, 0);

        feeCalculator.addTrustedSigner(signer);

        uint deadline = 1748952660;
        bytes memory signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);

        bytes memory hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        _trackSwap(poolKey, 3 ether, hookData, TX_ORIGIN);
    }

    /**
     * Test that we cannot swap with a used signature.
     */
    function test_CannotSwapWithUsedSignature() public {
        // Flaunch a memecoin
        (poolKey, memecoin) = _flaunchToken(true, 0, 0);

        feeCalculator.addTrustedSigner(signer);

        uint deadline = 1748952660;
        bytes memory signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);

        bytes memory hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // Make our initial swap, which can pass fine
        _trackSwap(poolKey, 3 ether, hookData, TX_ORIGIN);

        // Try and make a second swap with the same signature, which should revert
        vm.expectRevert(abi.encodeWithSelector(TrustedSignerFeeCalculator.SignatureAlreadyUsed.selector));
        _trackSwap(poolKey, 3 ether, hookData, TX_ORIGIN);
    }

    /**
     * Test that we cannot swap if the deadline has expired.
     */
    function test_CannotSwapIfDeadlineHasExpired() public {
        // Flaunch a memecoin
        (poolKey, memecoin) = _flaunchToken(true, 0, 0);

        feeCalculator.addTrustedSigner(signer);

        uint deadline = block.timestamp - 1;
        bytes memory signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);

        bytes memory hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        vm.expectRevert(abi.encodeWithSelector(TrustedSignerFeeCalculator.DeadlineExpired.selector, deadline));
        _trackSwap(poolKey, 3 ether, hookData, TX_ORIGIN);
    }

    /**
     * Test that we cannot swap if the signer is invalid.
     */
    function test_CannotSwapWithInvalidSigner() public {
        // Flaunch a memecoin
        (poolKey, memecoin) = _flaunchToken(true, 0, 0);

        uint deadline = 1748952660;
        bytes memory signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);

        bytes memory hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        vm.expectRevert(abi.encodeWithSelector(TrustedSignerFeeCalculator.InvalidSigner.selector, signer));
        _trackSwap(poolKey, 3 ether, hookData, TX_ORIGIN);
    }

    /**
     * We need to test that our swap fee is always the same as the base fee.
     */
    function test_CanDetermineSwapFee(uint _swapAmount, uint16 _baseFee) public view {
        assertEq(feeCalculator.determineSwapFee(poolKey, _getSwapParams(int(_swapAmount)), _baseFee), _baseFee);
    }

    /**
     * Test that we can set fair launch settings for a PoolKey.
     */
    function test_CanSetFlaunchParamsDuringFlaunch(bool _enabled, uint _walletCap, uint _txCap) public {
        // Flaunch a memecoin
        (poolKey, memecoin) = _flaunchToken(_enabled, _walletCap, _txCap);

        // Confirm that the fair launch settings are set
        (bool enabled, uint walletCap, uint txCap) = feeCalculator.fairLaunchSettings(poolKey.toId());
        assertEq(enabled, _enabled);
        assertEq(walletCap, _walletCap);
        assertEq(txCap, _txCap);
    }

    /**
     * Test that we cannot set fair launch settings if the caller is not the creator.
     */
    function test_CannotSetFlaunchParamsDirectly() public {
        // Flaunch a memecoin
        (poolKey, memecoin) = _flaunchToken(false, 0, 0);

        // Make up some fair launch settings
        TrustedSignerFeeCalculator.FairLaunchSettings memory settings = TrustedSignerFeeCalculator.FairLaunchSettings({
            enabled: true,
            walletCap: 10 ether,
            txCap: 5 ether
        });

        // Confirm that we cannot set fair launch settings if the caller is not the creator
        vm.expectRevert(TrustedSignerFeeCalculator.CallerNotPositionManager.selector);
        feeCalculator.setFlaunchParams(poolKey.toId(), abi.encode(settings));
    }

    /**
     * Test that wallet cap is enforced across multiple transactions.
     */
    function test_WalletCapEnforcedAcrossMultipleTransactions() public {
        // Flaunch a memecoin
        (poolKey, memecoin) = _flaunchToken(true, 5 ether, 0);

        feeCalculator.addTrustedSigner(signer);

        uint deadline = 1748952660;
        bytes memory signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);

        bytes memory hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // First transaction: 3 ether (should succeed)
        _trackSwap(poolKey, 3 ether, hookData, TX_ORIGIN);
        
        // Verify the wallet purchased amount is updated correctly
        assertEq(feeCalculator.walletPurchasedAmount(poolKey.toId(), TX_ORIGIN), 3 ether);

        // Generate new signature for second transaction
        deadline = 1748952661;
        signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);
        hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // Second transaction: 2 ether (should succeed, total: 5 ether)
        _trackSwap(poolKey, 2 ether, hookData, TX_ORIGIN);
        
        // Verify the wallet purchased amount is updated correctly
        assertEq(feeCalculator.walletPurchasedAmount(poolKey.toId(), TX_ORIGIN), 5 ether);

        // Generate new signature for third transaction
        deadline = 1748952662;
        signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);
        hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // Third transaction: 1 ether (should fail, would exceed wallet cap of 5 ether: 5 + 1 = 6 > 5)
        vm.expectRevert(abi.encodeWithSelector(TrustedSignerFeeCalculator.TransactionCapExceeded.selector, 1 ether, 0));
        _trackSwap(poolKey, 1 ether, hookData, TX_ORIGIN);
        
        // Verify the wallet purchased amount remains unchanged after failed transaction
        assertEq(feeCalculator.walletPurchasedAmount(poolKey.toId(), TX_ORIGIN), 5 ether);
    }

    /**
     * Test that transaction cap is enforced for individual transactions.
     */
    function test_TransactionCapEnforcedForIndividualTransactions() public {
        // Flaunch a memecoin
        (poolKey, memecoin) = _flaunchToken(true, 0, 2 ether);

        feeCalculator.addTrustedSigner(signer);

        uint deadline = 1748952660;
        bytes memory signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);

        bytes memory hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // Transaction with 3 ether (should fail, exceeds tx cap of 2 ether)
        vm.expectRevert(abi.encodeWithSelector(TrustedSignerFeeCalculator.TransactionCapExceeded.selector, 3 ether, 2 ether));
        _trackSwap(poolKey, 3 ether, hookData, TX_ORIGIN);
    }

    /**
     * Test that wallet cap can be bypassed with zero value.
     */
    function test_WalletCapBypassedWithZeroValue() public {
        // Flaunch a memecoin
        (poolKey, memecoin) = _flaunchToken(true, 0, 0);

        feeCalculator.addTrustedSigner(signer);

        uint deadline = 1748952660;
        bytes memory signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);

        bytes memory hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // Should succeed even with large amounts since caps are set to 0
        _trackSwap(poolKey, 3 ether, hookData, TX_ORIGIN);
        
        // Verify the wallet purchased amount is still tracked even when caps are bypassed
        assertEq(feeCalculator.walletPurchasedAmount(poolKey.toId(), TX_ORIGIN), 3 ether);

        // Second transaction should also succeed
        deadline = 1748952661;
        signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);
        hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );
        _trackSwap(poolKey, 3 ether, hookData, TX_ORIGIN);
        
        // Verify the wallet purchased amount continues to accumulate
        assertEq(feeCalculator.walletPurchasedAmount(poolKey.toId(), TX_ORIGIN), 6 ether);
    }

    /**
     * Test that transaction cap can be bypassed with zero value.
     */
    function test_TransactionCapBypassedWithZeroValue() public {
        // Flaunch a memecoin
        (poolKey, memecoin) = _flaunchToken(true, 10 ether, 0);

        feeCalculator.addTrustedSigner(signer);

        uint deadline = 1748952660;
        bytes memory signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);

        bytes memory hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // Should succeed even with large amounts since tx cap is set to 0
        _trackSwap(poolKey, 3 ether, hookData, TX_ORIGIN);
    }

    /**
     * Test that both wallet cap and transaction cap work together.
     */
    function test_WalletCapAndTransactionCapWorkTogether() public {
        // Flaunch a memecoin
        (poolKey, memecoin) = _flaunchToken(true, 10 ether, 3 ether);

        feeCalculator.addTrustedSigner(signer);

        uint deadline = 1748952660;
        bytes memory signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);

        bytes memory hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // First transaction: 2 ether (should succeed)
        _trackSwap(poolKey, 2 ether, hookData, TX_ORIGIN);

        // Generate new signature for second transaction
        deadline = 1748952661;
        signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);
        hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // Second transaction: 4 ether (should fail, exceeds tx cap of 3 ether)
        vm.expectRevert(abi.encodeWithSelector(TrustedSignerFeeCalculator.TransactionCapExceeded.selector, 4 ether, 3 ether));
        _trackSwap(poolKey, 4 ether, hookData, TX_ORIGIN);
    }

    /**
     * Test that wallet cap is tracked per wallet address.
     */
    function test_WalletCapTrackedPerWalletAddress() public {
        // Flaunch a memecoin
        (poolKey, memecoin) = _flaunchToken(true, 5 ether, 0);

        feeCalculator.addTrustedSigner(signer);

        uint deadline = 1748952660;
        bytes memory signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);

        bytes memory hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // First wallet: 3 ether (should succeed)
        _trackSwap(poolKey, 3 ether, hookData, TX_ORIGIN);
        
        // Verify the first wallet's purchased amount
        assertEq(feeCalculator.walletPurchasedAmount(poolKey.toId(), TX_ORIGIN), 3 ether);
        
        // Generate new signature for different wallet
        deadline = 1748952661;
        signature = _generateSignature(address(2), deadline, signerPrivateKey);
        hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // Second wallet: 4 ether (should succeed, different wallet)
        _trackSwap(poolKey, 4 ether, hookData, address(2));
        
        // Verify the second wallet's purchased amount
        assertEq(feeCalculator.walletPurchasedAmount(poolKey.toId(), address(2)), 4 ether);
        
        // Generate new signature for first wallet
        deadline = 1748952662;
        signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);
        hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // First wallet: 3 ether (should fail, would exceed wallet cap of 5 ether)
        vm.expectRevert(abi.encodeWithSelector(TrustedSignerFeeCalculator.TransactionCapExceeded.selector, 3 ether, 2 ether));
        _trackSwap(poolKey, 3 ether, hookData, TX_ORIGIN);
        
        // Verify the first wallet's purchased amount remains unchanged after failed transaction
        assertEq(feeCalculator.walletPurchasedAmount(poolKey.toId(), TX_ORIGIN), 3 ether);
        
        // Verify the second wallet's purchased amount is unchanged
        assertEq(feeCalculator.walletPurchasedAmount(poolKey.toId(), address(2)), 4 ether);
    }

    /**
     * Test that fair launch settings work with pool key specific signers.
     */
    function test_FairLaunchSettingsWorkWithPoolKeySpecificSigners() public {
        // Flaunch a memecoin
        (poolKey, memecoin) = _flaunchToken(true, 5 ether, 2 ether);

        // Set a pool key specific signer
        feeCalculator.setTrustedPoolKeySigner(poolKey, signer);

        uint deadline = 1748952660;
        bytes memory signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);

        bytes memory hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // Should succeed with valid signer and within caps
        _trackSwap(poolKey, 2 ether, hookData, TX_ORIGIN);

        // Generate new signature for second transaction
        deadline = 1748952661;
        signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);
        hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // Should fail, exceeds tx cap
        vm.expectRevert(abi.encodeWithSelector(TrustedSignerFeeCalculator.TransactionCapExceeded.selector, 3 ether, 2 ether));
        _trackSwap(poolKey, 3 ether, hookData, TX_ORIGIN);
    }

    /**
     * Test that wallet cap logic correctly prevents transactions that would exceed the cap.
     */
    function test_WalletCapLogicCorrectlyPreventsExceedingCap() public {
        // Flaunch a memecoin
        (poolKey, memecoin) = _flaunchToken(true, 5 ether, 0);

        feeCalculator.addTrustedSigner(signer);

        uint deadline = 1748952660;
        bytes memory signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);

        bytes memory hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // First transaction: 3 ether (should succeed)
        _trackSwap(poolKey, 3 ether, hookData, TX_ORIGIN);
        
        // Verify the wallet purchased amount is updated correctly
        assertEq(feeCalculator.walletPurchasedAmount(poolKey.toId(), TX_ORIGIN), 3 ether);

        // Generate new signature for second transaction
        deadline = 1748952661;
        signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);
        hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // Second transaction: 3 ether (should fail, would exceed wallet cap of 5 ether: 3 + 3 = 6 > 5)
        vm.expectRevert(abi.encodeWithSelector(TrustedSignerFeeCalculator.TransactionCapExceeded.selector, 3 ether, 2 ether));
        _trackSwap(poolKey, 3 ether, hookData, TX_ORIGIN);
        
        // Verify the wallet purchased amount remains unchanged after failed transaction
        assertEq(feeCalculator.walletPurchasedAmount(poolKey.toId(), TX_ORIGIN), 3 ether);
    }

    /**
     * Test that wallet cap allows transactions up to the exact cap limit.
     */
    function test_WalletCapAllowsTransactionsUpToExactLimit() public {
        // Flaunch a memecoin
        (poolKey, memecoin) = _flaunchToken(true, 5 ether, 0);

        feeCalculator.addTrustedSigner(signer);

        uint deadline = 1748952660;
        bytes memory signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);

        bytes memory hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // Confirm that we still have 5 ether available
        (bool hasCap, uint maxTokensOut) = feeCalculator.maxTokensOut(poolKey.toId(), TX_ORIGIN);
        assertEq(hasCap, true);
        assertEq(maxTokensOut, 5 ether);

        // First transaction: 3 ether (should succeed)
        _trackSwap(poolKey, 3 ether, hookData, TX_ORIGIN);
        
        // Verify the wallet purchased amount is updated correctly
        assertEq(feeCalculator.walletPurchasedAmount(poolKey.toId(), TX_ORIGIN), 3 ether);

        // Generate new signature for second transaction
        deadline = 1748952661;
        signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);
        hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // Confirm that we still have tokens available
        (hasCap, maxTokensOut) = feeCalculator.maxTokensOut(poolKey.toId(), TX_ORIGIN);
        assertEq(hasCap, true);
        assertEq(maxTokensOut, 2 ether);

        // Second transaction: 2 ether (should succeed, exactly at wallet cap: 3 + 2 = 5)
        _trackSwap(poolKey, 2 ether, hookData, TX_ORIGIN);
        
        // Verify the wallet purchased amount is exactly at the cap
        assertEq(feeCalculator.walletPurchasedAmount(poolKey.toId(), TX_ORIGIN), 5 ether);

        // We should now have no allocation remaining
        (hasCap, maxTokensOut) = feeCalculator.maxTokensOut(poolKey.toId(), TX_ORIGIN);
        assertEq(hasCap, true);
        assertEq(maxTokensOut, 0);

        // Generate new signature for third transaction
        deadline = 1748952662;
        signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);
        hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // Third transaction: 1 ether (should fail, would exceed wallet cap: 5 + 1 = 6 > 5)
        vm.expectRevert(abi.encodeWithSelector(TrustedSignerFeeCalculator.TransactionCapExceeded.selector, 1 ether, 0));
        _trackSwap(poolKey, 1 ether, hookData, TX_ORIGIN);
        
        // Verify the wallet purchased amount remains unchanged after failed transaction
        assertEq(feeCalculator.walletPurchasedAmount(poolKey.toId(), TX_ORIGIN), 5 ether);
    }

    /**
     * Test that wallet purchased amounts are tracked separately for different pool keys.
     */
    function test_WalletPurchasedAmountTrackedSeparatelyPerPoolKey() public {
        // Flaunch a memecoin
        (poolKey, memecoin) = _flaunchToken(true, 10 ether, 0);

        feeCalculator.addTrustedSigner(signer);

        uint deadline = 1748952660;
        bytes memory signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);

        bytes memory hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // First transaction on first pool key: 3 ether
        _trackSwap(poolKey, 3 ether, hookData, TX_ORIGIN);
        
        // Verify the wallet purchased amount for the first pool key
        assertEq(feeCalculator.walletPurchasedAmount(poolKey.toId(), TX_ORIGIN), 3 ether);

        // Flaunch a memecoin
        (secondPoolKey, memecoin) = _flaunchToken(true, 5 ether, 0);

        // Generate new signature for second pool key
        deadline = 1748952661;
        signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);
        hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        // First transaction on second pool key: 2 ether
        _trackSwap(secondPoolKey, 2 ether, hookData, TX_ORIGIN);
        
        // Verify the wallet purchased amounts are tracked separately
        assertEq(feeCalculator.walletPurchasedAmount(poolKey.toId(), TX_ORIGIN), 3 ether);
        assertEq(feeCalculator.walletPurchasedAmount(secondPoolKey.toId(), TX_ORIGIN), 2 ether);

        // Verify that a third wallet has zero amounts for both pool keys
        assertEq(feeCalculator.walletPurchasedAmount(poolKey.toId(), address(999)), 0);
        assertEq(feeCalculator.walletPurchasedAmount(secondPoolKey.toId(), address(999)), 0);
    }

    function test_canPremineWithTrustedSigner(
        uint _initialTokenFairLaunch,
        uint _premineAmount,
        address _creator,
        uint _initialPrice
    ) public {
        // Ensure that the creator is not a zero address, as this will revert
        vm.assume(_creator != address(0));

        // Ensure that our initial token supply is valid (InvalidInitialSupply)
        vm.assume(_initialTokenFairLaunch <= flaunch.MAX_FAIR_LAUNCH_TOKENS());

        // Ensure that our premine does not exceed the fair launch (PremineExceedsInitialAmount)
        vm.assume(_premineAmount > 0 && _premineAmount <= _initialTokenFairLaunch);

        // Provide our user with enough FLETH to make the premine swap
        deal(address(this), 4000e27);
        // {PoolManager} must have some initial flETH balance to serve `take()` requests in our hook
        deal(address(flETH), address(poolManager), 1000e27 ether);

        // Case 1: Trusted Signer is set but not enabled for the token
        flaunchZap.flaunch{value: 1000e27}({
            _flaunchParams: PositionManager.FlaunchParams({
                name: 'FlaunchZap',
                symbol: 'ZAP',
                tokenUri: 'ipfs://123',
                initialTokenFairLaunch: _initialTokenFairLaunch,
                fairLaunchDuration: 30 minutes,
                premineAmount: _premineAmount,
                creator: _creator,
                creatorFeeAllocation: 80_00,
                flaunchAt: 0,
                initialPriceParams: abi.encode(_initialPrice),
                feeCalculatorParams: bytes('')
            }),
            _premineSwapHookData: bytes('')
        });

        // Case 2: Trusted Signer is set and enabled for the token
        feeCalculator.addTrustedSigner(signer);
        uint deadline = 1748952660;
        bytes memory signature = _generateSignature(TX_ORIGIN, deadline, signerPrivateKey);
        bytes memory hookData = abi.encode(
            address(0),
            TrustedSignerFeeCalculator.SignedMessage({
                deadline: deadline, 
                signature: signature
            })
        );

        flaunchZap.flaunch{value: 1000e27}({
            _flaunchParams: PositionManager.FlaunchParams({
                name: 'FlaunchZap',
                symbol: 'ZAP',
                tokenUri: 'ipfs://123',
                initialTokenFairLaunch: _initialTokenFairLaunch,
                fairLaunchDuration: 30 minutes,
                premineAmount: _premineAmount,
                creator: _creator,
                creatorFeeAllocation: 80_00,
                flaunchAt: 0,
                initialPriceParams: abi.encode(_initialPrice),
                feeCalculatorParams: abi.encode(true, 0, 0) // Trusted Signer enabled
            }),
            _premineSwapHookData: hookData
        });
    }

    /**
     * When testing on Base Sepolia we found an issue in which the transaction amount was not being
     * correctly calculated. This test ensures that the transaction amount is correctly calculated.
     */
    function test_TransactionAmountIsCorrectlyCalculated() public forkBaseSepoliaBlock(29134187) {
        // Update the deployed TrustedSignerFeeCalculator with the new implementation
        deployCodeTo(
            'TrustedSignerFeeCalculator.sol',
            abi.encode(
                0x79FC52701cD4BE6f9Ba9aDC94c207DE37e3314eb,  // flETH
                0x4E7cB1e6800a7B297B38BddcecAF9Ca5b6616FDC   // PositionManager
            ),
            0x7c1A3Eb8d3Eb166B333b3a9bD40C5CA03931eB34
        );
        
        vm.startPrank(0x498E93Bc04955fCBAC04BCF1a3BA792f01Dbaa96, 0x498E93Bc04955fCBAC04BCF1a3BA792f01Dbaa96);

        0x492E6456D9528771018DeB9E87ef7750EF184104.call(
            hex'24856bc300000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000210040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000005c00000000000000000000000000000000000000000000000000000000000000560000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000003090c0f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000004600000000000000000000000000000000000000000000000000000000000000380000000000000000000000000000000000000000000000000000000000000002000000000000000000000000071eab7365e7ff1abcc993441846a85ec04a923e900000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000033b2e3c9fd0803ce80000000000000000000000000000000000000000000000033b2e3c9fd0803ce800000000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003c0000000000000000000000004bd2ca15286c96e4e731337de8b375da6841e88800000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000079fc52701cd4be6f9ba9adc94c207de37e3314eb0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003c0000000000000000000000004e7cb1e6800a7b297b38bddcecaf9ca5b6616fdc00000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000688c7ad900000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000041c3fdcdaad1b4f1b9a86757ce21d24a8d36678ac00099d8565b5e628056ead7e26c29f40803507c40a75fd652a5c16b548a5396e06194250e9a12a88fb896de9b1b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000033b2e3c9fd0803ce8000000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000071eab7365e7ff1abcc993441846a85ec04a923e90000000000000000000000000000000000000000033b2e3c9fd0803ce800000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000498e93bc04955fcbac04bcf1a3ba792f01dbaa960000000000000000000000000000000000000000000000000000000000000000'
        );

        vm.stopPrank();        
    }

    /**
     * Triggers a `trackSwap` call with the given hook data, amount and pool key.
     * 
     * @param _poolKey The pool key to use for the swap
     * @param _amount The amount to swap
     * @param _hookData The hook data to track the swap with
     */
    function _trackSwap(PoolKey memory _poolKey, uint _amount, bytes memory _hookData, address _origin) internal {
        // Set the `msg.sender` to the `positionManager` and the `tx.origin` to the `_origin`
        vm.startPrank(address(positionManager), _origin);

        feeCalculator.trackSwap(
            address(1), // We track the swap using `tx.origin`, so this is ignored
            _poolKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: int(_amount),
                sqrtPriceLimitX96: uint160(int160(TickMath.minUsableTick(_poolKey.tickSpacing)))
            }),
            toBalanceDelta(
                int128(int(_poolKey.currency1 == Currency.wrap(address(flETH)) ? 0 : _amount)),
                int128(int(_poolKey.currency0 == Currency.wrap(address(flETH)) ? 0 : _amount))
            ),
            _hookData
        );

        vm.stopPrank();
    }

    /**
     * Generates a signature for a given wallet, deadline and private key.
     * 
     * @param _wallet The wallet to generate a signature for
     * @param _deadline The deadline for the signature
     * @param _privateKey The private key to use to generate the signature
     *
     * @return signature_ The encoded signature
     */
    function _generateSignature(address _wallet, uint _deadline, uint _privateKey) internal pure returns (bytes memory signature_) {
        bytes32 hash = keccak256(abi.encodePacked(_wallet, _deadline));
        bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, message); 
        signature_ = abi.encodePacked(r, s, v);
    }

    /**
     * Flaunches a memecoin with the given fair launch settings.
     * 
     * @param _enabled Whether the fair launch settings are enabled
     * @param _walletCap The wallet cap for the fair launch
     * @param _txCap The transaction cap for the fair launch
     *
     * @return poolKey_ The PoolKey of the memecoin
     * @return memecoin_ The address of the memecoin
     */
    function _flaunchToken(bool _enabled, uint _walletCap, uint _txCap) internal returns (PoolKey memory poolKey_, address memecoin_) {
        // Flaunch a memecoin
        memecoin_ = positionManager.flaunch(
            PositionManager.FlaunchParams({
                name: 'Token Name',
                symbol: 'TOKEN',
                tokenUri: 'https://flaunch.gg/',
                initialTokenFairLaunch: supplyShare(50),
                fairLaunchDuration: 30 minutes,
                premineAmount: 0,
                creator: address(this),
                creatorFeeAllocation: 0,
                flaunchAt: 0,
                initialPriceParams: abi.encode(''),
                feeCalculatorParams: abi.encode(_enabled, _walletCap, _txCap)
            })
        );

        // Get the PoolKey from the memecoin address
        poolKey_ = positionManager.poolKey(memecoin_);
    }

}