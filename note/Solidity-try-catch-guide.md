# Solidity Try-Catch 异常处理指南

## 📚 目录
- [基本概念](#基本概念)
- [语法详解](#语法详解)
- [适用场景](#适用场景)
- [错误类型](#错误类型)
- [使用限制](#使用限制)
- [实际案例](#实际案例)
- [最佳实践](#最佳实践)
- [常见问题](#常见问题)

---

## 基本概念

### 什么是 try-catch？

`try-catch` 是 **Solidity 0.6.0** 引入的异常处理机制，用于捕获**外部合约调用**的失败，避免整个交易回滚。

### 为什么需要 try-catch？

在 Solidity 中，如果外部调用失败，默认会导致整个交易 revert。try-catch 允许我们：
- ✅ 优雅地处理错误，而不是直接 revert
- ✅ 在批量操作中隔离错误
- ✅ 实现降级策略（fallback）
- ✅ 提供更好的用户体验

### 传统方式 vs try-catch

```solidity
// ❌ 传统方式：调用失败会导致交易 revert
function getBalance(address token, address account) external view returns (uint) {
    return IERC20(token).balanceOf(account);
    // 如果 token 不是有效的 ERC20 合约，整个交易 revert
}

// ✅ 使用 try-catch：调用失败返回默认值
function getBalance(address token, address account) external view returns (uint) {
    try IERC20(token).balanceOf(account) returns (uint balance) {
        return balance;  // 成功：返回余额
    } catch {
        return 0;        // 失败：返回 0 而不是 revert
    }
}
```

---

## 语法详解

### 1. 基础语法

```solidity
try externalContract.someFunction() {
    // 调用成功时执行
} catch {
    // 调用失败时执行
}
```

### 2. 接收返回值

```solidity
try externalContract.someFunction() returns (returnType returnValue) {
    // 成功：可以使用 returnValue
    uint result = returnValue;
} catch {
    // 失败：处理错误
}
```

### 3. 多个返回值

```solidity
try externalContract.someFunction() returns (uint a, string memory b, bool c) {
    // 成功：使用多个返回值
    process(a, b, c);
} catch {
    // 失败
}
```

### 4. 完整的错误捕获

```solidity
try externalContract.someFunction() returns (uint value) {
    // 成功分支
    
} catch Error(string memory reason) {
    // 捕获 require/revert 的错误消息
    // reason 是错误字符串
    
} catch Panic(uint errorCode) {
    // 捕获 Panic 错误（assert 失败、除零等）
    // errorCode 是错误代码
    
} catch (bytes memory lowLevelData) {
    // 捕获其他低级错误
    // lowLevelData 是原始返回数据
}
```

---

## 适用场景

### 场景 1：安全查询外部合约

```solidity
contract SafeTokenQuery {
    // 安全地获取代币名称
    function getTokenName(address token) external view returns (string memory) {
        try IERC20Metadata(token).name() returns (string memory name) {
            return name;
        } catch {
            return "Unknown Token";
        }
    }
    
    // 安全地获取代币符号
    function getTokenSymbol(address token) external view returns (string memory) {
        try IERC20Metadata(token).symbol() returns (string memory symbol) {
            return symbol;
        } catch {
            return "???";
        }
    }
    
    // 安全地获取精度
    function getTokenDecimals(address token) external view returns (uint8) {
        try IERC20Metadata(token).decimals() returns (uint8 decimals) {
            return decimals;
        } catch {
            return 18;  // 默认精度
        }
    }
}
```

### 场景 2：批量操作中的错误隔离

```solidity
contract BatchOperations {
    event TransferSuccess(address indexed to, uint amount);
    event TransferFailed(address indexed to, uint amount, string reason);
    
    // 批量转账，单个失败不影响其他
    function batchTransfer(
        IERC20 token,
        address[] calldata recipients,
        uint[] calldata amounts
    ) external {
        require(recipients.length == amounts.length, "Length mismatch");
        
        for (uint i = 0; i < recipients.length; i++) {
            try token.transferFrom(msg.sender, recipients[i], amounts[i]) {
                // 成功
                emit TransferSuccess(recipients[i], amounts[i]);
                
            } catch Error(string memory reason) {
                // 失败但继续处理其他转账
                emit TransferFailed(recipients[i], amounts[i], reason);
            }
        }
    }
    
    // 批量调用，记录成功和失败
    function batchCall(
        address[] calldata targets,
        bytes[] calldata data
    ) external returns (bool[] memory results) {
        require(targets.length == data.length, "Length mismatch");
        results = new bool[](targets.length);
        
        for (uint i = 0; i < targets.length; i++) {
            try this.externalCall(targets[i], data[i]) {
                results[i] = true;
            } catch {
                results[i] = false;
            }
        }
    }
    
    function externalCall(address target, bytes calldata data) external {
        (bool success,) = target.call(data);
        require(success, "Call failed");
    }
}
```

### 场景 3：优雅降级（Fallback）

```solidity
contract PriceOracleWithFallback {
    address public primaryOracle;
    address public fallbackOracle;
    
    // 优先使用主预言机，失败时使用备用预言机
    function getPrice(address token) external view returns (uint price) {
        // 尝试主预言机
        try IPriceOracle(primaryOracle).getPrice(token) returns (uint p) {
            return p;
        } catch {
            // 主预言机失败，使用备用预言机
            try IPriceOracle(fallbackOracle).getPrice(token) returns (uint p) {
                return p;
            } catch {
                // 两个都失败，revert
                revert("All oracles failed");
            }
        }
    }
    
    // 多级降级
    function getPriceWithMultipleFallbacks(address token) external view returns (uint) {
        // 尝试链上预言机
        try IChainlinkOracle(chainlinkOracle).getPrice(token) returns (uint p) {
            return p;
        } catch {
            // 尝试 Uniswap TWAP
            try IUniswapOracle(uniswapOracle).getTWAP(token) returns (uint p) {
                return p;
            } catch {
                // 尝试自定义预言机
                try ICustomOracle(customOracle).getPrice(token) returns (uint p) {
                    return p;
                } catch {
                    // 使用缓存的价格（最后手段）
                    return cachedPrices[token];
                }
            }
        }
    }
}
```

### 场景 4：检查合约是否实现接口

```solidity
contract InterfaceChecker {
    // 检查合约是否支持 ERC20
    function isERC20(address token) external view returns (bool) {
        try IERC20(token).totalSupply() returns (uint) {
            return true;
        } catch {
            return false;
        }
    }
    
    // 检查合约是否支持 ERC721
    function isERC721(address token) external view returns (bool) {
        try IERC721(token).balanceOf(address(this)) returns (uint) {
            return true;
        } catch {
            return false;
        }
    }
    
    // 检查合约支持哪些功能
    function checkFeatures(address token) external view returns (
        bool hasName,
        bool hasSymbol,
        bool hasDecimals
    ) {
        try IERC20Metadata(token).name() returns (string memory) {
            hasName = true;
        } catch {
            hasName = false;
        }
        
        try IERC20Metadata(token).symbol() returns (string memory) {
            hasSymbol = true;
        } catch {
            hasSymbol = false;
        }
        
        try IERC20Metadata(token).decimals() returns (uint8) {
            hasDecimals = true;
        } catch {
            hasDecimals = false;
        }
    }
}
```

### 场景 5：NFT 所有权查询（项目实例）

```solidity
contract Memecoin {
    Flaunch public flaunch;  // ERC721 合约
    
    /**
     * 查询 memecoin 的创建者（NFT 持有者）
     * 如果 NFT 被销毁，返回 address(0) 而不是 revert
     */
    function creator() public view returns (address creator_) {
        uint tokenId = flaunch.tokenId(address(this));
        
        // 尝试获取 NFT 所有者
        try flaunch.ownerOf(tokenId) returns (address owner) {
            // ✅ NFT 存在：返回所有者地址
            creator_ = owner;
            
        } catch {
            // ✅ NFT 被销毁：返回零地址
            // 不会导致整个查询失败
            // creator_ 保持默认值 address(0)
        }
    }
}
```

---

## 错误类型

### 1. Error (String Revert)

捕获 `require` 或 `revert` 产生的错误：

```solidity
contract ErrorExample {
    function testError(address token) external view returns (string memory) {
        try IERC20(token).balanceOf(address(this)) returns (uint) {
            return "Success";
        } catch Error(string memory reason) {
            // 捕获错误消息
            // reason = "ERC20: invalid address" 或类似消息
            return string(abi.encodePacked("Error: ", reason));
        } catch {
            return "Unknown error";
        }
    }
}

// 会被 catch Error 捕获的错误
contract TokenContract {
    function balanceOf(address account) external view returns (uint) {
        require(account != address(0), "ERC20: invalid address");
        // 或
        revert("ERC20: invalid address");
    }
}
```

### 2. Panic (Assertion Failures)

捕获 `assert` 失败、除零、数组越界等错误：

```solidity
contract PanicExample {
    function testPanic(uint a, uint b) external pure returns (string memory) {
        try this.divide(a, b) returns (uint result) {
            return string(abi.encodePacked("Result: ", result));
            
        } catch Panic(uint errorCode) {
            // errorCode 是 panic 错误代码
            if (errorCode == 0x01) {
                return "Assert failed";
            } else if (errorCode == 0x11) {
                return "Arithmetic overflow/underflow";
            } else if (errorCode == 0x12) {
                return "Division by zero";
            } else if (errorCode == 0x32) {
                return "Array access out of bounds";
            } else {
                return "Unknown panic";
            }
        }
    }
    
    function divide(uint a, uint b) external pure returns (uint) {
        return a / b;  // b == 0 时触发 Panic(0x12)
    }
}
```

#### Panic 错误代码表

| 代码 | 含义 |
|------|------|
| 0x01 | `assert()` 失败 |
| 0x11 | 算术溢出/下溢（0.8.0 之前不检查） |
| 0x12 | 除零或模零 |
| 0x21 | 枚举类型转换错误 |
| 0x22 | 访问错误编码的存储字节数组 |
| 0x31 | `pop()` 空数组 |
| 0x32 | 数组索引越界 |
| 0x41 | 内存分配过多 |
| 0x51 | 调用零初始化的内部函数变量 |

### 3. Low-Level Data (其他错误)

捕获所有其他类型的错误：

```solidity
contract LowLevelExample {
    function testLowLevel(address target, bytes calldata data) external returns (bool) {
        try this.externalCall(target, data) {
            return true;
            
        } catch (bytes memory lowLevelData) {
            // lowLevelData 包含原始错误数据
            // 可以尝试解码
            
            if (lowLevelData.length > 0) {
                // 尝试解码为 Error(string)
                if (bytes4(lowLevelData) == bytes4(keccak256("Error(string)"))) {
                    string memory reason = abi.decode(
                        _slice(lowLevelData, 4),
                        (string)
                    );
                    emit ErrorCaught(reason);
                }
            }
            
            return false;
        }
    }
    
    function externalCall(address target, bytes calldata data) external {
        (bool success,) = target.call(data);
        require(success);
    }
    
    function _slice(bytes memory data, uint start) internal pure returns (bytes memory) {
        bytes memory result = new bytes(data.length - start);
        for (uint i = 0; i < result.length; i++) {
            result[i] = data[start + i];
        }
        return result;
    }
}
```

---

## 使用限制

### 1. 只能用于外部调用

```solidity
contract Limitations {
    // ✅ 可以：外部合约调用
    function validUse1() external {
        try externalContract.someFunction() {
        } catch {}
    }
    
    // ✅ 可以：通过 this 调用自己的 external/public 函数
    function validUse2() external {
        try this.externalFunction() {
        } catch {}
    }
    
    function externalFunction() external {}
    
    // ❌ 不可以：内部函数调用
    function invalidUse1() external {
        // try internalFunction() {}  // 编译错误
    }
    
    function internalFunction() internal {}
    
    // ❌ 不可以：普通语句
    function invalidUse2() external {
        // try {
        //     uint x = a + b;
        // } catch {}  // 编译错误
    }
}
```

### 2. 必须是函数调用

```solidity
contract FunctionCallOnly {
    IERC20 public token;
    
    // ✅ 可以：函数调用
    function validUse() external view {
        try token.balanceOf(msg.sender) returns (uint balance) {
            // 使用 balance
        } catch {}
    }
    
    // ❌ 不可以：合约创建
    function invalidUse1() external {
        // try new SomeContract() {  // 编译错误
        // } catch {}
    }
    
    // ❌ 不可以：send/transfer
    function invalidUse2() external {
        // try payable(address).send(1 ether) {  // 编译错误
        // } catch {}
    }
}
```

### 3. 返回值必须在 try 块中声明

```solidity
contract ReturnValueDeclaration {
    // ✅ 正确：在 try 中声明返回值
    function validUse() external view {
        try token.balanceOf(msg.sender) returns (uint balance) {
            uint myBalance = balance;  // 可以使用
        } catch {}
        
        // uint x = balance;  // 错误：balance 在此作用域外
    }
    
    // ❌ 错误：尝试在外部使用返回值
    function invalidUse() external view {
        uint balance;
        // try token.balanceOf(msg.sender) returns (uint balance) {
        //     // 这会创建新的局部变量，而不是赋值给外部的 balance
        // } catch {}
    }
}
```

### 4. catch 块不能访问 try 块的局部变量

```solidity
contract ScopeIssues {
    function example() external view {
        try token.balanceOf(msg.sender) returns (uint balance) {
            uint doubled = balance * 2;  // try 块的局部变量
            
        } catch {
            // uint x = doubled;  // 错误：无法访问 try 块的变量
        }
    }
}
```

---

## 实际案例

### 案例 1：安全的代币信息聚合器

```solidity
contract TokenInfoAggregator {
    struct TokenInfo {
        string name;
        string symbol;
        uint8 decimals;
        uint totalSupply;
        bool isValid;
    }
    
    function getTokenInfo(address token) external view returns (TokenInfo memory info) {
        info.isValid = false;
        
        // 尝试获取名称
        try IERC20Metadata(token).name() returns (string memory name) {
            info.name = name;
        } catch {
            info.name = "Unknown";
        }
        
        // 尝试获取符号
        try IERC20Metadata(token).symbol() returns (string memory symbol) {
            info.symbol = symbol;
        } catch {
            info.symbol = "???";
        }
        
        // 尝试获取精度
        try IERC20Metadata(token).decimals() returns (uint8 decimals) {
            info.decimals = decimals;
        } catch {
            info.decimals = 18;
        }
        
        // 尝试获取总供应量
        try IERC20(token).totalSupply() returns (uint supply) {
            info.totalSupply = supply;
            info.isValid = true;  // 至少 totalSupply 可用，认为是有效的 ERC20
        } catch {
            info.totalSupply = 0;
        }
    }
    
    // 批量查询
    function batchGetTokenInfo(address[] calldata tokens) 
        external view returns (TokenInfo[] memory infos) 
    {
        infos = new TokenInfo[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            infos[i] = this.getTokenInfo(tokens[i]);
        }
    }
}
```

### 案例 2：多签钱包的批量执行

```solidity
contract MultiSigWallet {
    struct Transaction {
        address to;
        uint value;
        bytes data;
        bool executed;
        bool success;
    }
    
    Transaction[] public transactions;
    
    event ExecutionSuccess(uint indexed txId);
    event ExecutionFailure(uint indexed txId, string reason);
    
    // 执行单个交易，失败不影响钱包状态
    function executeTransaction(uint txId) external {
        Transaction storage txn = transactions[txId];
        require(!txn.executed, "Already executed");
        
        txn.executed = true;
        
        try this.externalCall(txn.to, txn.value, txn.data) {
            txn.success = true;
            emit ExecutionSuccess(txId);
            
        } catch Error(string memory reason) {
            txn.success = false;
            emit ExecutionFailure(txId, reason);
            
        } catch {
            txn.success = false;
            emit ExecutionFailure(txId, "Unknown error");
        }
    }
    
    function externalCall(
        address to,
        uint value,
        bytes calldata data
    ) external {
        require(msg.sender == address(this), "Only internal");
        (bool success,) = to.call{value: value}(data);
        require(success, "Call failed");
    }
    
    // 批量执行，即使某些失败也继续
    function batchExecute(uint[] calldata txIds) external {
        for (uint i = 0; i < txIds.length; i++) {
            try this.executeTransaction(txIds[i]) {
                // 成功
            } catch {
                // 失败，但继续执行其他交易
            }
        }
    }
}
```

### 案例 3：DEX 聚合器的安全报价

```solidity
contract DEXAggregator {
    struct Quote {
        address dex;
        uint amountOut;
        bool available;
    }
    
    address[] public dexes;
    
    // 从多个 DEX 获取报价
    function getQuotes(
        address tokenIn,
        address tokenOut,
        uint amountIn
    ) external view returns (Quote[] memory quotes) {
        quotes = new Quote[](dexes.length);
        
        for (uint i = 0; i < dexes.length; i++) {
            quotes[i].dex = dexes[i];
            
            try IDex(dexes[i]).getAmountOut(tokenIn, tokenOut, amountIn) 
                returns (uint amountOut) 
            {
                quotes[i].amountOut = amountOut;
                quotes[i].available = true;
                
            } catch {
                quotes[i].amountOut = 0;
                quotes[i].available = false;
            }
        }
    }
    
    // 找到最佳报价
    function getBestQuote(
        address tokenIn,
        address tokenOut,
        uint amountIn
    ) external view returns (address bestDex, uint bestAmount) {
        Quote[] memory quotes = this.getQuotes(tokenIn, tokenOut, amountIn);
        
        for (uint i = 0; i < quotes.length; i++) {
            if (quotes[i].available && quotes[i].amountOut > bestAmount) {
                bestDex = quotes[i].dex;
                bestAmount = quotes[i].amountOut;
            }
        }
        
        require(bestDex != address(0), "No available DEX");
    }
}
```

### 案例 4：NFT 市场的安全检查

```solidity
contract NFTMarketplace {
    struct ListingInfo {
        bool isApproved;
        bool hasOwnership;
        bool isValid;
        address owner;
    }
    
    // 检查 NFT 是否可以上架
    function checkListing(
        address nft,
        uint tokenId,
        address seller
    ) external view returns (ListingInfo memory info) {
        // 检查所有权
        try IERC721(nft).ownerOf(tokenId) returns (address owner) {
            info.owner = owner;
            info.hasOwnership = (owner == seller);
        } catch {
            info.hasOwnership = false;
        }
        
        // 检查授权
        try IERC721(nft).getApproved(tokenId) returns (address approved) {
            info.isApproved = (approved == address(this));
        } catch {
            // 如果 getApproved 失败，尝试 isApprovedForAll
            try IERC721(nft).isApprovedForAll(seller, address(this)) 
                returns (bool approvedForAll) 
            {
                info.isApproved = approvedForAll;
            } catch {
                info.isApproved = false;
            }
        }
        
        info.isValid = info.hasOwnership && info.isApproved;
    }
}
```

---

## 最佳实践

### 1. 明确指定捕获的错误类型

```solidity
// ✅ 好：区分不同错误类型
function goodPractice(address token) external view returns (string memory) {
    try IERC20(token).balanceOf(msg.sender) returns (uint balance) {
        return "Success";
        
    } catch Error(string memory reason) {
        // 处理 require/revert 错误
        return string(abi.encodePacked("Error: ", reason));
        
    } catch Panic(uint code) {
        // 处理 panic 错误
        return string(abi.encodePacked("Panic: ", code));
        
    } catch (bytes memory lowLevelData) {
        // 处理其他错误
        return "Unknown error";
    }
}

// ❌ 不推荐：笼统捕获所有错误
function badPractice(address token) external view returns (string memory) {
    try IERC20(token).balanceOf(msg.sender) returns (uint balance) {
        return "Success";
    } catch {
        // 无法区分错误类型
        return "Error";
    }
}
```

### 2. 记录错误日志

```solidity
contract WithLogging {
    event CallFailed(address indexed target, string reason);
    event CallFailedWithCode(address indexed target, uint errorCode);
    event CallFailedLowLevel(address indexed target, bytes data);
    
    function callWithLogging(address target) external {
        try IExternalContract(target).someFunction() {
            // 成功
            
        } catch Error(string memory reason) {
            emit CallFailed(target, reason);
            
        } catch Panic(uint code) {
            emit CallFailedWithCode(target, code);
            
        } catch (bytes memory lowLevelData) {
            emit CallFailedLowLevel(target, lowLevelData);
        }
    }
}
```

### 3. 提供降级策略

```solidity
contract WithFallback {
    address public primaryService;
    address public backupService;
    
    // ✅ 好：提供备选方案
    function getData() external view returns (uint) {
        // 尝试主服务
        try IService(primaryService).getData() returns (uint data) {
            return data;
        } catch {
            // 主服务失败，使用备用服务
            return IService(backupService).getData();
        }
    }
}
```

### 4. 避免过度使用

```solidity
// ❌ 不推荐：不必要的 try-catch
function unnecessary() external view {
    try this.pureFunction() returns (uint result) {
        return result;
    } catch {
        return 0;
    }
}

function pureFunction() external pure returns (uint) {
    return 42;  // 永远不会失败
}

// ✅ 好：只在真正可能失败的地方使用
function necessary(address unknownContract) external view {
    try IUnknown(unknownContract).someFunction() returns (uint result) {
        return result;
    } catch {
        return 0;
    }
}
```

### 5. 文档化错误处理逻辑

```solidity
contract WellDocumented {
    /**
     * @notice 获取代币余额，如果查询失败返回 0
     * @dev 使用 try-catch 处理以下情况：
     *      - token 不是有效的 ERC20 合约
     *      - balanceOf 函数不存在
     *      - 调用 revert 或 out of gas
     * @param token 代币合约地址
     * @param account 账户地址
     * @return 余额，如果查询失败返回 0
     */
    function getBalanceSafe(
        address token,
        address account
    ) external view returns (uint) {
        try IERC20(token).balanceOf(account) returns (uint balance) {
            return balance;
        } catch {
            // 任何错误都返回 0，而不是 revert
            return 0;
        }
    }
}
```

### 6. 考虑 Gas 成本

```solidity
contract GasEfficiency {
    // ✅ 好：只捕获需要的错误类型
    function efficient(address token) external view {
        try IERC20(token).balanceOf(msg.sender) returns (uint balance) {
            // 使用 balance
        } catch Error(string memory) {
            // 只处理 Error 类型
        }
    }
    
    // ❌ 效率较低：捕获所有类型但不使用
    function inefficient(address token) external view {
        try IERC20(token).balanceOf(msg.sender) returns (uint balance) {
            // 使用 balance
        } catch Error(string memory reason) {
            // 不使用 reason
        } catch Panic(uint code) {
            // 不使用 code
        } catch (bytes memory data) {
            // 不使用 data
        }
    }
}
```

---

## 常见问题

### Q1: try-catch 会增加多少 gas 成本？

**A**: 
- try-catch 本身的 gas 成本很低（约 100-200 gas）
- 主要成本在于外部调用本身
- 如果调用成功，额外成本可以忽略不计
- 如果调用失败，catch 块的执行会有一些成本

```solidity
// Gas 成本示例
function withoutTryCatch() external view returns (uint) {
    return token.balanceOf(msg.sender);
    // 如果失败：整个交易 revert，gas 全部消耗
}

function withTryCatch() external view returns (uint) {
    try token.balanceOf(msg.sender) returns (uint balance) {
        return balance;
    } catch {
        return 0;
    }
    // 如果失败：catch 块执行，消耗额外的少量 gas
}
```

### Q2: 可以在 catch 块中再次使用 try-catch 吗？

**A**: 可以，支持嵌套使用

```solidity
function nested() external view returns (uint) {
    try primaryOracle.getPrice() returns (uint price) {
        return price;
    } catch {
        // 在 catch 块中再次使用 try-catch
        try backupOracle.getPrice() returns (uint price) {
            return price;
        } catch {
            return 0;
        }
    }
}
```

### Q3: try-catch 能捕获 out of gas 错误吗？

**A**: 
- 部分可以，取决于剩余 gas
- EIP-150 规定：调用时保留 1/64 的 gas
- 如果外部调用耗尽所有 gas，catch 仍可能执行
- 但如果整个交易 gas 不足，无法捕获

```solidity
function gasHandling() external view {
    try expensiveCall() {
        // 成功
    } catch {
        // 如果 expensiveCall 耗尽 gas
        // 这里仍有 1/64 的 gas 可以执行简单逻辑
    }
}
```

### Q4: 为什么不能用 try-catch 包裹内部函数？

**A**: 
- try-catch 只能用于外部调用
- 内部函数调用在同一个执行上下文中
- 如果内部函数失败，整个交易都会 revert
- 这是 Solidity 的设计限制

```solidity
// ❌ 不可以
function internal cannotCatch() {
    try internalFunction() {  // 编译错误
    } catch {}
}

// ✅ 可以通过 this 调用自己的 external 函数
function workaround() {
    try this.externalFunction() {
    } catch {}
}

function externalFunction() external {}
```

### Q5: catch 块可以访问 try 块的变量吗？

**A**: 
- 不可以，它们是不同的作用域
- 需要在外部声明变量

```solidity
// ❌ 不可以
function wrongScope() {
    try token.balanceOf(msg.sender) returns (uint balance) {
        uint doubled = balance * 2;
    } catch {
        // uint x = doubled;  // 错误：doubled 不在作用域内
    }
}

// ✅ 正确做法
function correctScope() {
    uint result;
    
    try token.balanceOf(msg.sender) returns (uint balance) {
        result = balance * 2;
    } catch {
        result = 0;
    }
    
    // 使用 result
}
```

### Q6: 可以在 view/pure 函数中使用 try-catch 吗？

**A**: 
- 可以在 view 函数中使用（调用其他 view/pure 函数）
- 不能在 pure 函数中使用（pure 不允许读取状态）

```solidity
// ✅ 可以：view 函数
function viewFunction() external view {
    try token.balanceOf(msg.sender) returns (uint balance) {
        // ...
    } catch {}
}

// ❌ 不可以：pure 函数不能进行外部调用
function pureFunction() external pure {
    // try ... {}  // 编译错误
}
```

---

## 快速参考

### 基础模板

```solidity
// 1. 简单的 try-catch
try externalContract.someFunction() {
    // 成功
} catch {
    // 失败
}

// 2. 带返回值
try externalContract.someFunction() returns (uint value) {
    // 使用 value
} catch {
    // 失败
}

// 3. 完整的错误捕获
try externalContract.someFunction() returns (uint value) {
    // 成功
} catch Error(string memory reason) {
    // require/revert 错误
} catch Panic(uint errorCode) {
    // assert/panic 错误
} catch (bytes memory lowLevelData) {
    // 其他错误
}
```

### 常见用例

```solidity
// 1. 安全查询
function safeQuery(address token) external view returns (uint) {
    try IERC20(token).balanceOf(msg.sender) returns (uint bal) {
        return bal;
    } catch {
        return 0;
    }
}

// 2. 降级策略
function withFallback() external view returns (uint) {
    try primary.getData() returns (uint data) {
        return data;
    } catch {
        return backup.getData();
    }
}

// 3. 批量操作
function batchProcess(address[] calldata targets) external {
    for (uint i = 0; i < targets.length; i++) {
        try this.process(targets[i]) {
            // 成功
        } catch {
            // 失败但继续
        }
    }
}
```

---

## 总结

### 核心要点

1. **try-catch 用于捕获外部调用的失败**
   - 避免单个失败导致整个交易 revert
   - 提供更好的错误处理和用户体验

2. **三种错误类型**
   - Error: require/revert 错误
   - Panic: assert/overflow/division 等错误
   - Low-level: 其他所有错误

3. **使用限制**
   - 只能用于外部合约调用
   - 不能用于内部函数
   - 不能用于普通语句

4. **最佳实践**
   - 区分错误类型
   - 记录错误日志
   - 提供降级策略
   - 避免过度使用

5. **实际应用**
   - 批量操作错误隔离
   - 多级降级策略
   - 安全的合约查询
   - NFT/Token 信息聚合

### 何时使用 try-catch

- ✅ 调用不可信的外部合约
- ✅ 批量操作需要错误隔离
- ✅ 需要提供降级/备选方案
- ✅ 查询可能不存在的合约功能
- ❌ 内部函数调用
- ❌ 总是成功的操作
- ❌ 需要严格失败的关键操作

---

## 参考资源

- [Solidity Documentation - Try/Catch](https://docs.soliditylang.org/en/latest/control-structures.html#try-catch)
- [Solidity 0.6.0 Release Notes](https://blog.soliditylang.org/2019/12/09/solidity-0.6-release-announcement/)
- [EIP-150: Gas Cost Changes](https://eips.ethereum.org/EIPS/eip-150)
- [Solidity Error Handling Best Practices](https://consensys.github.io/smart-contract-best-practices/development-recommendations/solidity-specific/error-handling/)

---

*最后更新：2024年12月*

