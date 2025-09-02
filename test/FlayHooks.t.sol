// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {Hooks, IHooks} from '@uniswap/v4-core/src/libraries/Hooks.sol';
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import {Pool} from '@uniswap/v4-core/src/libraries/Pool.sol';
import {PoolManager} from '@uniswap/v4-core/src/PoolManager.sol';
import {PoolModifyLiquidityTest} from '@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol';
import {TickMath} from '@uniswap/v4-core/src/libraries/TickMath.sol';

import {FlayHooks} from '@flaunch/FlayHooks.sol';
import {PoolSwap} from '@flaunch/zaps/PoolSwap.sol';
import {ProtocolRoles} from '@flaunch/libraries/ProtocolRoles.sol';

import {ERC20Mock} from './tokens/ERC20Mock.sol';
import {FlaunchTest} from './FlaunchTest.sol';
import {HookMiner} from './utils/HookMiner.sol';


contract FlayHooksTest is FlaunchTest {

    /// Set contract addresses hardcoded on the FlayHooks contract
    address public constant TOKEN_0 = 0x000000000D564D5be76f7f0d28fE52605afC7Cf8;
    address public constant TOKEN_1 = 0xF1A7000000950C7ad8Aff13118Bb7aB561A448ee;
    address public constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;

    /// Our {FlayHooks} contract we are testing
    FlayHooks internal flayHooks;

    /// Tokens deployed as PoolKey currencies
    ERC20Mock internal token0;
    ERC20Mock internal token1;

    function setUp() public {
        // Deploy our PoolManager to the expected address and update our test contracts
        deployCodeTo('PoolManager.sol', abi.encode(address(this)), POOL_MANAGER);
        poolManager = PoolManager(POOL_MANAGER);
        poolModifyPosition = new PoolModifyLiquidityTest(poolManager);
        poolSwap = new PoolSwap(poolManager);

        // Deploy our ERC20Mock tokens to specific addresses that will be supported on Base
        deployCodeTo('tokens/ERC20Mock.sol:ERC20Mock', abi.encode(address(this)), TOKEN_0);
        deployCodeTo('tokens/ERC20Mock.sol:ERC20Mock', abi.encode(address(this)), TOKEN_1);

        token0 = ERC20Mock(TOKEN_0);
        token1 = ERC20Mock(TOKEN_1);

        // Deploy our FlayHooks contract to a valid address
        (, bytes32 salt) = HookMiner.find(
            // @dev The address that will deploy the hook. In `forge test`, this will be the test contract `address(this)`
            // or the pranking address. In `forge script`, this should be `0x4e59b44847b379578588920cA78FbF26c0B4956C`
            // (CREATE2 Deployer Proxy).
            address(this),
            uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG),
            type(FlayHooks).creationCode,
            abi.encode(SQRT_PRICE_1_1, address(this))
        );

        flayHooks = new FlayHooks{salt: salt}(SQRT_PRICE_1_1, address(this));
        flayHooks.bidWall().grantRole(ProtocolRoles.POSITION_MANAGER, address(flayHooks));
    }

    function test_CanGetPublicVariables() public view {
        // Check and validate our pool key
        (
            Currency currency0,
            Currency currency1,
            uint24 fee,
            int24 tickSpacing,
            IHooks hooks
        ) = flayHooks.flayNativePoolKey();

        assertEq(Currency.unwrap(currency0), address(token0));
        assertEq(Currency.unwrap(currency1), address(token1));
        assertEq(fee, 0);
        assertEq(tickSpacing, 60);
        assertEq(address(hooks), address(flayHooks));

        // Validate our immutable variables
        assertEq(flayHooks.nativeToken(), address(token0));
        assertEq(flayHooks.flayToken(), address(token1));

        // Validate our constants
        assertEq(flayHooks.MIN_DISTRIBUTE_THRESHOLD(), 0.001 ether);
        assertEq(flayHooks.BASE_SWAP_FEE(), 1_00);
    }

    function test_CanGetHookPermissions() public view {
        Hooks.Permissions memory permissions = flayHooks.getHookPermissions();

        assertEq(permissions.beforeInitialize, true);
        assertEq(permissions.beforeSwap, true);
        assertEq(permissions.afterSwap, true);
        assertEq(permissions.beforeSwapReturnDelta, true);
        assertEq(permissions.afterSwapReturnDelta, true);

        assertEq(permissions.afterInitialize, false);
        assertEq(permissions.beforeAddLiquidity, false);
        assertEq(permissions.afterAddLiquidity, false);
        assertEq(permissions.beforeRemoveLiquidity, false);
        assertEq(permissions.afterRemoveLiquidity, false);
        assertEq(permissions.beforeDonate, false);
        assertEq(permissions.afterDonate, false);
        assertEq(permissions.afterAddLiquidityReturnDelta, false);
        assertEq(permissions.afterRemoveLiquidityReturnDelta, false);
    }

    function test_CannotInitializeDirectly(uint160 _initialSqrtPriceX96) public {
        _assumeValidSqrtPriceX96(_initialSqrtPriceX96);

        vm.expectRevert();
        poolManager.initialize({
            key: PoolKey({
                currency0: Currency.wrap(address(token0)),
                currency1: Currency.wrap(address(token1)),
                fee: 0,
                tickSpacing: 60,
                hooks: IHooks(address(flayHooks))
            }),
            sqrtPriceX96: _initialSqrtPriceX96
        });
    }

    function test_CanSwap(uint _seed) public {
        // Ensure we have enough tokens for liquidity and approve them for our {PoolManager}
        deal(address(token0), address(this), 10e27);
        deal(address(token1), address(this), 10e27);
        token0.approve(address(poolModifyPosition), type(uint).max);
        token1.approve(address(poolModifyPosition), type(uint).max);

        (
            Currency currency0,
            Currency currency1,
            uint24 fee,
            int24 tickSpacing,
            IHooks hooks
        ) = flayHooks.flayNativePoolKey();

        PoolKey memory poolKey = PoolKey(currency0, currency1, fee, tickSpacing, hooks);

        // Modify our position with additional ETH and tokens
        poolModifyPosition.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(poolKey.tickSpacing),
                tickUpper: TickMath.maxUsableTick(poolKey.tickSpacing),
                liquidityDelta: 10 ether,
                salt: ''
            }),
            ''
        );

        token0.approve(address(poolSwap), type(uint).max);
        token1.approve(address(poolSwap), type(uint).max);

        for (uint i = 0; i < 32; i++) {
            // Generate a pseudo-random number using keccak256 with the seed and index. We wrap the value
            // into an int48 to protect us from hitting values outside the cast.
            int swapValue = int(int48(int(uint(keccak256(abi.encodePacked(_seed, i))))));

            // Determine the boolean value based on the least significant bit of the hash
            bool zeroForOne = (uint(keccak256(abi.encodePacked(_seed, i))) & 1) == 1;
            bool flipSwapValue = (uint(keccak256(abi.encodePacked(_seed / 2, i))) & 1) == 1;

            poolSwap.swap(
                poolKey,
                IPoolManager.SwapParams({
                    zeroForOne: zeroForOne,
                    amountSpecified: flipSwapValue ? swapValue : -swapValue,
                    sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
                })
            );
        }
    }

    function test_CanSwapWithBidWall() public {
        // Ensure we have enough tokens for liquidity and approve them for our {PoolManager}
        deal(address(token0), address(this), 10e27);
        deal(address(token1), address(this), 10e27);
        token0.approve(address(poolModifyPosition), type(uint).max);
        token1.approve(address(poolModifyPosition), type(uint).max);

        (
            Currency currency0,
            Currency currency1,
            uint24 fee,
            int24 tickSpacing,
            IHooks hooks
        ) = flayHooks.flayNativePoolKey();

        PoolKey memory poolKey = PoolKey(currency0, currency1, fee, tickSpacing, hooks);

        // Modify our position with additional ETH and tokens
        poolModifyPosition.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(poolKey.tickSpacing),
                tickUpper: TickMath.maxUsableTick(poolKey.tickSpacing),
                liquidityDelta: 10 ether,
                salt: ''
            }),
            ''
        );

        token0.approve(address(poolSwap), type(uint).max);
        token1.approve(address(poolSwap), type(uint).max);

        // Make a swap big enough to trigger the BidWall
        poolSwap.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -1000 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            })
        );

        // Now make a swap that will hit the BidWall liquidity
        poolSwap.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: false,
                amountSpecified: -1 ether,
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            })
        );
    }

    function _assumeValidSqrtPriceX96(uint160 _initialSqrtPriceX96) internal pure {
        vm.assume(_initialSqrtPriceX96 >= TickMath.MIN_SQRT_PRICE);
        vm.assume(_initialSqrtPriceX96 < TickMath.MAX_SQRT_PRICE);
    }

}
