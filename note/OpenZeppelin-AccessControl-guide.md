# OpenZeppelin AccessControl 技术指南

## 📖 概述

`AccessControl` 是 OpenZeppelin 提供的**基于角色的访问控制系统**（Role-Based Access Control, RBAC），用于实现智能合约的细粒度权限管理。

**导入方式：**
```solidity
import {AccessControl} from '@openzeppelin/contracts/access/AccessControl.sol';
```

**官方文档：** https://docs.openzeppelin.com/contracts/5.x/access-control

---

## 🎯 核心作用

| 功能 | 说明 |
|------|------|
| **细粒度权限管理** | 为不同账户分配不同的角色，实现精确的权限控制 |
| **多角色支持** | 一个账户可以同时拥有多个角色 |
| **角色层级管理** | 每个角色都有对应的管理员角色 |
| **动态权限控制** | 运行时授予或撤销权限 |

---

## 🔑 核心概念

### 1. 角色定义

角色使用 `bytes32` 类型表示，通常通过 `keccak256` 哈希函数生成：

```solidity
// 定义角色常量
bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

// 默认管理员角色（所有角色的默认管理员）
bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
```

### 2. 角色层级

- 每个角色都有一个**管理员角色**（Admin Role）
- 管理员角色可以授予或撤销该角色
- `DEFAULT_ADMIN_ROLE` 是最高级别的管理员角色
- 可以通过 `_setRoleAdmin()` 设置角色的管理员

---

## 📋 主要函数

### 查询函数

```solidity
// 检查账户是否拥有指定角色
function hasRole(bytes32 role, address account) public view returns (bool)

// 获取角色的管理员角色
function getRoleAdmin(bytes32 role) public view returns (bytes32)
```

### 权限管理函数

```solidity
// 授予角色（需要调用者拥有该角色的管理员权限）
function grantRole(bytes32 role, address account) public onlyRole(getRoleAdmin(role))

// 撤销角色（需要调用者拥有该角色的管理员权限）
function revokeRole(bytes32 role, address account) public onlyRole(getRoleAdmin(role))

// 主动放弃角色（账户自己放弃）
function renounceRole(bytes32 role, address account) public
```

### 修饰符

```solidity
// 限制只有拥有指定角色的账户才能调用
modifier onlyRole(bytes32 role)
```

### 内部函数

```solidity
// 内部授予角色（不检查权限，通常在构造函数中使用）
function _grantRole(bytes32 role, address account) internal

// 设置角色的管理员角色
function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal
```

---

## 💡 基本使用示例

### 示例 1：简单的角色控制合约

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract MyToken is AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    
    mapping(address => uint256) public balances;
    
    constructor() {
        // 部署者获得默认管理员权限
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // 部署者同时获得铸币权限
        _grantRole(MINTER_ROLE, msg.sender);
    }
    
    // 只有拥有 MINTER_ROLE 的账户可以调用
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        balances[to] += amount;
    }
    
    // 只有拥有 BURNER_ROLE 的账户可以调用
    function burn(address from, uint256 amount) public onlyRole(BURNER_ROLE) {
        require(balances[from] >= amount, "Insufficient balance");
        balances[from] -= amount;
    }
}
```

### 示例 2：自定义修饰符

```solidity
contract MyContract is AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    // 自定义修饰符，提供更友好的错误信息
    modifier onlyOperator() {
        if (!hasRole(OPERATOR_ROLE, msg.sender)) {
            revert("Not authorized: requires OPERATOR_ROLE");
        }
        _;
    }
    
    function sensitiveOperation() public onlyOperator {
        // 敏感操作
    }
}
```

---

## 🔍 在 FairLaunch 合约中的实际应用

### 合约继承

```solidity
contract FairLaunch is AccessControl {
    // ...
}
```

### 构造函数中初始化

```solidity
constructor (IPoolManager _poolManager) {
    poolManager = _poolManager;
    
    // 授予部署者默认管理员权限
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
}
```

### 使用自定义修饰符限制函数访问

```solidity
// 自定义修饰符
modifier onlyPositionManager {
    if (!hasRole(ProtocolRoles.POSITION_MANAGER, msg.sender)) {
        revert NotPositionManager();
    }
    _;
}

