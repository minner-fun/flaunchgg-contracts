// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from 'forge-std/console.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {CustomRevert} from '@uniswap/v4-core/src/libraries/CustomRevert.sol';
import {Hooks, IHooks} from '@uniswap/v4-core/src/libraries/Hooks.sol';
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import {PoolIdLibrary, PoolId} from '@uniswap/v4-core/src/types/PoolId.sol';
import {TickMath} from '@uniswap/v4-core/src/libraries/TickMath.sol';

import {FairLaunch} from '@flaunch/hooks/FairLaunch.sol';
import {FeeDistributor} from '@flaunch/hooks/FeeDistributor.sol';
import {Flaunch} from '@flaunch/Flaunch.sol';
import {InitialPrice} from '@flaunch/price/InitialPrice.sol';
import {PositionManager} from '@flaunch/PositionManager.sol';
import {ProtocolRoles} from '@flaunch/libraries/ProtocolRoles.sol';
import {TokenSupply} from '@flaunch/libraries/TokenSupply.sol';

import {FlaunchTest} from '../FlaunchTest.sol';

import {TrustedSignerFeeCalculator} from '@flaunch/fees/TrustedSignerFeeCalculator.sol';
import {StaticFeeCalculator} from '@flaunch/fees/StaticFeeCalculator.sol';
import {toBalanceDelta} from '@uniswap/v4-core/src/types/BalanceDelta.sol';


