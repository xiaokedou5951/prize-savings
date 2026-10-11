# contracts 模块架构

M0 闭环合约（Foundry / Solidity 0.8.24）：存款 → 底层计息 → 收益清算入池 → 每日 TWAB 开奖 → 领奖 → 赎回本金。跨模块的协议级内容（不变量详解、权限矩阵、中奖算法）在 [../docs/architecture/contracts.md](../docs/architecture/contracts.md)，本篇只讲模块内部组织与测试布局。

## 目录结构

```text
src/
├── interfaces/          # ITwabController / IPrizeVault / IPrizePool / ILiquidationPair
│                        # 上游契约：TS ABI 从实现合约产物提取，接口是模块边界
├── PrizeVault/          # PrizeVault.sol + TwabERC20.sol（份额路由层）
├── PrizePool/           # PrizePool.sol（开奖/分级/领取，3 档硬编码 pure 配置）
├── TwabController/      # TwabController(抽象) + Simple/Observation 两实现
├── LiquidationPair/     # 线性降价清算
├── libraries/           # TwabLibSimple（追加扫描）/ ObservationLib+TwabLibObservation（环/二分）
├── Claimer/ VaultFactory/ RngRelayAuction/   # 空目录占位，M1/M2 再填
└── mocks/               # MockERC20 / MockERC4626（仅本地与测试）
script/Deploy.s.sol      # 本地一键部署 + 组装授权（TWAB_MODE 切 TWAB 实现）
test/                     # 单元 / fuzz 不变量 / 端到端
```

## 模块内关键取舍

- **TWAB 算法与权限分层**：[TwabController.sol](src/TwabController/TwabController.sol) 只留 `onlyVault` 权限与参数校验，存储/算法全部在子类。两种实现对同一接口结果等价，行为测试共用 [TwabControllerBehavior.t.sol](test/TwabControllerBehavior.t.sol)（抽象基类），两个 12 行的子类测试各跑一遍，防分叉。
- **份额不落地存储**：PrizeVault 继承的 ERC20 余额函数全部 override 路由到 TwabController，避免"vault 余额账"与"TWAB 账"双写漂移（对应不变量 2）。
- **收益路径**：`_pullAssets` 先花合约 loose 余额、不足再从 yieldVault redeem；`liquidatableBalanceOf` 天然只暴露超额资产，零损失不需要额外记账。
- **Mock 边界**：`MockERC4626.mockHarvest` 以捐赠抬升份额单价模拟计息，不模拟真实 DeFi 风险；接真实收益源是 PRD M0 集成阶段任务。

## 测试布局

| 文件 | 覆盖 |
|------|------|
| [Invariants.t.sol](test/Invariants.t.sol) | fuzz：存取款/收益注入任意序列下零损失 + 份额守恒 |
| [Integration.t.sol](test/Integration.t.sol) | 端到端闭环，两种 TWAB 实现各跑一遍 |
| [PrizeVault.t.sol](test/PrizeVault.t.sol) | 存赎 roundtrip、harvest 后可清算额、权限 |
| [PrizePool.t.sol](test/PrizePool.t.sol) | 到期/权限开奖、3 档分布、重复领取防护、零供应 |
| [LiquidationPair.t.sol](test/LiquidationPair.t.sol) | 线性降价、奖币入池/yield 出金、可清算额上钳、`Liquidation` 事件断言（含钳制值） |
| [TwabControllerBehavior.t.sol](test/TwabControllerBehavior.t.sol) | 时间加权、历史点查询、仅 vault 可写、零地址/非法区间 |
| [ObservationTwabController.t.sol](test/ObservationTwabController.t.sol) | 大量 checkpoint 环形覆盖 + 二分正确性 |

> 待补：以 Foundry `invariant` handler 做真正的状态机 fuzz（当前为 fuzz 单测形态）；fork 测试真实 ERC-4626。

## 常用命令

```bash
forge build --root contracts          # 或根目录 pnpm contracts:build
forge test --root contracts -vvv      # 或 pnpm contracts:test
forge fmt --root contracts --check
```

## 与系统的衔接点

- ABI 输出 → [../packages/contracts/](../packages/contracts/)，链路与漂移风险见 [../docs/architecture/module-contracts.md](../docs/architecture/module-contracts.md)。
- 部署与角色交接 → [../docs/architecture/deployment.md](../docs/architecture/deployment.md)。