// 受保护的函数
function createPosition(
    PoolId _poolId,
    int24 _initialTick,
    uint _flaunchesAt,
    uint _initialTokenFairLaunch,
    uint _fairLaunchDuration
) public virtual onlyPositionManager returns (FairLaunchInfo memory) {
    // 只有 PositionManager 可以调用
    // ...
}
```

### 受保护的函数列表

在 FairLaunch 合约中，以下函数只能被拥有 `POSITION_MANAGER` 角色的地址调用：

- `createPosition()` - 创建公平启动位置
- `closePosition()` - 关闭公平启动位置
- `fillFromPosition()` - 从公平启动位置填充
- `modifyRevenue()` - 修改收入

---

## 🎨 优势对比

### 传统 Ownable vs AccessControl

| 特性 | Ownable | AccessControl |
|------|---------|---------------|
| **所有者数量** | 单一所有者 | 支持多个角色 |
| **权限细分** | ❌ 无法细分 | ✅ 可以定义多种角色 |
| **多重身份** | ❌ 一个地址只能是或不是所有者 | ✅ 一个地址可以拥有多个角色 |
| **权限转移** | 只能完全转移所有权 | 可以灵活授予/撤销特定角色 |
| **安全性** | 单点故障风险 | 分散权限，降低风险 |
| **灵活性** | 低 | 高 |

### 使用场景建议

- **使用 Ownable：** 简单合约，只需要单一管理员
- **使用 AccessControl：** 复杂合约，需要多种权限级别

---

## 🔧 完整工作流程示例

```solidity
// 1. 部署合约
FairLaunch fairLaunch = new FairLaunch(poolManager);
// 此时 msg.sender 拥有 DEFAULT_ADMIN_ROLE

// 2. 管理员授予 POSITION_MANAGER 角色
fairLaunch.grantRole(
    ProtocolRoles.POSITION_MANAGER, 
    positionManagerAddress
);

// 3. 检查角色
bool hasRole = fairLaunch.hasRole(
    ProtocolRoles.POSITION_MANAGER,
    positionManagerAddress
); // true

// 4. POSITION_MANAGER 调用受保护的函数（✅ 成功）
positionManagerAddress.call(
    abi.encodeWithSelector(
        fairLaunch.createPosition.selector,
        poolId,
        initialTick,
        flaunchesAt,
        initialTokenFairLaunch,
        fairLaunchDuration
    )
);

// 5. 普通地址调用受保护的函数（❌ 失败）
randomAddress.call(
    abi.encodeWithSelector(
        fairLaunch.createPosition.selector,
        // ...
    )
); // 回滚，抛出 NotPositionManager() 错误

// 6. 撤销角色
fairLaunch.revokeRole(
    ProtocolRoles.POSITION_MANAGER,
    positionManagerAddress
);

// 7. 主动放弃角色
fairLaunch.renounceRole(
    ProtocolRoles.POSITION_MANAGER,
    positionManagerAddress
);
```

---

## 📚 高级用法

### 1. 多层级角色管理

```solidity
contract AdvancedContract is AccessControl {
    bytes32 public constant SUPER_ADMIN = keccak256("SUPER_ADMIN");
    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32 public constant OPERATOR = keccak256("OPERATOR");
    
    constructor() {
        // 设置 DEFAULT_ADMIN_ROLE 为 SUPER_ADMIN 的管理员
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        
        // 设置角色层级：SUPER_ADMIN 可以管理 ADMIN
        _setRoleAdmin(ADMIN, SUPER_ADMIN);
        
        // 设置角色层级：ADMIN 可以管理 OPERATOR
        _setRoleAdmin(OPERATOR, ADMIN);
        
        // 授予初始 SUPER_ADMIN
        _grantRole(SUPER_ADMIN, msg.sender);
    }
}
```

### 2. 组合多个角色

```solidity
function adminOnlyFunction() public {
    require(
        hasRole(ADMIN_ROLE, msg.sender) || hasRole(SUPER_ADMIN_ROLE, msg.sender),
        "Requires admin or super admin"
    );
    // 函数逻辑
}
```

### 3. 临时权限授予

```solidity
mapping(address => uint256) public roleExpiry;

modifier onlyRoleWithExpiry(bytes32 role) {
    require(hasRole(role, msg.sender), "Missing role");
    require(roleExpiry[msg.sender] > block.timestamp, "Role expired");
    _;
}

