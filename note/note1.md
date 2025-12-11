# 1、瞬态存储 PositionManager.sol
跟预挖相关
if (_params.premineAmount != 0) {
    int premineAmount = _params.premineAmount.toInt256();
    assembly { tstore(poolId, premineAmount) }                     // 瞬态存储，用于存储预挖数量
}

## tload 读取瞬态存储
    function _tload(bytes32 _key) internal view returns (int value_) {
        assembly { value_ := tload(_key) }
    }

```solidity
tload(p)   == transientStorage[p]
tstore(p, v)  ==  transientStorage[p] := v
```


# 2、sqrtPriceX96


# 3、如何区别是 卖，还是买
第一个参数是eth，第二个参数是meme，那就是买


# 4、在fairlaunch阶段，是如何定价的。
设定tick，也就确定了价格（价格与tick是有一个公式的）。在fairlaunch阶段只能买入，不能卖出，在PositionManager的
```solidity
if (nativeIsZero != _params.zeroForOne) {
    revert FairLaunch.CannotSellTokenDuringFairLaunch();
}   // 如果我们的原生代币不是货币0，则抛出错误
```

# BeforeSwapDelta和 BalanceDelta的区别
BeforeSwapDelta - 描述"精确"与"非精确" 高128位：用户精确指定的代币数量（specified amount）
低128位：根据价格计算出来的代币数量（unspecified amount）
BalanceDelta - 描述Token0和Token1的实际变化 高128位：永远是token0的余额变化
低128位：永远是token1的余额变化
与用户指定精确还是非精确无关，只看代币在池子中的顺序

# validTick什么意思
validTick来着TickFinder 库。用于将任意tick值调整为符合tickSpacing的有效tick

# FairLaunch.sol _createImmutablePosition
还没搞懂，还需要看一下


# fairlaunch未出售完的代币销毁
出于经济学考虑，进行通缩

# beforeSwap的机制
BeforeSwapDelta的记录表示，再钩子里已经处理了多少代币，poolManager再处理剩下的

# _settleDelta方法进行转账
方法的内部实现,没看明白
```solidity
if (_delta.amount0() < 0) {
    _poolKey.currency0.settle(poolManager, address(this), uint(-int(_delta.amount0())), false);
} else if (_delta.amount0() > 0) {
    poolManager.take(_poolKey.currency0, address(this), uint(int(_delta.amount0())));
}
```

# 顿悟
我悟了，这uniswap，flaunch，无非就是变着法子计算一个代币等于多少另外的代币，然后扣除一点费用，然后给考虑给谁。总之就是这些，swap，fee

节省每天 2.5小时。
工作时间，全身心研究defi
