# 1、瞬态存储


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