function grantTemporaryRole(
    bytes32 role,
    address account,
    uint256 duration
) public onlyRole(getRoleAdmin(role)) {
    grantRole(role, account);
    roleExpiry[account] = block.timestamp + duration;
}
```

---

## ⚠️ 最佳实践

### ✅ 推荐做法

1. **在构造函数中初始化管理员**
   ```solidity
   constructor() {
       _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
   }
   ```

2. **使用常量定义角色**
   ```solidity
   bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
   ```

3. **提供清晰的错误信息**
   ```solidity
   modifier onlyAdmin {
       if (!hasRole(ADMIN_ROLE, msg.sender)) {
           revert NotAdmin();
       }
       _;
   }
   ```

4. **文档化所有角色**
   - 在代码注释中说明每个角色的用途
   - 在 README 中列出所有角色和权限

5. **最小权限原则**
   - 只授予必要的权限
   - 定期审查和清理不必要的角色

### ❌ 避免做法

1. **不要硬编码地址**
   ```solidity
   // ❌ 不推荐
   if (msg.sender == 0x123...) { ... }
   
   // ✅ 推荐
   if (hasRole(ADMIN_ROLE, msg.sender)) { ... }
   ```

2. **不要忽略角色层级**
   - 合理设计角色的管理员关系
   - 避免循环依赖

3. **不要在没有保护的情况下使用 `_grantRole`**
   - `_grantRole` 不检查权限，只在构造函数或内部使用
   - 对外接口使用 `grantRole`

---

## 🔒 安全注意事项

### 1. DEFAULT_ADMIN_ROLE 风险

⚠️ **警告：** `DEFAULT_ADMIN_ROLE` 拥有最高权限，可以管理所有其他角色。

**最佳实践：**
```solidity
// 部署后立即转移给多签钱包
function transferAdminToMultisig(address multisig) external onlyRole(DEFAULT_ADMIN_ROLE) {
    grantRole(DEFAULT_ADMIN_ROLE, multisig);
    renounceRole(DEFAULT_ADMIN_ROLE, msg.sender);
}
```

### 2. 角色撤销时机

确保在撤销关键角色之前有替代方案：

```solidity
function safeRevokeAdmin(address oldAdmin, address newAdmin) external {
    require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
    require(oldAdmin != newAdmin, "Same address");
    
    // 先授予新管理员
    grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
    // 再撤销旧管理员
    revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
}
```

### 3. 检查零地址

```solidity
function grantRoleSafe(bytes32 role, address account) external {
    require(account != address(0), "Cannot grant role to zero address");
    grantRole(role, account);
}
```

---

## 📊 事件监听

AccessControl 会发出以下事件：

```solidity
// 角色授予时触发
event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

// 角色撤销时触发
event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

// 角色管理员变更时触发
event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
```

**监听示例：**
```javascript
// 使用 ethers.js 监听角色授予事件
contract.on("RoleGranted", (role, account, sender) => {
    console.log(`Role ${role} granted to ${account} by ${sender}`);
});
```

---

## 🧪 测试示例

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MyContract.sol";

contract AccessControlTest is Test {
    MyContract public myContract;
    address public admin = address(1);
    address public operator = address(2);
    address public user = address(3);
    
    function setUp() public {
        vm.prank(admin);
        myContract = new MyContract();
    }
    
    function testAdminCanGrantRole() public {
        bytes32 OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
        
        vm.prank(admin);
        myContract.grantRole(OPERATOR_ROLE, operator);
        
        assertTrue(myContract.hasRole(OPERATOR_ROLE, operator));
    }
    
    function testNonAdminCannotGrantRole() public {
        bytes32 OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
        
        vm.prank(user);
        vm.expectRevert();
        myContract.grantRole(OPERATOR_ROLE, operator);
    }
    
    function testOperatorCanCallProtectedFunction() public {
        bytes32 OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
        
        vm.prank(admin);
        myContract.grantRole(OPERATOR_ROLE, operator);
        
        vm.prank(operator);
        myContract.operatorOnlyFunction();
        // 应该成功执行
    }
    
    function testUserCannotCallProtectedFunction() public {
        vm.prank(user);
        vm.expectRevert();
        myContract.operatorOnlyFunction();
    }
}
```

---

## 📖 相关资源

- [OpenZeppelin AccessControl 文档](https://docs.openzeppelin.com/contracts/5.x/api/access#AccessControl)
- [OpenZeppelin 访问控制指南](https://docs.openzeppelin.com/contracts/5.x/access-control)
- [Solidity by Example - Access Control](https://solidity-by-example.org/app/access-control/)

---

## 📝 总结

`AccessControl` 是一个强大而灵活的权限管理工具，适用于需要复杂权限控制的智能合约：

✅ **使用场景：**
- 多人协作的 DeFi 协议
- 需要多种操作权限的复杂系统
- 需要动态调整权限的应用

✅ **核心优势：**
- 细粒度权限控制
- 灵活的角色管理
- 标准化且经过审计
- 易于扩展和维护

✅ **关键要点：**
- 合理设计角色层级
- 保护好 `DEFAULT_ADMIN_ROLE`
- 遵循最小权限原则
- 做好事件监听和审计

---

*最后更新：2025-12-14*

