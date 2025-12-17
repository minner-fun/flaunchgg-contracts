# ERC165 接口检测完全指南

## 📚 目录
- [什么是 ERC165](#什么是-erc165)
- [什么是 interfaceId](#什么是-interfaceid)
- [supportsInterface 方法](#supportsinterface-方法)
- [interfaceId 的计算](#interfaceid-的计算)
- [Memecoin 的实现](#memecoin-的实现)
- [使用场景](#使用场景)
- [实际案例](#实际案例)
- [最佳实践](#最佳实践)

---

## 什么是 ERC165？

### 基本概念

**ERC165** 是一个以太坊标准（EIP-165），用于**接口检测**。它允许智能合约声明它支持哪些接口，其他合约可以在运行时查询这些信息。

```plaintext
问题：如何知道一个合约实现了哪些功能？

传统方式（❌ 不可靠）：
1. 查看合约代码 → 麻烦，且可能看不到
2. 尝试调用方法 → 可能失败，浪费 gas
3. 假设所有 ERC20 都有相同功能 → 不一定准确

ERC165 方式（✅ 标准化）：
1. 调用 supportsInterface(interfaceId)
2. 返回 true/false
3. 可靠、快速、省 gas
```

### ERC165 接口定义

```solidity
// IERC165 接口
interface IERC165 {
    /**
     * @notice Query if a contract implements an interface
     * @param interfaceId The interface identifier, as specified in ERC-165
     * @dev Interface identification is specified in ERC-165. 
     *      This function uses less than 30,000 gas.
     * @return `true` if the contract implements `interfaceID` and
     *         `interfaceID` is not 0xffffffff, `false` otherwise
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
```

### 为什么需要 ERC165？

```solidity
// 场景 1：避免盲目调用
contract Bridge {
    function bridgeToken(address token) external {
        // ❌ 直接调用可能失败
        IERC7802(token).crosschainBurn(msg.sender, amount);
        
        // ✅ 先检查是否支持
        if (IERC165(token).supportsInterface(type(IERC7802).interfaceId)) {
            IERC7802(token).crosschainBurn(msg.sender, amount);
        } else {
            revert("Token does not support crosschain bridging");
        }
    }
}

// 场景 2：功能检测
contract DApp {
    function useToken(address token) external {
        // 检查是否支持 Permit（签名授权）
        if (IERC165(token).supportsInterface(type(IERC20Permit).interfaceId)) {
            // 使用 Permit 功能（用户体验更好）
            usePermit(token);
        } else {
            // 回退到传统 approve
            useApprove(token);
        }
    }
}

// 场景 3：多接口支持
contract Aggregator {
    function analyzeToken(address token) external view returns (string[] memory features) {
        string[] memory supported;
        
        if (IERC165(token).supportsInterface(type(IERC20).interfaceId)) {
            supported.push("ERC20");
        }
        
        if (IERC165(token).supportsInterface(type(IERC20Permit).interfaceId)) {
            supported.push("Permit");
        }
        
        if (IERC165(token).supportsInterface(type(IERC7802).interfaceId)) {
            supported.push("Superchain");
        }
        
        return supported;
    }
}
```

---

## 什么是 interfaceId？

### 基本定义

**interfaceId** 是一个 **4 字节（bytes4）** 的唯一标识符，用于标识一个接口。

```solidity
// interfaceId 是 bytes4 类型
bytes4 interfaceId = type(IERC20).interfaceId;

// 示例值
type(IERC20).interfaceId           = 0x36372b07
type(IERC20Permit).interfaceId     = 0x9d8ff7da
type(IERC7802).interfaceId         = 0x...（SuperchainERC20）
type(IERC165).interfaceId          = 0x01ffc9a7
```

### interfaceId 的来源

```plaintext
interfaceId 是通过接口中所有函数选择器（function selector）进行 XOR 运算得到的

公式：
interfaceId = functionSelector1 ⊕ functionSelector2 ⊕ functionSelector3 ⊕ ...

其中：
functionSelector = bytes4(keccak256("functionName(paramType1,paramType2,...)"))
⊕ 表示 XOR（异或）运算
```

### 计算示例

```solidity
// 示例：计算 IERC20 的 interfaceId

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// 步骤 1：计算每个函数的选择器
bytes4 selector1 = bytes4(keccak256("totalSupply()"));                           // 0x18160ddd
bytes4 selector2 = bytes4(keccak256("balanceOf(address)"));                     // 0x70a08231
bytes4 selector3 = bytes4(keccak256("transfer(address,uint256)"));              // 0xa9059cbb
bytes4 selector4 = bytes4(keccak256("allowance(address,address)"));             // 0xdd62ed3e
bytes4 selector5 = bytes4(keccak256("approve(address,uint256)"));               // 0x095ea7b3
bytes4 selector6 = bytes4(keccak256("transferFrom(address,address,uint256)")); // 0x23b872dd

// 步骤 2：XOR 所有选择器
bytes4 interfaceId = selector1 ^ selector2 ^ selector3 ^ selector4 ^ selector5 ^ selector6;
// 结果：0x36372b07

// 验证
assert(interfaceId == type(IERC20).interfaceId);  // ✅ 相同
```

### 详细计算过程

```javascript
// JavaScript 计算示例

const { keccak256, toUtf8Bytes } = require('ethers');

// 函数签名列表
const functions = [
    "totalSupply()",
    "balanceOf(address)",
    "transfer(address,uint256)",
    "allowance(address,address)",
    "approve(address,uint256)",
    "transferFrom(address,address,uint256)"
];

// 计算每个函数的选择器
const selectors = functions.map(func => {
    const hash = keccak256(toUtf8Bytes(func));
    const selector = hash.slice(0, 10);  // 取前 4 字节（0x + 8位）
    console.log(`${func} → ${selector}`);
    return selector;
});

// XOR 所有选择器
let interfaceId = 0;
selectors.forEach(selector => {
    interfaceId ^= parseInt(selector, 16);
});

console.log(`IERC20 interfaceId: 0x${interfaceId.toString(16).padStart(8, '0')}`);
// 输出: 0x36372b07
```

### Solidity 中获取 interfaceId

```solidity
// 方法 1：使用 type() 关键字（推荐）
bytes4 id1 = type(IERC20).interfaceId;

// 方法 2：手动计算（不推荐，容易出错）
bytes4 id2 = 
    bytes4(keccak256("totalSupply()")) ^
    bytes4(keccak256("balanceOf(address)")) ^
    bytes4(keccak256("transfer(address,uint256)")) ^
    bytes4(keccak256("allowance(address,address)")) ^
    bytes4(keccak256("approve(address,uint256)")) ^
    bytes4(keccak256("transferFrom(address,address,uint256)"));

assert(id1 == id2);  // ✅ 相同

// 方法 3：使用常量（最高效）
bytes4 constant IERC20_INTERFACE_ID = 0x36372b07;
```

---

## supportsInterface 方法

### 基本实现

```solidity
// 最简单的实现
contract MyToken is IERC165 {
    function supportsInterface(bytes4 interfaceId) 
        public view virtual override returns (bool) 
    {
        return interfaceId == type(IERC165).interfaceId;
    }
}

// 支持多个接口
contract MyToken is IERC165, IERC20 {
    function supportsInterface(bytes4 interfaceId) 
        public view virtual override returns (bool) 
    {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IERC20).interfaceId;
    }
}

// 使用 super（继承链）
contract MyToken is ERC20, ERC20Permit {
    function supportsInterface(bytes4 interfaceId) 
        public view virtual override returns (bool) 
    {
        return
            interfaceId == type(IERC20Permit).interfaceId ||
            super.supportsInterface(interfaceId);  // ← 调用父类
    }
}
```

### OpenZeppelin 的实现

```solidity
// OpenZeppelin 的 ERC165 基础实现
abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) 
        public view virtual override returns (bool) 
    {
        return interfaceId == type(IERC165).interfaceId;
    }
}

// 子类重写
contract ERC721 is ERC165 {
    function supportsInterface(bytes4 interfaceId) 
        public view virtual override returns (bool) 
    {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);  // ← 包含 IERC165
    }
}
```

### Gas 优化版本

```solidity
// 优化 1：使用汇编
contract OptimizedToken {
    function supportsInterface(bytes4 interfaceId) 
        public view virtual returns (bool result) 
    {
        assembly {
            let s := shr(224, interfaceId)
            // ERC165: 0x01ffc9a7, ERC20: 0x36372b07, ERC7802: 0x...
            result := or(
                or(eq(s, 0x01ffc9a7), eq(s, 0x36372b07)),
                eq(s, 0x...)
            )
        }
    }
}

// 优化 2：使用位掩码（对于大量接口）
contract ManyInterfacesToken {
    // 存储所有支持的接口 ID
    mapping(bytes4 => bool) private _supportedInterfaces;
    
    constructor() {
        _supportedInterfaces[type(IERC165).interfaceId] = true;
        _supportedInterfaces[type(IERC20).interfaceId] = true;
        _supportedInterfaces[type(IERC20Permit).interfaceId] = true;
        // ... 更多接口
    }
    
    function supportsInterface(bytes4 interfaceId) 
        public view virtual returns (bool) 
    {
        return _supportedInterfaces[interfaceId];
    }
}
```

---

## Memecoin 的实现

### 完整代码分析

```solidity
// src/contracts/Memecoin.sol:296-324

/**
 * Define our supported interfaces through contract extension.
 * 通过合约扩展定义我们的支持接口。
 * @dev Implements IERC165 via IERC7802
 */
function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
    return (
        // Base token interfaces
        // 基础代币接口
        _interfaceId == type(IERC20).interfaceId ||
        _interfaceId == type(IERC20Upgradeable).interfaceId ||

        // Permit interface
        // Permit 签名授权接口
        _interfaceId == type(IERC20PermitUpgradeable).interfaceId ||

        // ERC20VotesUpgradable interface
        // 投票治理接口
        _interfaceId == type(IERC5805Upgradeable).interfaceId ||

        // Superchain interfaces
        // Superchain 跨链接口
        _interfaceId == type(IERC7802).interfaceId ||
        _interfaceId == type(IERC165).interfaceId ||

        // Memecoin interface
        // Memecoin 自定义接口
        _interfaceId == type(IMemecoin).interfaceId
    );
}
```

### 各个接口的作用

```solidity
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 1. IERC20 - 标准 ERC20 接口
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// 作用：声明这是一个标准 ERC20 代币
// 使用场景：DEX、钱包、浏览器等识别为 ERC20 代币

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 2. IERC20Upgradeable - 可升级版 ERC20 接口
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// 与 IERC20 相同，但用于可升级合约
// Memecoin 继承了 ERC20Upgradeable，所以声明支持

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 3. IERC20PermitUpgradeable - Permit 签名授权接口
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

interface IERC20Permit {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    
    function nonces(address owner) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

// 作用：支持 EIP-2612 签名授权（无需 approve 交易）
// 使用场景：DApp 可以使用签名授权，提升用户体验

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 4. IERC5805Upgradeable - 投票治理接口
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

interface IERC5805 {
    function delegate(address delegatee) external;
    function delegates(address account) external view returns (address);
    function getVotes(address account) external view returns (uint256);
    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);
    // ... 更多投票相关方法
}

// 作用：支持链上治理投票
// 使用场景：DAO 治理平台（如 Tally）识别为治理代币

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 5. IERC7802 - Superchain 跨链接口
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

interface IERC7802 {
    function crosschainMint(address _to, uint256 _amount) external;
    function crosschainBurn(address _from, uint256 _amount) external;
}

// 作用：支持 Superchain 原生跨链
// 使用场景：SuperchainTokenBridge 识别为可跨链代币

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 6. IERC165 - 接口检测接口本身
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// 作用：表明合约支持 ERC165 接口检测标准
// 使用场景：其他合约可以安全地调用 supportsInterface

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 7. IMemecoin - Memecoin 自定义接口
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

interface IMemecoin {
    function creator() external view returns (address);
    function treasury() external view returns (address payable);
    function setMetadata(string calldata name, string calldata symbol) external;
    // ... 更多 Memecoin 特有方法
}

// 作用：Memecoin 特有功能
// 使用场景：Flaunch 平台识别为 Memecoin
```

### 接口 ID 值

```solidity
// 各个接口的 interfaceId（示例值）

IERC20.interfaceId                    = 0x36372b07
IERC20Upgradeable.interfaceId         = 0x36372b07（与 IERC20 相同）
IERC20PermitUpgradeable.interfaceId   = 0x9d8ff7da
IERC5805Upgradeable.interfaceId       = 0xe90fb3f6
IERC7802.interfaceId                  = 0x... (SuperchainERC20)
IERC165.interfaceId                   = 0x01ffc9a7
IMemecoin.interfaceId                 = 0x... (自定义)

// 在 Solidity 中查询
contract Test {
    function getInterfaceIds() external pure {
        console.log("IERC20:", type(IERC20).interfaceId);
        console.log("IERC165:", type(IERC165).interfaceId);
        // ...
    }
}
```

---

## 使用场景

### 场景 1：跨链桥检测代币能力

```solidity
// SuperchainTokenBridge 检查代币是否支持跨链

contract SuperchainTokenBridge {
    function sendERC20(
        address token,
        address to,
        uint256 amount,
        uint256 chainId
    ) external {
        // ✅ 检查代币是否支持 IERC7802
        require(
            IERC165(token).supportsInterface(type(IERC7802).interfaceId),
            "Token does not support crosschain bridging"
        );
        
        // 执行跨链
        IERC7802(token).crosschainBurn(msg.sender, amount);
        _sendMessage(chainId, token, to, amount);
    }
}

// 如果没有检查，直接调用可能失败：
// ❌ IERC7802(token).crosschainBurn(...) → revert（如果代币不支持）
```

### 场景 2：DApp 自适应功能

```solidity
// DApp 根据代币能力提供不同功能

contract DApp {
    function swapTokens(address token, uint256 amount) external {
        // 方案 A：使用 Permit（更好的用户体验）
        if (IERC165(token).supportsInterface(type(IERC20Permit).interfaceId)) {
            // 用户只需签名，无需 approve 交易
            // 前端请求用户签名 → 一笔交易完成 approve + swap
            usePermitFlow(token, amount);
        }
        // 方案 B：传统 approve（需要两笔交易）
        else {
            // 用户需要先 approve，再 swap
            useTraditionalFlow(token, amount);
        }
    }
    
    function usePermitFlow(address token, uint256 amount) internal {
        // 假设已经有用户的签名
        IERC20Permit(token).permit(
            msg.sender,
            address(this),
            amount,
            deadline,
            v, r, s
        );
        _executeSwap(token, amount);
    }
    
    function useTraditionalFlow(address token, uint256 amount) internal {
        // 需要用户事先调用 token.approve(address(this), amount)
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        _executeSwap(token, amount);
    }
}
```

### 场景 3：钱包和浏览器显示

```solidity
// 区块链浏览器或钱包识别代币类型

contract TokenAnalyzer {
    struct TokenInfo {
        bool isERC20;
        bool hasPermit;
        bool hasVoting;
        bool isSuperchain;
        string[] features;
    }
    
    function analyzeToken(address token) external view returns (TokenInfo memory info) {
        // 检查各种接口支持
        try IERC165(token).supportsInterface(type(IERC20).interfaceId) returns (bool supported) {
            info.isERC20 = supported;
            if (supported) info.features.push("ERC20");
        } catch {}
        
        try IERC165(token).supportsInterface(type(IERC20Permit).interfaceId) returns (bool supported) {
            info.hasPermit = supported;
            if (supported) info.features.push("Permit (EIP-2612)");
        } catch {}
        
        try IERC165(token).supportsInterface(type(IERC5805).interfaceId) returns (bool supported) {
            info.hasVoting = supported;
            if (supported) info.features.push("Governance Voting");
        } catch {}
        
        try IERC165(token).supportsInterface(type(IERC7802).interfaceId) returns (bool supported) {
            info.isSuperchain = supported;
            if (supported) info.features.push("Superchain Bridging");
        } catch {}
        
        return info;
    }
}

// 前端使用
// const info = await analyzer.analyzeToken(MEMECOIN_ADDRESS);
// console.log("Token features:", info.features);
// // 输出: ["ERC20", "Permit (EIP-2612)", "Governance Voting", "Superchain Bridging"]
```

### 场景 4：DAO 治理平台识别

```solidity
// Tally 等治理平台检测代币是否支持治理

contract GovernancePlatform {
    function canCreateProposal(address token) external view returns (bool) {
        // 检查是否支持 ERC5805（投票接口）
        try IERC165(token).supportsInterface(type(IERC5805).interfaceId) returns (bool supported) {
            return supported;
        } catch {
            return false;
        }
    }
    
    function getVotingPower(address token, address user) external view returns (uint256) {
        // 确保代币支持投票
        require(
            IERC165(token).supportsInterface(type(IERC5805).interfaceId),
            "Token does not support voting"
        );
        
        return IERC5805(token).getVotes(user);
    }
}
```

### 场景 5：智能合约工厂

```solidity
// 工厂合约验证部署的代币是否符合要求

contract MemecoinFactory {
    function deployMemecoin(
        string memory name,
        string memory symbol
    ) external returns (address memecoin) {
        // 部署新代币
        memecoin = address(new Memecoin());
        Memecoin(memecoin).initialize(name, symbol);
        
        // ✅ 验证部署的代币支持所需接口
        require(
            IERC165(memecoin).supportsInterface(type(IERC20).interfaceId),
            "Must support ERC20"
        );
        
        require(
            IERC165(memecoin).supportsInterface(type(IERC7802).interfaceId),
            "Must support Superchain bridging"
        );
        
        require(
            IERC165(memecoin).supportsInterface(type(IERC5805).interfaceId),
            "Must support governance"
        );
        
        emit MemecoinDeployed(memecoin, name, symbol);
    }
}
```

---

## 实际案例

### 案例 1：Uniswap 检测代币类型

```javascript
// Uniswap 前端检测代币是否支持 Permit

async function checkPermitSupport(tokenAddress) {
    const ERC165_ABI = ["function supportsInterface(bytes4) view returns (bool)"];
    const token = new ethers.Contract(tokenAddress, ERC165_ABI, provider);
    
    // IERC20Permit 的 interfaceId
    const PERMIT_INTERFACE_ID = "0x9d8ff7da";
    
    try {
        const supportsPermit = await token.supportsInterface(PERMIT_INTERFACE_ID);
        
        if (supportsPermit) {
            console.log("✅ Token supports Permit - can use gasless approval");
            return "permit";
        } else {
            console.log("❌ Token does not support Permit - need traditional approve");
            return "approve";
        }
    } catch (error) {
        console.log("Token does not implement ERC165");
        return "approve";
    }
}

// 使用
const method = await checkPermitSupport(USDC_ADDRESS);
if (method === "permit") {
    // 使用 Permit 流程（一笔交易）
    await swapWithPermit();
} else {
    // 使用传统流程（两笔交易）
    await approve();
    await swap();
}
```

### 案例 2：Etherscan 显示代币特性

```solidity
// Etherscan 后端服务检测代币功能

contract EtherscanTokenAnalyzer {
    function getTokenFeatures(address token) external view returns (string[] memory) {
        string[] memory features = new string[](10);
        uint256 count = 0;
        
        // 基础 ERC20
        if (_supportsInterface(token, type(IERC20).interfaceId)) {
            features[count++] = "ERC-20";
        }
        
        // Permit
        if (_supportsInterface(token, type(IERC20Permit).interfaceId)) {
            features[count++] = "Permit (EIP-2612)";
        }
        
        // 投票
        if (_supportsInterface(token, type(IERC5805).interfaceId)) {
            features[count++] = "Votes (EIP-5805)";
        }
        
        // Superchain
        if (_supportsInterface(token, type(IERC7802).interfaceId)) {
            features[count++] = "Superchain (EIP-7802)";
        }
        
        // Flashmint
        if (_supportsInterface(token, 0x3b3bff0f)) {  // IERC3156 interfaceId
            features[count++] = "Flash Mint (EIP-3156)";
        }
        
        // 截断数组
        string[] memory result = new string[](count);
        for (uint i = 0; i < count; i++) {
            result[i] = features[i];
        }
        return result;
    }
    
    function _supportsInterface(address token, bytes4 interfaceId) 
        internal view returns (bool) 
    {
        try IERC165(token).supportsInterface(interfaceId) returns (bool supported) {
            return supported;
        } catch {
            return false;
        }
    }
}
```

### 案例 3：多链桥智能路由

```solidity
// 跨链桥根据代币能力选择最优路由

contract SmartBridge {
    function bridgeToken(
        address token,
        uint256 amount,
        uint256 targetChain
    ) external {
        // 优先级 1：检查是否支持 Superchain 原生跨链
        if (IERC165(token).supportsInterface(type(IERC7802).interfaceId)) {
            // 使用 Superchain 原生桥（最快、最便宜）
            useSuperchainBridge(token, amount, targetChain);
            return;
        }
        
        // 优先级 2：检查是否有官方桥
        if (hasOfficialBridge(token, targetChain)) {
            // 使用官方桥
            useOfficialBridge(token, amount, targetChain);
            return;
        }
        
        // 优先级 3：使用通用桥（lock + mint）
        useGenericBridge(token, amount, targetChain);
    }
}
```

### 案例 4：NFT Marketplace

```solidity
// NFT 市场检测支付代币类型

contract NFTMarketplace {
    function buyNFT(
        uint256 nftId,
        address paymentToken,
        uint256 price
    ) external {
        // 检查支付代币是否是有效的 ERC20
        require(
            IERC165(paymentToken).supportsInterface(type(IERC20).interfaceId),
            "Invalid payment token"
        );
        
        // 如果支持 Permit，提供更好的用户体验
        if (IERC165(paymentToken).supportsInterface(type(IERC20Permit).interfaceId)) {
            // 前端可以使用 Permit 流程
            // 用户签名 → 一笔交易完成支付
            emit PermitSupported(paymentToken);
        }
        
        // 执行购买
        IERC20(paymentToken).transferFrom(msg.sender, seller, price);
        _transferNFT(nftId, msg.sender);
    }
}
```

---

## 最佳实践

### 1. 实现 supportsInterface 的规范

```solidity
// ✅ 正确：列出所有支持的接口
contract MyToken is ERC20, ERC20Permit, IERC165 {
    function supportsInterface(bytes4 interfaceId) 
        public view virtual override returns (bool) 
    {
        return
            interfaceId == type(IERC20).interfaceId ||
            interfaceId == type(IERC20Permit).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
}

// ❌ 错误：忘记包含 IERC165 本身
contract BadToken is ERC20, IERC165 {
    function supportsInterface(bytes4 interfaceId) 
        public view virtual override returns (bool) 
    {
        return interfaceId == type(IERC20).interfaceId;
        // 缺少 type(IERC165).interfaceId  ❌
    }
}

// ❌ 错误：声明了不支持的接口
contract LyingToken is IERC165 {
    function supportsInterface(bytes4 interfaceId) 
        public view virtual override returns (bool) 
    {
        return interfaceId == type(IERC721).interfaceId;  // 但没有实现 IERC721  ❌
    }
}
```

### 2. 使用 supportsInterface 的规范

```solidity
// ✅ 正确：使用 try-catch 处理不支持 ERC165 的合约
contract SafeCaller {
    function callIfSupported(address token) external {
        try IERC165(token).supportsInterface(type(IERC20Permit).interfaceId) 
            returns (bool supported) 
        {
            if (supported) {
                // 安全调用
                IERC20Permit(token).permit(...);
            }
        } catch {
            // token 不支持 ERC165，使用其他方式
            fallbackMethod(token);
        }
    }
}

// ❌ 错误：不处理不支持 ERC165 的情况
contract UnsafeCaller {
    function callIfSupported(address token) external {
        if (IERC165(token).supportsInterface(type(IERC20Permit).interfaceId)) {
            // 如果 token 不支持 ERC165，这里会 revert  ❌
            IERC20Permit(token).permit(...);
        }
    }
}
```

### 3. Gas 优化

```solidity
// 优化 1：缓存接口检测结果
contract OptimizedDApp {
    mapping(address => bool) private _supportsPermit;
    mapping(address => bool) private _checked;
    
    function swapToken(address token, uint256 amount) external {
        // 第一次检查时缓存结果
        if (!_checked[token]) {
            _supportsPermit[token] = _checkPermitSupport(token);
            _checked[token] = true;
        }
        
        // 使用缓存的结果
        if (_supportsPermit[token]) {
            usePermitFlow(token, amount);
        } else {
            useApproveFlow(token, amount);
        }
    }
}

// 优化 2：使用常量而不是每次计算
contract ConstantOptimized {
    bytes4 private constant ERC20_INTERFACE_ID = 0x36372b07;
    bytes4 private constant PERMIT_INTERFACE_ID = 0x9d8ff7da;
    
    function supportsInterface(bytes4 interfaceId) 
        public pure returns (bool) 
    {
        return
            interfaceId == ERC20_INTERFACE_ID ||
            interfaceId == PERMIT_INTERFACE_ID;
    }
}
```

### 4. 测试建议

```solidity
// 完整的测试用例
contract MemecoinInterfaceTest is Test {
    Memecoin token;
    
    function setUp() public {
        token = new Memecoin();
    }
    
    function testSupportsERC20() public {
        assertTrue(token.supportsInterface(type(IERC20).interfaceId));
    }
    
    function testSupportsPermit() public {
        assertTrue(token.supportsInterface(type(IERC20Permit).interfaceId));
    }
    
    function testSupportsVotes() public {
        assertTrue(token.supportsInterface(type(IERC5805).interfaceId));
    }
    
    function testSupportsSuperchain() public {
        assertTrue(token.supportsInterface(type(IERC7802).interfaceId));
    }
    
    function testSupportsERC165() public {
        assertTrue(token.supportsInterface(type(IERC165).interfaceId));
    }
    
    function testDoesNotSupportRandomInterface() public {
        assertFalse(token.supportsInterface(0xffffffff));
    }
    
    function testDoesNotSupportERC721() public {
        assertFalse(token.supportsInterface(type(IERC721).interfaceId));
    }
}
```

### 5. 文档建议

```solidity
/**
 * @title Memecoin
 * @notice A feature-rich ERC20 token with multiple extensions
 * 
 * Supported Interfaces (ERC165):
 * ─────────────────────────────
 * - IERC20 (0x36372b07)
 *   Standard ERC20 token interface
 *   
 * - IERC20Permit (0x9d8ff7da)
 *   EIP-2612: Permit extension for gasless approvals
 *   
 * - IERC5805 (0xe90fb3f6)
 *   EIP-5805: Voting with delegation
 *   
 * - IERC7802 (0x...)
 *   EIP-7802: Crosschain token interface (SuperchainERC20)
 *   
 * - IERC165 (0x01ffc9a7)
 *   EIP-165: Interface detection standard
 *   
 * - IMemecoin (0x...)
 *   Custom Memecoin interface
 * 
 * @dev Use supportsInterface() to check for supported features before calling
 */
contract Memecoin is IERC165, IERC20, IERC20Permit, IERC5805, IERC7802 {
    // ...
}
```

---

## 快速参考

### 常用接口 ID

```solidity
// 标准接口 ID（常量）
IERC165:         0x01ffc9a7
IERC20:          0x36372b07
IERC20Permit:    0x9d8ff7da
IERC721:         0x80ac58cd
IERC1155:        0xd9b67a26
IERC5805:        0xe90fb3f6  // Votes
IERC7802:        0x...        // SuperchainERC20
```

### 检查接口支持的模板

```solidity
// 安全检查模板
function checkInterface(address contract_, bytes4 interfaceId) 
    internal view returns (bool) 
{
    try IERC165(contract_).supportsInterface(interfaceId) 
        returns (bool supported) 
    {
        return supported;
    } catch {
        return false;
    }
}
```

### 实现 supportsInterface 的模板

```solidity
// 基础模板
function supportsInterface(bytes4 interfaceId) 
    public view virtual override returns (bool) 
{
    return
        interfaceId == type(Interface1).interfaceId ||
        interfaceId == type(Interface2).interfaceId ||
        interfaceId == type(IERC165).interfaceId;  // ← 不要忘记
}
```

### 检查清单

实现 ERC165 时确认：
- [ ] 实现 `supportsInterface` 方法
- [ ] 返回所有实现的接口 ID
- [ ] 包含 `IERC165` 本身
- [ ] 不声明未实现的接口
- [ ] 使用 `type(Interface).interfaceId` 获取 ID
- [ ] 添加完整的测试用例
- [ ] 文档说明支持的接口

---

## 总结

### ERC165 的核心概念

```plaintext
ERC165 = 接口检测标准
    ↓
supportsInterface(interfaceId) → true/false
    ↓
interfaceId = bytes4（通过 XOR 计算）
    ↓
在运行时检测合约功能
```

### Memecoin 的接口支持

```plaintext
Memecoin 支持 7 个接口：

1. IERC20              → 标准 ERC20
2. IERC20Upgradeable   → 可升级 ERC20
3. IERC20Permit        → 签名授权
4. IERC5805            → 投票治理
5. IERC7802            → Superchain 跨链
6. IERC165             → 接口检测
7. IMemecoin           → 自定义功能
```

### 关键要点

```solidity
// 1. 获取 interfaceId
bytes4 id = type(IERC20).interfaceId;

// 2. 检查接口支持
bool supported = IERC165(token).supportsInterface(id);

// 3. 实现 supportsInterface
function supportsInterface(bytes4 interfaceId) public view returns (bool) {
    return interfaceId == type(MyInterface).interfaceId || ...;
}

// 4. interfaceId 计算
interfaceId = selector1 ⊕ selector2 ⊕ selector3 ⊕ ...
```

### 为什么重要？

```plaintext
✅ 类型安全：调用前检查，避免 revert
✅ 功能检测：根据能力提供不同功能
✅ 兼容性：标准化的接口识别
✅ 可扩展：新功能可以被自动发现
✅ 互操作性：不同合约可以安全交互
```

---

## 参考资源

- [EIP-165: Interface Detection](https://eips.ethereum.org/EIPS/eip-165)
- [OpenZeppelin ERC165 文档](https://docs.openzeppelin.com/contracts/4.x/api/utils#ERC165)
- [Solidity 文档 - type](https://docs.soliditylang.org/en/latest/units-and-global-variables.html#type-information)
- [Interface ID 计算器](https://www.4byte.directory/)

---

*最后更新：2024年12月*

