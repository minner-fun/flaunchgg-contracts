# TreasuryActionManager 授权流程详解

## 📚 目录
- [整体架构](#整体架构)
- [TreasuryActionManager 详解](#treasuryactionmanager-详解)
- [授权流程](#授权流程)
- [执行流程](#执行流程)
- [权限控制](#权限控制)
- [实际案例](#实际案例)
- [安全机制](#安全机制)

---

## 整体架构

### 角色关系图

```plaintext
┌─────────────────────────────────────────────────────────────┐
│                      授权和执行流程                          │
└─────────────────────────────────────────────────────────────┘

角色层级：

1. Protocol Owner（协议所有者）
   ↓ 控制
2. TreasuryActionManager（动作管理器）
   ↓ 批准/拒绝
3. ITreasuryAction 实现合约（如 BuyBackManager）
   ↓ 被调用
4. MemecoinTreasury（金库）
   ↓ 检查授权
5. Pool Creator（池创建者）
   ↓ 执行动作
```

### 合约关系

```plaintext
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  PositionManager (constructor)                              │
│  │                                                           │
│  ├─ 接收 params.actionManager                               │
│  │   └─ TreasuryActionManager (由外部部署)                  │
│  │       │                                                   │
│  │       ├─ owner: protocolOwner                            │
│  │       └─ mapping: approvedActions                        │
│  │                                                           │
│  └─ 创建 MemecoinTreasury (每个池一个)                      │
│       │                                                      │
│       └─ initialize(actionManager)                          │
│           └─ 引用同一个 TreasuryActionManager               │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## TreasuryActionManager 详解

### 合约代码

```solidity
// src/contracts/treasury/ActionManager.sol

contract TreasuryActionManager is Ownable {
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // 事件
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    event ActionApproved(address indexed _action);
    event ActionUnapproved(address indexed _action);
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // 存储
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    /// 存储已批准的动作合约地址
    mapping(address _action => bool _approved) public approvedActions;
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // 构造函数
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    /**
     * Sets the contract owner.
     * 设置合约所有者。
     * @dev This contract should be created in the {PositionManager} constructor call.
     */
    constructor(address _protocolOwner) {
        _initializeOwner(_protocolOwner);  // 设置所有者为协议所有者
    }
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // 核心方法（只有 owner 可以调用）
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    /**
     * Approves an action contract.
     * 批准一个操作合约。
     */
    function approveAction(address _action) external onlyOwner {
        approvedActions[_action] = true;
        emit ActionApproved(_action);
    }
    
    /**
     * Remove an action contract from approval.
     * 移除一个操作合约的批准。
     */
    function unapproveAction(address _action) external onlyOwner {
        approvedActions[_action] = false;
        emit ActionUnapproved(_action);
    }
}
```

### 关键特性

```solidity
// 特性 1：基于 Solady 的 Ownable
// - 只有 owner 可以批准/撤销动作
// - owner 是 protocolOwner（协议所有者）

// 特性 2：简单的 mapping 存储
// - address => bool
// - true = 已批准，false = 未批准

// 特性 3：全局共享
// - 所有 MemecoinTreasury 共享同一个 ActionManager
// - 一次批准，所有池都可以使用
```

---

## 授权流程

### 第 1 步：部署 TreasuryActionManager

```solidity
// 部署时（通常在部署 PositionManager 之前）

// 1. 协议团队部署 ActionManager
TreasuryActionManager actionManager = new TreasuryActionManager(protocolOwner);

// 此时：
// - actionManager.owner() == protocolOwner
// - approvedActions 为空（没有批准任何动作）
```

### 第 2 步：部署 PositionManager

```solidity
// 2. 部署 PositionManager，传入 actionManager

PositionManager.ConstructorParams memory params = PositionManager.ConstructorParams({
    poolManager: poolManager,
    nativeToken: nativeToken,
    feeDistribution: feeDistribution,
    initialPrice: initialPrice,
    protocolOwner: protocolOwner,        // ← 协议所有者
    protocolFeeRecipient: feeRecipient,
    flayGovernance: flayGovernance,
    feeEscrow: feeEscrow,
    feeExemptions: feeExemptions,
    actionManager: actionManager,        // ← 传入 ActionManager
    bidWall: bidWall,
    fairLaunch: fairLaunch
});

PositionManager positionManager = new PositionManager(params);

// 此时：
// - positionManager.actionManager == actionManager
// - 所有将来创建的 MemecoinTreasury 都会引用这个 actionManager
```

### 第 3 步：Protocol Owner 批准 Action

```solidity
// 3. Protocol Owner 批准一个或多个 ITreasuryAction 合约

// 场景 A：批准 BuyBackManager
address buyBackManager = 0x123...;
actionManager.approveAction(buyBackManager);
// → approvedActions[buyBackManager] = true ✅
// → emit ActionApproved(buyBackManager)

// 场景 B：批准 StakingManager
address stakingManager = 0x456...;
actionManager.approveAction(stakingManager);
// → approvedActions[stakingManager] = true ✅
// → emit ActionApproved(stakingManager)

// 场景 C：批准自定义动作
address customAction = 0x789...;
actionManager.approveAction(customAction);
// → approvedActions[customAction] = true ✅
```

### 第 4 步：创建池时自动设置

```solidity
// 4. 用户创建池时，MemecoinTreasury 自动初始化

function flaunch(FlaunchParams calldata _params) external payable {
    // ... 创建 memecoin 和 treasury ...
    
    // 初始化 MemecoinTreasury，传入 actionManager
    MemecoinTreasury(memecoinTreasury).initialize(
        payable(address(this)),      // positionManager
        address(actionManager),       // ← ActionManager 地址
        nativeToken,
        _poolKey
    );
    
    // 此时：
    // - memecoinTreasury.actionManager == actionManager
    // - 这个 treasury 可以执行所有已批准的动作
}
```

### 完整时序图

```plaintext
时间轴：部署 → 批准 → 创建池 → 执行

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. 部署阶段（协议团队）
   
   Protocol Team
        ↓
   部署 ActionManager(protocolOwner)
        ↓
   actionManager.owner = protocolOwner ✅
   
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

2. 批准阶段（Protocol Owner）
   
   Protocol Owner (0xABCD...)
        ↓
   actionManager.approveAction(buyBackManager)
        ↓
   approvedActions[buyBackManager] = true ✅
        ↓
   actionManager.approveAction(stakingManager)
        ↓
   approvedActions[stakingManager] = true ✅
   
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

3. 创建池阶段（用户）
   
   Alice 创建 MEME 池
        ↓
   positionManager.flaunch(...)
        ↓
   创建 MemecoinTreasury
        ↓
   treasury.initialize(..., actionManager, ...)
        ↓
   treasury.actionManager = actionManager ✅
   
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

4. 执行阶段（Pool Creator）
   
   Alice (Pool Creator)
        ↓
   treasury.executeAction(buyBackManager, data)
        ↓
   检查：actionManager.approvedActions[buyBackManager]
        ↓
   如果 true → 执行 ✅
   如果 false → revert ❌
```

---

## 执行流程

### MemecoinTreasury.executeAction()

```solidity
// src/contracts/treasury/MemecoinTreasury.sol:71-97

function executeAction(address _action, bytes memory _data) public nonReentrant {
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // 步骤 1：检查动作是否已批准
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    if (!actionManager.approvedActions(_action)) revert ActionNotApproved();
    // ↑ 这里检查授权！
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // 步骤 2：检查调用者是否是 Pool Creator
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    address poolCreator = poolKey.memecoin(nativeToken).creator();
    if (poolCreator != msg.sender) revert Unauthorized();
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // 步骤 3：授权代币给动作合约
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    IERC20 token0 = IERC20(Currency.unwrap(poolKey.currency0));
    IERC20 token1 = IERC20(Currency.unwrap(poolKey.currency1));
    
    token0.approve(_action, type(uint).max);  // 临时授权
    token1.approve(_action, type(uint).max);
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // 步骤 4：领取费用
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    claimFees();  // 确保 treasury 有最新的余额
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // 步骤 5：执行动作
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    ITreasuryAction(_action).execute(poolKey, _data);
    emit ActionExecuted(_action, poolKey, _data);
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // 步骤 6：撤销授权
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    token0.approve(_action, 0);  // 清零授权
    token1.approve(_action, 0);
}
```

### 执行检查流程

```plaintext
用户调用：treasury.executeAction(buyBackManager, data)
        ↓
┌────────────────────────────────────────────────────┐
│ 检查 1：动作是否已批准？                           │
│ actionManager.approvedActions[buyBackManager]      │
│   ↓                                                │
│ true  → 继续 ✅                                    │
│ false → revert ActionNotApproved() ❌              │
└────────────────────────────────────────────────────┘
        ↓
┌────────────────────────────────────────────────────┐
│ 检查 2：调用者是否是 Pool Creator？                │
│ msg.sender == poolCreator                          │
│   ↓                                                │
│ true  → 继续 ✅                                    │
│ false → revert Unauthorized() ❌                   │
└────────────────────────────────────────────────────┘
        ↓
┌────────────────────────────────────────────────────┐
│ 检查 3：临时授权代币                               │
│ token0.approve(buyBackManager, max)                │
│ token1.approve(buyBackManager, max)                │
└────────────────────────────────────────────────────┘
        ↓
┌────────────────────────────────────────────────────┐
│ 执行：调用动作合约                                 │
│ ITreasuryAction(buyBackManager).execute(...)       │
└────────────────────────────────────────────────────┘
        ↓
┌────────────────────────────────────────────────────┐
│ 清理：撤销授权                                     │
│ token0.approve(buyBackManager, 0)                  │
│ token1.approve(buyBackManager, 0)                  │
└────────────────────────────────────────────────────┘
        ↓
完成！
```

---

## 权限控制

### 三层权限控制
这里说明白了，其实是协议管理者，是flunch协议官方，来控制着金库合约的行为授权。授权后，是池所有者，才有权利执行某个动作。other用户，自始至终都无权限。每个meme币，都有自己meme币合约，和金库合约。金库管理者合约只有一个。并且归flunch官方所有。
```plaintext
┌──────────────────────────────────────────────────────┐
│ 第 1 层：Protocol Owner 控制                         │
├──────────────────────────────────────────────────────┤
│ 权限：                                               │
│ - 批准新的 ITreasuryAction 合约                     │
│ - 撤销已批准的 ITreasuryAction 合约                 │
│                                                      │
│ 方法：                                               │
│ - actionManager.approveAction()                     │
│ - actionManager.unapproveAction()                   │
│                                                      │
│ 限制：                                               │
│ - 只有 Protocol Owner 可以调用                      │
│ - 通过 onlyOwner 修饰符保护                         │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│ 第 2 层：ActionManager 白名单                        │
├──────────────────────────────────────────────────────┤
│ 权限：                                               │
│ - 只有已批准的动作可以被执行                         │
│                                                      │
│ 检查：                                               │
│ - approvedActions[_action] == true                  │
│                                                      │
│ 限制：                                               │
│ - 未批准的动作会 revert ActionNotApproved()         │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│ 第 3 层：Pool Creator 权限                           │
├──────────────────────────────────────────────────────┤
│ 权限：                                               │
│ - 只有池创建者可以执行动作                           │
│                                                      │
│ 检查：                                               │
│ - msg.sender == poolCreator                         │
│                                                      │
│ 限制：                                               │
│ - 其他人无法操作别人的 treasury                      │
│ - 通过 Unauthorized() 保护                          │
└──────────────────────────────────────────────────────┘
```

### 权限矩阵

```plaintext
┌────────────────────────────────────────────────────────────┐
│ 操作                  │ Protocol Owner │ Pool Creator │ 其他 │
├────────────────────────────────────────────────────────────┤
│ approveAction()       │ ✅             │ ❌           │ ❌   │
│ unapproveAction()     │ ✅             │ ❌           │ ❌   │
│ executeAction()       │ ❌             │ ✅ (自己的)  │ ❌   │
│ claimFees()           │ ✅             │ ✅           │ ✅   │
└────────────────────────────────────────────────────────────┘

注：
- claimFees() 任何人都可以调用（无权限限制）
- executeAction() 只能操作自己创建的池
```

---

## 实际案例

### 案例 1：批准 BuyBackManager

```javascript
// 1. Protocol Owner 部署 BuyBackManager
const BuyBackManager = await ethers.getContractFactory("BuyBackManager");
const buyBackManager = await BuyBackManager.deploy(...);
await buyBackManager.deployed();

console.log("BuyBackManager deployed:", buyBackManager.address);
// 输出: 0x123...

// 2. Protocol Owner 批准 BuyBackManager
const actionManager = await ethers.getContractAt(
    "TreasuryActionManager",
    ACTION_MANAGER_ADDRESS
);

const tx = await actionManager.approveAction(buyBackManager.address);
await tx.wait();

console.log("BuyBackManager approved ✅");
// 触发事件: ActionApproved(0x123...)

// 3. 验证批准
const isApproved = await actionManager.approvedActions(buyBackManager.address);
console.log("Is approved:", isApproved);
// 输出: true
```

### 案例 2：Pool Creator 执行回购

```javascript
// Alice 是 MEME 池的创建者

// 1. Alice 获取她的 treasury 地址
const treasury = await positionManager.memecoinTreasury(MEME_ADDRESS);
console.log("Treasury:", treasury);

// 2. Alice 准备回购参数
const buyBackData = ethers.utils.defaultAbiCoder.encode(
    ["uint256", "uint256"],
    [
        ethers.utils.parseEther("100"),  // 使用 100 ETH
        ethers.utils.parseEther("1000")  // 期望回购 1000 MEME
    ]
);

// 3. Alice 执行回购
const memecoinTreasury = await ethers.getContractAt(
    "MemecoinTreasury",
    treasury
);

const tx = await memecoinTreasury.executeAction(
    buyBackManager.address,
    buyBackData
);
await tx.wait();

console.log("Buyback executed ✅");
// 触发事件: ActionExecuted(buyBackManager, poolKey, data)
```

### 案例 3：尝试未批准的动作

```javascript
// Bob 部署了一个恶意的动作合约
const MaliciousAction = await ethers.getContractFactory("MaliciousAction");
const maliciousAction = await MaliciousAction.deploy();
await maliciousAction.deployed();

// Bob 尝试执行（没有通过 Protocol Owner 批准）
const treasury = await ethers.getContractAt(
    "MemecoinTreasury",
    TREASURY_ADDRESS
);

try {
    await treasury.executeAction(maliciousAction.address, "0x");
} catch (error) {
    console.log("Error:", error.message);
    // 输出: "ActionNotApproved()"
}

// ❌ 失败！未批准的动作无法执行
```

### 案例 4：撤销已批准的动作

```javascript
// Protocol Owner 发现 BuyBackManager 有漏洞，需要撤销

// 1. Protocol Owner 撤销批准
const tx = await actionManager.unapproveAction(buyBackManager.address);
await tx.wait();

console.log("BuyBackManager unapproved ✅");
// 触发事件: ActionUnapproved(0x123...)

// 2. 验证撤销
const isApproved = await actionManager.approvedActions(buyBackManager.address);
console.log("Is approved:", isApproved);
// 输出: false

// 3. 尝试执行会失败
try {
    await treasury.executeAction(buyBackManager.address, data);
} catch (error) {
    console.log("Error:", error.message);
    // 输出: "ActionNotApproved()"
}

// ❌ 已撤销的动作无法执行
```

---

## 安全机制

### 1. 白名单机制

```solidity
// 只有 Protocol Owner 批准的动作可以执行

// ✅ 安全：Protocol Owner 审核所有动作合约
if (!actionManager.approvedActions(_action)) revert ActionNotApproved();

// 好处：
// - 防止恶意合约
// - 统一管理
// - 可以撤销
```

### 2. 权限分离

```plaintext
Protocol Owner：
- 控制哪些动作可以被执行
- 不能执行具体的动作

Pool Creator：
- 只能执行已批准的动作
- 只能操作自己的 treasury

分离的好处：
- Protocol Owner 不能滥用个人的 treasury
- Pool Creator 不能执行恶意动作
- 双重保护 ✅
```

### 3. 临时授权

```solidity
// 执行前授权
token0.approve(_action, type(uint).max);
token1.approve(_action, type(uint).max);

// 执行动作
ITreasuryAction(_action).execute(poolKey, _data);

// 执行后撤销
token0.approve(_action, 0);
token1.approve(_action, 0);

// 好处：
// - 最小化授权时间
// - 防止长期风险
// - 即使动作合约有漏洞，影响也有限
```

### 4. 重入保护

```solidity
// 使用 Solady 的 ReentrancyGuard
function executeAction(address _action, bytes memory _data) 
    public 
    nonReentrant  // ← 防止重入
{
    // ...
}

// 好处：
// - 防止递归调用
// - 保护 treasury 安全
```

### 5. 双重检查

```solidity
// 检查 1：动作是否批准
if (!actionManager.approvedActions(_action)) revert ActionNotApproved();

// 检查 2：调用者是否是创建者
address poolCreator = poolKey.memecoin(nativeToken).creator();
if (poolCreator != msg.sender) revert Unauthorized();

// 双重保护 ✅
```

---

## 完整流程图

```plaintext
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
阶段 1：初始化（部署时）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Protocol Team
    ↓
部署 ActionManager
    ↓
ActionManager.constructor(protocolOwner)
    ↓
owner = protocolOwner ✅

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
阶段 2：批准动作（Protocol Owner）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Protocol Owner
    ↓
actionManager.approveAction(buyBackManager)
    ↓
检查：msg.sender == owner?
    ↓ ✅
approvedActions[buyBackManager] = true
    ↓
emit ActionApproved(buyBackManager)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
阶段 3：创建池（用户）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Alice
    ↓
positionManager.flaunch(params)
    ↓
创建 MemecoinTreasury
    ↓
treasury.initialize(..., actionManager, ...)
    ↓
treasury.actionManager = actionManager ✅

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
阶段 4：执行动作（Pool Creator）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Alice (Pool Creator)
    ↓
treasury.executeAction(buyBackManager, data)
    ↓
┌─────────────────────────────────────────┐
│ 检查 1：动作是否批准？                 │
│ actionManager.approvedActions[action]   │
│ → true ✅                               │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ 检查 2：调用者是否是创建者？           │
│ msg.sender == poolCreator               │
│ → true ✅                               │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ 授权代币                                │
│ token0.approve(action, max)             │
│ token1.approve(action, max)             │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ 领取费用                                │
│ claimFees()                             │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ 执行动作                                │
│ ITreasuryAction(action).execute(...)    │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ 撤销授权                                │
│ token0.approve(action, 0)               │
│ token1.approve(action, 0)               │
└─────────────────────────────────────────┘
    ↓
完成 ✅
```

---

## 快速参考

### 关键地址获取

```solidity
// 获取 ActionManager
address actionManager = positionManager.actionManager();

// 获取 Treasury
address treasury = positionManager.memecoinTreasury(memecoinAddress);

// 检查动作是否批准
bool isApproved = TreasuryActionManager(actionManager).approvedActions(actionAddress);
```

### 关键方法

```solidity
// ActionManager
function approveAction(address _action) external onlyOwner
function unapproveAction(address _action) external onlyOwner
mapping(address => bool) public approvedActions

// MemecoinTreasury
function executeAction(address _action, bytes memory _data) public nonReentrant
function claimFees() public
```

### 错误处理

```solidity
// 常见错误
error ActionNotApproved();  // 动作未批准
error Unauthorized();       // 调用者不是池创建者
error Reentrancy();         // 重入攻击
```

---

## 总结

### 授权流程核心

```plaintext
1. 部署：
   Protocol Team → 部署 ActionManager(protocolOwner)

2. 批准：
   Protocol Owner → actionManager.approveAction(action)

3. 使用：
   Pool Creator → treasury.executeAction(action, data)

4. 检查：
   ✅ 动作是否批准？
   ✅ 调用者是否是创建者？

5. 执行：
   临时授权 → 执行动作 → 撤销授权
```

### 安全特性

```plaintext
✅ 白名单机制（只有批准的动作）
✅ 权限分离（Owner vs Creator）
✅ 临时授权（最小化风险）
✅ 重入保护（nonReentrant）
✅ 双重检查（批准 + 权限）
```

### 关键要点

```plaintext
谁控制什么：
- Protocol Owner：控制哪些动作可以执行
- Pool Creator：控制何时执行动作
- ActionManager：全局共享，统一管理

安全保证：
- 恶意合约无法执行（未批准）
- 他人无法操作你的 treasury（权限检查）
- 授权时间最短（临时授权）
```

---

*最后更新：2024年12月*