contract FairLaunchTest is FlaunchTest {

    using PoolIdLibrary for PoolKey;

    /// Store the `tx.origin` we expect in tests
    address internal constant TX_ORIGIN = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

    PoolKey internal EXPECTED_POOL_KEY;
    PoolKey internal EXPECTED_FLIPPED_POOL_KEY;

    PoolId internal immutable EXPECTED_POOL_ID;
    PoolId internal immutable EXPECTED_FLIPPED_POOL_ID;

    uint FAIR_LAUNCH_DURATION = 30 minutes;

    address MEMECOIN_UNFLIPPED = 0xF2C9428E4C5657e1Ea0c45C3ffD227025CA05f00;
    address MEMECOIN_FLIPPED = 0xEC82FeB3eD96601CeB4563EA04Fa9A89b12b9D7a;

    constructor () {
        // Deploy our platform
        _deployPlatform();

        // Set our expected PoolKey. The `currency1` address is the deterministic address of the `Memecoin`
        // that will be created when we run `positionManager.flaunch`.
        EXPECTED_POOL_KEY = _normalizePoolKey(PoolKey({
            currency0: Currency.wrap(address(WETH)),
            currency1: Currency.wrap(MEMECOIN_UNFLIPPED),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(address(positionManager))
        }));
        EXPECTED_POOL_ID = EXPECTED_POOL_KEY.toId();

        EXPECTED_FLIPPED_POOL_KEY = _normalizePoolKey(PoolKey({
            currency0: Currency.wrap(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF),
            currency1: Currency.wrap(MEMECOIN_FLIPPED),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(address(positionManager))
        }));
        EXPECTED_FLIPPED_POOL_ID = EXPECTED_FLIPPED_POOL_KEY.toId();
    }

    function test_CanCreateFairLaunchPool(uint _supply, bool _flipped) public flipTokens(_flipped) {
        // Ensure we have a valid initial supply
        vm.assume(_supply <= flaunch.MAX_FAIR_LAUNCH_TOKENS());

        if (!_flipped) {
            vm.expectEmit();
            emit PositionManager.PoolStateUpdated(EXPECTED_POOL_ID, 112045541949572279837463876454, 6931, 0, 0, 0);
        } else {
            vm.expectEmit();
            emit PositionManager.PoolStateUpdated(EXPECTED_FLIPPED_POOL_ID, 56022770974786139918731938227, -6932, 0, 0, 0);
        }

        // Create our Memecoin
        address memecoin = positionManager.flaunch(PositionManager.FlaunchParams('name', 'symbol', 'https://token.gg/', _supply, FAIR_LAUNCH_DURATION, 0, address(this), 0, 0, abi.encode(''), abi.encode(1_000)));

        // Confirm the balances of our two contracts
        assertEq(IERC20(memecoin).balanceOf(address(positionManager)), TokenSupply.INITIAL_SUPPLY);
        assertEq(IERC20(memecoin).balanceOf(address(poolManager)), 0);
    }

    function test_CannotCreateFairLaunchPoolWithHighInitialSupply(uint _supply, bool _flipped) public flipTokens(_flipped) {
        // Ensure we have an invalid initial supply
        vm.assume(_supply > flaunch.MAX_FAIR_LAUNCH_TOKENS());

        vm.expectRevert(abi.encodeWithSelector(Flaunch.InvalidInitialSupply.selector, _supply));
        positionManager.flaunch(PositionManager.FlaunchParams('name', 'symbol', 'https://token.gg/', _supply, FAIR_LAUNCH_DURATION, 0, address(this), 0, 0, abi.encode(''), abi.encode(1_000)));
    }

    function test_CanGetInsideFairLaunchWindow(uint _timestamp, bool _flipped) public flipTokens(_flipped) {
        vm.assume(_timestamp >= block.timestamp);
        vm.assume(_timestamp < block.timestamp + FAIR_LAUNCH_DURATION);

        positionManager.flaunch(PositionManager.FlaunchParams('name', 'symbol', 'https://token.gg/', supplyShare(50), FAIR_LAUNCH_DURATION, 0, address(this), 0, 0, abi.encode(''), abi.encode(1_000)));

        vm.warp(_timestamp);
        assertTrue(fairLaunch.inFairLaunchWindow(poolId(_flipped)));
    }

    function test_CanGetOutsideFairLaunchWindow(uint48 _timestamp, bool _flipped) public flipTokens(_flipped) {
        vm.assume(_timestamp >= block.timestamp + FAIR_LAUNCH_DURATION);

        positionManager.flaunch(PositionManager.FlaunchParams('name', 'symbol', 'https://token.gg/', supplyShare(50), FAIR_LAUNCH_DURATION, 0, address(this), 0, 0, abi.encode(''), abi.encode(1_000)));

        vm.warp(_timestamp);
        assertFalse(fairLaunch.inFairLaunchWindow(poolId(_flipped)));
    }

    // /// @dev Debug test to reproduce specific failure case from fuzz testing
    // function test_Debug_CanRebalancePoolAfterFairLaunch_Flipped() public flipTokens(true) {
    //     uint _flSupplyPercent = 3;
    //     uint _flETHBuy = 24959;
        
    //     console.log("=== DEBUG TEST: Specific Failure Case ===");
    //     console.log("Flipped: true");
    //     console.log("Supply Percent:", _flSupplyPercent);
    //     console.log("ETH Buy Amount:", _flETHBuy);
    //     console.log("WETH Address:", address(WETH));
        
    //     deal(address(WETH), address(poolManager), 1000e27 ether);
        
    //     uint fairLaunchSupply = supplyShare(_flSupplyPercent);
    //     console.log("Fair Launch Supply:", fairLaunchSupply);

    //     // Create our memecoin
    //     address memecoin = positionManager.flaunch(
    //         PositionManager.FlaunchParams(
    //             'name', 
    //             'symbol', 
    //             'https://token.gg/', 
    //             fairLaunchSupply, 
    //             FAIR_LAUNCH_DURATION, 
    //             0, 
    //             address(this), 
    //             0, 
    //             0, 
    //             abi.encode(''), 
    //             abi.encode(1_000)
    //         )
    //     );
    //     console.log("Memecoin created:", memecoin);
        
    //     // Check pool state
    //     PoolKey memory key = poolKey(true);
    //     PoolId pid = poolId(true);
    //     console.log("Pool ID:", uint256(PoolId.unwrap(pid)));
    //     console.log("Pool currency0:", Currency.unwrap(key.currency0));
    //     console.log("Pool currency1:", Currency.unwrap(key.currency1));
        
    //     (uint160 sqrtPriceX96, int24 tick,,) = poolManager.getSlot0(pid);
    //     console.log("Pool sqrtPriceX96:", sqrtPriceX96);
    //     console.log("Pool tick:", int256(tick));
        
    //     // Check if pool is initialized
    //     if (sqrtPriceX96 == 0) {
    //         console.log("ERROR: Pool is NOT initialized!");
    //     } else {
    //         console.log("Pool is initialized");
    //     }

    //     // Give tokens and approve for swap
    //     deal(address(WETH), address(this), 2 ether);
    //     WETH.approve(address(poolSwap), type(uint).max);

    //     // Action our swap during Fair Launch
    //     console.log("Attempting swap during Fair Launch...");
    //     poolSwap.swap(
    //         key,
    //         IPoolManager.SwapParams({
    //             zeroForOne: false, // !flipped = !true = false
    //             amountSpecified: -int(_flETHBuy),
    //             sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
    //         })
    //     );
    //     console.log("First swap completed");
        
    //     // End Fair Launch
    //     vm.warp(block.timestamp + FAIR_LAUNCH_DURATION + 1);
    //     assertFalse(fairLaunch.inFairLaunchWindow(pid));
    //     console.log("Fair Launch ended");

    //     // remaining Fair Launch supply
    //     FairLaunch.FairLaunchInfo memory fairLaunchInfo = fairLaunch.fairLaunchInfo(pid);
    //     uint flSupplyToBurn = fairLaunchInfo.supply;
    //     console.log("Remaining FL supply to burn:", flSupplyToBurn);

    //     // Action our swap after Fair Launch for rebalancing
    //     console.log("Attempting swap after Fair Launch for rebalancing...");
    //     poolSwap.swap(
    //         key,
    //         IPoolManager.SwapParams({
    //             zeroForOne: false,
    //             amountSpecified: -1 ether,
    //             sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
    //         })
    //     );
    //     console.log("Rebalancing swap completed");

    //     // confirm that the unsold memecoin fair launch supply was burned
    //     uint burnedAmount = IERC20(memecoin).balanceOf(positionManager.BURN_ADDRESS());
    //     console.log("Burned amount:", burnedAmount);
    //     assertEq(burnedAmount, flSupplyToBurn, 'Invalid burn amount');
    // }

    function test_CanRebalancePoolAfterFairLaunch_Single() public flipTokens(true) {
        bool _flipped = true;
        uint _flSupplyPercent = 3;
        uint _flETHBuy = 24959;

        console.log("=== DEBUG TEST: Specific Failure Case ===");
        console.log("Flipped: true");
        console.log("Supply Percent:", _flSupplyPercent);
        console.log("ETH Buy Amount:", _flETHBuy);
        console.log("WETH Address:", address(WETH));

        deal(address(WETH), address(poolManager), 1000e27 ether);
        // vm.assume(_flSupplyPercent > 0 && _flSupplyPercent < 69);
        // vm.assume(_flETHBuy > 0 && _flETHBuy < 1 ether);
        uint fairLaunchSupply = supplyShare(_flSupplyPercent);
        console.log("Fair Launch Supply:", fairLaunchSupply);

        // Create our memecoin
        address memecoin = positionManager.flaunch(PositionManager.FlaunchParams('name', 'symbol', 'https://token.gg/', fairLaunchSupply, FAIR_LAUNCH_DURATION, 0, address(this), 0, 0, abi.encode(''), abi.encode(1_000)));
        console.log("Memecoin created:", memecoin);

        // Give tokens and approve for swap
        deal(address(WETH), address(this), 2 ether);
        WETH.approve(address(poolSwap), type(uint).max);

        // Action our swap during Fair Launch
        poolSwap.swap(
            poolKey(_flipped),
            IPoolManager.SwapParams({
                zeroForOne: !_flipped,
                amountSpecified: -int(_flETHBuy),
                sqrtPriceLimitX96: !_flipped ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            })
        );
        
        // End Fair Launch
        vm.warp(block.timestamp + FAIR_LAUNCH_DURATION + 1);
        assertFalse(fairLaunch.inFairLaunchWindow(poolId(_flipped)));

        // remaining Fair Launch supply
        FairLaunch.FairLaunchInfo memory fairLaunchInfo = fairLaunch.fairLaunchInfo(poolId(_flipped));
        uint flSupplyToBurn = fairLaunchInfo.supply;

        // Action our swap after Fair Launch for rebalancing
        poolSwap.swap(
            poolKey(_flipped),
            IPoolManager.SwapParams({
                zeroForOne: !_flipped,
                amountSpecified: -1 ether,
                sqrtPriceLimitX96: !_flipped ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            })
        );

        // confirm that the unsold memecoin fair launch supply was burned
        assertEq(IERC20(memecoin).balanceOf(positionManager.BURN_ADDRESS()), flSupplyToBurn, 'Invalid burn amount');
    }

    function test_CanRebalancePoolAfterFairLaunch(bool _flipped, uint _flSupplyPercent, uint _flETHBuy) public flipTokens(_flipped) {
        deal(address(WETH), address(poolManager), 1000e27 ether);
        vm.assume(_flSupplyPercent > 0 && _flSupplyPercent < 69);
        vm.assume(_flETHBuy > 0 && _flETHBuy < 1 ether);

        // Create our memecoin
        address memecoin = positionManager.flaunch(PositionManager.FlaunchParams('name', 'symbol', 'https://token.gg/', supplyShare(_flSupplyPercent), FAIR_LAUNCH_DURATION, 0, address(this), 0, 0, abi.encode(''), abi.encode(1_000)));

        // Give tokens and approve for swap
        deal(address(WETH), address(this), 2 ether);
        WETH.approve(address(poolSwap), type(uint).max);

        // Action our swap during Fair Launch
        poolSwap.swap(
            poolKey(_flipped),
            IPoolManager.SwapParams({
                zeroForOne: !_flipped,
                amountSpecified: -int(_flETHBuy),
                sqrtPriceLimitX96: !_flipped ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            })
        );
        
        // End Fair Launch
        vm.warp(block.timestamp + FAIR_LAUNCH_DURATION + 1);
        assertFalse(fairLaunch.inFairLaunchWindow(poolId(_flipped)));

        // remaining Fair Launch supply
        FairLaunch.FairLaunchInfo memory fairLaunchInfo = fairLaunch.fairLaunchInfo(poolId(_flipped));
        uint flSupplyToBurn = fairLaunchInfo.supply;

        // Action our swap after Fair Launch for rebalancing
        poolSwap.swap(
            poolKey(_flipped),
            IPoolManager.SwapParams({
                zeroForOne: !_flipped,
                amountSpecified: -1 ether,
                sqrtPriceLimitX96: !_flipped ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            })
        );

        // confirm that the unsold memecoin fair launch supply was burned
        assertEq(IERC20(memecoin).balanceOf(positionManager.BURN_ADDRESS()), flSupplyToBurn, 'Invalid burn amount');
    }

    /**
     * FairLaunch swaps will always be NATIVE for CT.
     *
     * SPECIFIED means that we want the CT amount and fees will be NATIVE
     * UNSPECIFIED means that we want the NATIVE amount and fees will be CT
     *
     * FLIPPED and UNFLIPPED should not make any difference aside from a slight tick
     * variance, meaning that we may have a dust variation.
     *
     * - FLIPPED tick (-6932)
     * - UNFLIPPED tick (6931)
     *
     * The test suite is set up to understand that 1 ETH : 2 TOKEN (0.5 ETH : 1 TOKEN).
     */
    function test_CanCaptureRevenueAndSupplyChange(bool _specified, bool _flipped, bool _fees) public flipTokens(_flipped) {
        // If we have no fees fuzzed, then we disable pool swap fees
        if (!_fees) {
            positionManager.setFeeDistribution(
                FeeDistributor.FeeDistribution({
                    swapFee: 0,
                    referrer: 0,
                    protocol: 0,
                    active: true
                })
            );
        }
        // Otherwise, ensure that we send 100% to the protocol to avoid the bidWall share going
        // back into the `fairLaunchRevenue` due to the `bidWall` pre-allocation.
        else {
            positionManager.setFeeDistribution(
                FeeDistributor.FeeDistribution({
                    swapFee: 1_00,
                    referrer: 0,
                    protocol: 10_00,
                    active: true
                })
            );
        }

        deal(address(WETH), address(poolManager), 1000e27 ether);

        // Create our memecoin
        positionManager.flaunch(PositionManager.FlaunchParams('name', 'symbol', 'https://token.gg/', supplyShare(50), FAIR_LAUNCH_DURATION, 0, address(this), 0, 0, abi.encode(''), abi.encode(1_000)));
        assertTrue(fairLaunch.inFairLaunchWindow(poolId(_flipped)));

        // Give tokens and approve for swap
        deal(address(WETH), address(this), 10 ether);
        WETH.approve(address(poolSwap), type(uint).max);

        // Action our swap to buy token from the pool
        poolSwap.swap(
            poolKey(_flipped),
            IPoolManager.SwapParams({
                zeroForOne: !_flipped,
                amountSpecified: _specified ? int(1 ether) : -1 ether,
                sqrtPriceLimitX96: !_flipped ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            })
        );

        uint ethIn;
        uint tokenOut;
        uint fees;

        if (_specified) {
            tokenOut = 1 ether;
            ethIn = _flipped ? 499990919207187760 : 500040918299108479;

            if (_fees) {
                fees = _flipped ? 4999909192071877 : 5000409182991084;
            }
        } else {
            ethIn = 1 ether;
            tokenOut = _flipped ? 2000036323830947322 : 1999836340196927629;
        }

        // Confirm that our revenue and supply values are correct
        FairLaunch.FairLaunchInfo memory fairLaunchInfo = fairLaunch.fairLaunchInfo(poolId(_flipped));
        assertEq(fairLaunchInfo.revenue, ethIn - fees, 'Invalid revenue');
        assertEq(fairLaunchInfo.supply, supplyShare(50) - tokenOut, 'Invalid token');

        // Confirm we hold at least the expected revenue in the contract
        assertGe(
            IERC20(positionManager.getNativeToken()).balanceOf(address(positionManager)),
            ethIn - fees
        );
    }

    /// @dev This also test that we can sell after the Fair Launch window has ended
    function test_CannotSellTokenDuringFairLaunchWindow(bool _flipped) public flipTokens(_flipped) {
        deal(address(WETH), address(poolManager), 1000e27 ether);

        // Create our memecoin
        address memecoin = positionManager.flaunch(PositionManager.FlaunchParams('name', 'symbol', 'https://token.gg/', supplyShare(50), FAIR_LAUNCH_DURATION, 0, address(this), 0, 0, abi.encode(''), abi.encode(1_000)));

        vm.warp(block.timestamp + FAIR_LAUNCH_DURATION - 1);
        assertTrue(fairLaunch.inFairLaunchWindow(poolId(_flipped)), 'Should be in fair launch');

        // Give tokens and approve for swap
        deal(address(WETH), address(this), 1 ether);
        WETH.approve(address(poolSwap), type(uint).max);

        // Action our swap to buy token from the pool
        poolSwap.swap(
            poolKey(_flipped),
            IPoolManager.SwapParams({
                zeroForOne: !_flipped,
                amountSpecified: -1 ether,
                sqrtPriceLimitX96: !_flipped ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            })
        );

        // Now try and sell the token back into the pool
        IERC20(memecoin).approve(address(poolSwap), type(uint).max);
        int sellAmountSpecified = -int(IERC20(memecoin).balanceOf(address(this)));

        // Expect our error wrapped within the `FailedHookCall` response
        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(positionManager),
                IHooks.beforeSwap.selector,
                abi.encodeWithSelector(FairLaunch.CannotSellTokenDuringFairLaunch.selector),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );

        poolSwap.swap(
            poolKey(_flipped),
            IPoolManager.SwapParams({
                zeroForOne: _flipped,
                amountSpecified: sellAmountSpecified,
                sqrtPriceLimitX96: _flipped ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            })
        );

        // Move forward to fair launch window expiration and attempt swap again (successfully)
        vm.warp(block.timestamp + FAIR_LAUNCH_DURATION + 1);
        assertFalse(fairLaunch.inFairLaunchWindow(poolId(_flipped)), 'Should not be in fair launch');

        poolSwap.swap(
            poolKey(_flipped),
            IPoolManager.SwapParams({
                zeroForOne: _flipped,
                amountSpecified: sellAmountSpecified,
                sqrtPriceLimitX96: _flipped ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            })
        );
    }

    function test_CanGetFeesFromFairLaunchSwap(bool _flipped) public flipTokens(_flipped) {
        deal(address(WETH), address(poolManager), 1000e27 ether);

        // Create our memecoin with tokens in fair launch
        positionManager.flaunch(PositionManager.FlaunchParams('name', 'symbol', 'https://token.gg/', supplyShare(50), FAIR_LAUNCH_DURATION, 0, address(this), 0, 0, abi.encode(''), abi.encode(1_000)));

        // We should currently be within the FairLaunch window
        assertTrue(fairLaunch.inFairLaunchWindow(poolId(_flipped)));

        // Deal enough ETH to fulfill the entire FairLaunch position
        deal(address(WETH), address(this), 100e27 ether);
        WETH.approve(address(poolSwap), type(uint).max);

        // Perfect a swap with ETH as the unspecified token
        poolSwap.swap(
            poolKey(_flipped),
            IPoolManager.SwapParams({
                zeroForOne: !_flipped,
                amountSpecified: 0.5 ether,
                sqrtPriceLimitX96: !_flipped ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            })
        );

        // Perfect a swap with non-ETH as the unspecified token
        poolSwap.swap(
            poolKey(_flipped),
            IPoolManager.SwapParams({
                zeroForOne: !_flipped,
                amountSpecified: -0.5 ether,
                sqrtPriceLimitX96: !_flipped ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            })
        );

        // Pass time
        vm.warp(block.timestamp + 1 days);

        for (uint i; i < 1; ++i) {
            // We should currently be within the FairLaunch window
            assertFalse(fairLaunch.inFairLaunchWindow(poolId(_flipped)));

            // Action a swap that will rebalance
            poolSwap.swap(
                poolKey(_flipped),
                IPoolManager.SwapParams({
                    zeroForOne: !_flipped,
                    amountSpecified: -0.1 ether,
                    sqrtPriceLimitX96: !_flipped ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
                })
            );

            vm.warp(block.timestamp + 5);
        }
    }

    function test_CanBuyTokenAtSamePriceDuringFairLaunch(bool _flipped) public flipTokens(_flipped) {
        deal(address(WETH), address(poolManager), 1000e27 ether);

        // Create our memecoin with tokens in fair launch
        positionManager.flaunch(PositionManager.FlaunchParams('name', 'symbol', 'https://token.gg/', supplyShare(50), FAIR_LAUNCH_DURATION, 0, address(this), 0, 0, abi.encode(''), abi.encode(1_000)));

        // We should currently be within the FairLaunch window
        assertTrue(fairLaunch.inFairLaunchWindow(poolId(_flipped)));

        // Get the starting pool manager ETH balance
        uint poolManagerEth = WETH.balanceOf(address(poolManager));

        // Deal enough ETH to fulfill the entire FairLaunch position
        deal(address(WETH), address(this), 100e27 ether);
        WETH.approve(address(poolSwap), type(uint).max);

        uint startBalance = WETH.balanceOf(address(this));
        uint ethSpent;

        // Action our swap to buy all of the FairLaunch tokens from the pool
        uint expectedEthCost;
        uint tokenBuyAmount = supplyShare(5);

        // We stop just shy of the limit as we don't want to go over the threshold
        for (uint i = tokenBuyAmount; i <= supplyShare(45);) {
            uint loopStartBalance = WETH.balanceOf(address(this));

            poolSwap.swap(
                poolKey(_flipped),
                IPoolManager.SwapParams({
                    zeroForOne: !_flipped,
                    amountSpecified: int(tokenBuyAmount),
                    sqrtPriceLimitX96: !_flipped ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
                })
            );

            // Capture the first buy cost
            if (expectedEthCost == 0) {
                expectedEthCost = startBalance - WETH.balanceOf(address(this));
            }

            // Confirm the amount of ETH spent the same each time
            uint iterationEthCost = loopStartBalance - WETH.balanceOf(address(this));
            assertEq(expectedEthCost, iterationEthCost, 'Invalid ETH spent');

            ethSpent += iterationEthCost;

            address memecoin = _flipped ? MEMECOIN_FLIPPED : MEMECOIN_UNFLIPPED;

            // Confirm that we receive _just about_ the right amount of token
            assertApproxEqRel(
                IERC20(memecoin).balanceOf(address(this)),
                uint(i),
                0.000001 ether, // 0.0001%
                'Invalid Memecoin balance'
            );

            // Confirm that the expected people are holding the expected token balances
            assertEq(IERC20(memecoin).balanceOf(address(this)), i, 'Invalid user balance');
            assertEq(IERC20(memecoin).balanceOf(address(fairLaunch)), 0, 'Invalid FairLaunch balance');
            assertEq(IERC20(memecoin).balanceOf(address(positionManager)), TokenSupply.INITIAL_SUPPLY - i, 'Invalid PositionManager balance');
            assertEq(IERC20(memecoin).balanceOf(address(poolManager)), 0, 'Invalid PoolManager balance');

            assertEq(WETH.balanceOf(address(this)), startBalance - ethSpent, 'Invalid user ETH balance');
            assertEq(WETH.balanceOf(address(fairLaunch)), 0, 'Invalid FairLaunch ETH balance');
            // assertEq(WETH.balanceOf(address(positionManager)), ethSpent, 'Invalid PositionManager ETH balance');
            assertEq(WETH.balanceOf(address(poolManager)), poolManagerEth, 'Invalid PoolManager ETH balance');

            FairLaunch.FairLaunchInfo memory fairLaunchInfo = fairLaunch.fairLaunchInfo(poolId(_flipped));
            assertEq(fairLaunchInfo.supply, supplyShare(50) - i, 'Invalid PositionManager token supply');

            // Iterate to the next swap
            i += tokenBuyAmount;
        }
    }

    function test_CanOverbuyFairLaunchPosition(bool _flipped) public flipTokens(_flipped) {
        deal(address(WETH), address(poolManager), 1000e27 ether);

        // Create our memecoin with tokens in fair launch
        positionManager.flaunch(PositionManager.FlaunchParams('name', 'symbol', 'https://token.gg/', 0.1e27, FAIR_LAUNCH_DURATION, 0, address(this), 0, 0, abi.encode(''), abi.encode(1_000)));

        // We should currently be within the FairLaunch window
        assertTrue(fairLaunch.inFairLaunchWindow(poolId(_flipped)));

        // Deal enough ETH to fulfill the entire FairLaunch position
        deal(address(WETH), address(this), 100e27 ether);
        WETH.approve(address(poolSwap), type(uint).max);

        uint startBalance = WETH.balanceOf(address(this));

        // Action our swap to buy all of the FairLaunch tokens from the pool
        poolSwap.swap(
            poolKey(_flipped),
            IPoolManager.SwapParams({
                zeroForOne: !_flipped,
                amountSpecified: int(supplyShare(50)),
                sqrtPriceLimitX96: !_flipped ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            })
        );

        uint ethSpent = startBalance - WETH.balanceOf(address(this));

        assertEq(IERC20(_flipped ? MEMECOIN_FLIPPED : MEMECOIN_UNFLIPPED).balanceOf(address(this)), supplyShare(50), 'Invalid user balance');
        assertLt(WETH.balanceOf(address(this)), startBalance, 'Invalid user ETH balance');

        // Confirm the fair window is closed
        assertFalse(fairLaunch.inFairLaunchWindow(EXPECTED_POOL_ID));

        // Confirm that we cannot sell the tokens back for more than we bought them for
        vm.expectRevert();
        poolSwap.swap(
            poolKey(_flipped),
            IPoolManager.SwapParams({
                zeroForOne: _flipped,
                amountSpecified: int(ethSpent),
                sqrtPriceLimitX96: _flipped ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            })
        );

        // Confirm that we can buy more tokens now that we are out of FL
        poolSwap.swap(
            poolKey(_flipped),
            IPoolManager.SwapParams({
                zeroForOne: !_flipped,
                amountSpecified: -0.01 ether,
                sqrtPriceLimitX96: !_flipped ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            })
        );
    }

    // function test_CanFairLaunchSwap(uint _supply) public {
    function test_CanFairLaunchSwap() public {

        // Ensure our supply is within the full range (0 - 100%)
        uint _supply = 40;

        deal(address(WETH), address(poolManager), 1000e27 ether);

        initialPrice.setSqrtPriceX96(
            InitialPrice.InitialSqrtPriceX96({
                unflipped: FL_SQRT_PRICE_1_2,
                flipped: FL_SQRT_PRICE_2_1
            })
        );

        positionManager.flaunch(
            PositionManager.FlaunchParams(
                'name',
                'symbol',
                'https://token.gg/',
                supplyShare(_supply),
                FAIR_LAUNCH_DURATION,
                0,
                address(this),
                0,
                0,
                abi.encode(''),
                abi.encode(1_000)
            )
        );

        // Deal enough ETH to fulfill the entire FairLaunch position
        deal(address(WETH), address(this), 1000e18);
        WETH.approve(address(poolSwap), type(uint).max);

        // Action our swap to buy all of the FairLaunch tokens from the pool
        poolSwap.swap(
            poolKey(false),
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -1000e18,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            })
        );
    }

    function test_CanFairLaunchWithScheduledFlaunch() public {
        deal(address(WETH), address(poolManager), 1000e27 ether);

        initialPrice.setSqrtPriceX96(
            InitialPrice.InitialSqrtPriceX96({
                unflipped: FL_SQRT_PRICE_1_2,
                flipped: FL_SQRT_PRICE_2_1
            })
        );

        uint startsAt = block.timestamp + 6 hours;
        uint endsAt = startsAt + FAIR_LAUNCH_DURATION;

        positionManager.flaunch(
            PositionManager.FlaunchParams({
                name: 'name',
                symbol: 'symbol',
                tokenUri: 'https://token.gg/',
                initialTokenFairLaunch: supplyShare(50),
                fairLaunchDuration: FAIR_LAUNCH_DURATION,
                premineAmount: 0,
                creator: address(this),
                creatorFeeAllocation: 0,
                flaunchAt: startsAt,
                initialPriceParams: abi.encode(''),
                feeCalculatorParams: abi.encode(1_000)
            })
        );

        // Deal enough ETH to fulfill our tests
        deal(address(WETH), address(this), 0.5e18);
        WETH.approve(address(poolSwap), type(uint).max);

        assertFalse(fairLaunch.inFairLaunchWindow(poolId(false)));

        // Action our swap to buy all of the FairLaunch tokens from the pool
        vm.expectRevert();
        poolSwap.swap(
            poolKey(false),
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.1e18,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            })
        );

        // Shift forward to just before the window
        vm.warp(startsAt - 1);

        assertFalse(fairLaunch.inFairLaunchWindow(poolId(false)));

        // We should still revert
        vm.expectRevert();
        poolSwap.swap(
            poolKey(false),
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.1e18,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            })
        );

        // Skip to window opening
        vm.warp(startsAt + 1);

        assertTrue(fairLaunch.inFairLaunchWindow(poolId(false)));

        poolSwap.swap(
            poolKey(false),
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.1e18,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            })
        );

        // Move to just before window ends
        vm.warp(endsAt - 1);

        assertTrue(fairLaunch.inFairLaunchWindow(poolId(false)));

        poolSwap.swap(
            poolKey(false),
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.1e18,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            })
        );

        // Move outside window
        vm.warp(endsAt + 1);

        assertFalse(fairLaunch.inFairLaunchWindow(poolId(false)));

        poolSwap.swap(
            poolKey(false),
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.1e18,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            })
        );
    }

    function test_CanSetZeroFairLaunchDuration() public {
        vm.expectEmit();
        emit FairLaunch.FairLaunchCreated(poolId(false), 0, block.timestamp, block.timestamp);

        // Flaunch our token
        positionManager.flaunch(
            PositionManager.FlaunchParams({
                name: 'name',
                symbol: 'symbol',
                tokenUri: 'https://token.gg/',
                initialTokenFairLaunch: 0,
                fairLaunchDuration: 0,
                premineAmount: 0,
                creator: address(this),
                creatorFeeAllocation: 0,
                flaunchAt: 0,
                initialPriceParams: abi.encode(''),
                feeCalculatorParams: abi.encode(1_000)
            })
        );

        assertFalse(fairLaunch.inFairLaunchWindow(poolId(false)));

        FairLaunch.FairLaunchInfo memory info = fairLaunch.fairLaunchInfo(poolId(false));
        assertEq(info.startsAt, block.timestamp);
        assertEq(info.endsAt, block.timestamp);
        assertEq(info.initialTick, 6931);  // Known due to constant test value
        assertEq(info.revenue, 0);
        assertEq(info.supply, 0);
        assertEq(info.closed, false);

        // Confirm that we can now make a swap
        deal(address(WETH), address(this), 2 ether);
        WETH.approve(address(poolSwap), type(uint).max);

        // Action our swap during Fair Launch
        poolSwap.swap(
            poolKey(false),
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int(1 ether),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            })
        );

        // Refresh our pool fair launch information
        info = fairLaunch.fairLaunchInfo(poolId(false));

        // The information should all be the same as before, but it will now be closed
        assertEq(info.startsAt, block.timestamp);
        assertEq(info.endsAt, block.timestamp);
        assertEq(info.initialTick, 6931);  // Known due to constant test value
        assertEq(info.revenue, 0);
        assertEq(info.supply, 0);
        assertEq(info.closed, true);

        // We should still be marked as outside the fair launch window
        assertFalse(fairLaunch.inFairLaunchWindow(poolId(false)));
    }

    function test_CanSetVariedFairLaunchDuration(uint _duration) public {
        // Ensure that we have a duration that is not zero. Any amount will be allowed.
        vm.assume(_duration != 0);

        // Ensure that the duration is not too long, otherwise it will overflow
        vm.assume(_duration < type(uint128).max);

        vm.expectEmit();
        emit FairLaunch.FairLaunchCreated(poolId(false), supplyShare(50), block.timestamp, block.timestamp + _duration);

        // Flaunch our token
        positionManager.flaunch(
            PositionManager.FlaunchParams(
                'name', 'symbol', 'https://token.gg/', supplyShare(50), _duration, 0,
                address(this), 0, 0, abi.encode(''), abi.encode(1_000)
            )
        );

        // Confirm that we are now in the fair launch window
        assertTrue(fairLaunch.inFairLaunchWindow(poolId(false)));

        // Confirm that the `endsAt` parameter is as expected
        FairLaunch.FairLaunchInfo memory fairLaunchInfo = fairLaunch.fairLaunchInfo(poolId(false));
        assertEq(fairLaunchInfo.startsAt, block.timestamp);
        assertEq(fairLaunchInfo.endsAt, block.timestamp + _duration);
        assertEq(fairLaunchInfo.supply, supplyShare(50));
        assertEq(fairLaunchInfo.closed, false);
    }

    function test_CannotBypassFairLaunchCalculatorWithLargeBuy(
        bool _validSignature,
        bool _validWalletCap,
        bool _validTxCap
    ) public {
        // Ensure that at least one of our fuzzed parameters is true
        vm.assume(_validSignature || _validWalletCap || _validTxCap);

        // Deploy the fee calculators
        TrustedSignerFeeCalculator trustedSignerFeeCalculator = new TrustedSignerFeeCalculator(address(flETH));
        trustedSignerFeeCalculator.grantRole(ProtocolRoles.POSITION_MANAGER, address(positionManager));
        StaticFeeCalculator staticFeeCalculator = new StaticFeeCalculator();

        // Set the fair launch calculator to TrustedSignerFeeCalculator
        positionManager.setFairLaunchFeeCalculator(trustedSignerFeeCalculator);

        // Set the post-fair launch calculator to StaticFeeCalculator
        positionManager.setFeeCalculator(staticFeeCalculator);

        // Create a signer and add it as a trusted signer for antibot protection
        (address signer, uint signerPrivateKey) = makeAddrAndKey("trusted_signer");
        trustedSignerFeeCalculator.addTrustedSigner(signer);

        // Use smaller, more manageable amounts
        uint fairLaunchSupply = 10e27;
        uint walletCap = _validWalletCap ? 0 : 5e27;
        uint txCap = _validTxCap ? 0 : 1e27;

        // Flaunch the token with fair launch settings enabled
        address memecoin = positionManager.flaunch(
            PositionManager.FlaunchParams({
                name: 'TestToken',
                symbol: 'TEST',
                tokenUri: 'https://token.gg/',
                initialTokenFairLaunch: fairLaunchSupply,
                fairLaunchDuration: 30 minutes,
                premineAmount: 0,
                creator: address(this),
                creatorFeeAllocation: 0,
                flaunchAt: 0,
                initialPriceParams: abi.encode(1000e6),
                feeCalculatorParams: abi.encode(true, walletCap, txCap)
            })
        );

        // Get the pool key
        PoolKey memory testPoolKey = positionManager.poolKey(memecoin);
        PoolId testPoolId = testPoolKey.toId();

        // Verify that fair launch settings are enabled
        {
            (bool enabled, uint returnedWalletCap, uint returnedTxCap) = trustedSignerFeeCalculator.fairLaunchSettings(testPoolId);
            assertTrue(enabled, "Fair launch settings should be enabled");
            assertEq(returnedWalletCap, walletCap, "Wallet cap should be set correctly");
            assertEq(returnedTxCap, txCap, "Transaction cap should be set correctly");
        }

        // Generate a valid signature for the transaction
        uint deadline = block.timestamp + 1 hours;
        bytes memory signature = bytes('');
        if (_validSignature) {
            signature = _generateSignature(TX_ORIGIN, testPoolId, deadline, signerPrivateKey);
        }

        // Give this test contract some WETH to make the swap
        deal(address(flETH), address(this), 1000e29);
        flETH.approve(address(poolSwap), type(uint).max);
        
        // Also ensure the poolManager has enough flETH to handle the swap
        deal(address(flETH), address(poolManager), 1000e29);

        // In all cases, this swap should fail as it will fail at least one of the fuzzed parameters
        if (!_validSignature) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    CustomRevert.WrappedError.selector,
                    address(positionManager),
                    IHooks.afterSwap.selector,
                    abi.encodeWithSelector(TrustedSignerFeeCalculator.InvalidSigner.selector, address(0)),
                    abi.encodeWithSelector(Hooks.HookCallFailed.selector)
                )
            );
        } else if (!_validTxCap) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    CustomRevert.WrappedError.selector,
                    address(positionManager),
                    IHooks.afterSwap.selector,
                    abi.encodeWithSelector(TrustedSignerFeeCalculator.TransactionCapExceeded.selector, 10e27 + 1, 1e27),
                    abi.encodeWithSelector(Hooks.HookCallFailed.selector)
                )
            );
        } else if (!_validWalletCap) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    CustomRevert.WrappedError.selector,
                    address(positionManager),
                    IHooks.afterSwap.selector,
                    abi.encodeWithSelector(TrustedSignerFeeCalculator.TransactionCapExceeded.selector, 10e27 + 1, 5e27),
                    abi.encodeWithSelector(Hooks.HookCallFailed.selector)
                )
            );
        }

        // Perform the actual swap with hook data that will fail the fair launch calculator
        poolSwap.swap(
            testPoolKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: int(fairLaunchSupply + 1), // Positive amount = exact tokens out
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            abi.encode(
                address(0),
                TrustedSignerFeeCalculator.SignedMessage({
                    poolId: PoolId.unwrap(testPoolId),
                    deadline: deadline,
                    signature: signature
                })
            )
        );
    }

    /**
     * Generates a signature for a given wallet, poolId, deadline and private key.
     * 
     * @param _wallet The wallet to generate a signature for
     * @param _poolId The pool id that this signature is valid for
     * @param _deadline The deadline for the signature
     * @param _privateKey The private key to use to generate the signature
     *
     * @return signature_ The encoded signature
     */
    function _generateSignature(address _wallet, PoolId _poolId, uint _deadline, uint _privateKey) internal pure returns (bytes memory signature_) {
        bytes32 hash = keccak256(abi.encodePacked(_wallet, PoolId.unwrap(_poolId), _deadline));
        bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, message); 
        signature_ = abi.encodePacked(r, s, v);
    }

    function poolKey(bool _flipped) internal view returns (PoolKey memory) {
        return _flipped ? EXPECTED_FLIPPED_POOL_KEY : EXPECTED_POOL_KEY;
    }

    function poolId(bool _flipped) internal view returns (PoolId) {
        return _flipped ? EXPECTED_FLIPPED_POOL_ID : EXPECTED_POOL_ID;
    }

}
