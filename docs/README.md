# Prize Savings 架构文档

> 文档组织规则见 [架构文档组织方式.md](./架构文档组织方式.md)：跨模块内容进 `docs/`，模块内部细节进各模块的 `ARCHITECTURE.md`；ABI/地址/类型以代码为单一事实源，文档只指向、不复制。

## 从哪读起

| 想了解 | 读哪篇 |
|--------|--------|
| 产品要做什么（冻结设计 v0.1） | [prd/prize-savings-lottery-design.md](./prd/prize-savings-lottery-design.md) |
| 系统由哪些模块组成、资金如何流转 | [architecture/overview.md](./architecture/overview.md) |
| 合约职责、开奖状态机、三条不变量 | [architecture/contracts.md](./architecture/contracts.md) |
| ABI/地址/事件如何在模块间共享 | [architecture/module-contracts.md](./architecture/module-contracts.md) |
| 本地链部署、地址与环境变量 | [architecture/deployment.md](./architecture/deployment.md) |
| 不可逆决策的来龙去脉 | [decisions/](./decisions/) |

## 模块级文档（就近存放）

- [contracts/ARCHITECTURE.md](../contracts/ARCHITECTURE.md)
- [frontend/ARCHITECTURE.md](../frontend/ARCHITECTURE.md)
- [subgraph/ARCHITECTURE.md](../subgraph/ARCHITECTURE.md)
- [keeper/ARCHITECTURE.md](../keeper/ARCHITECTURE.md)
- [packages/contracts/README.md](../packages/contracts/README.md)（共享 SDK）

## ADR 索引

| ADR | 主题 | 状态 |
|-----|------|------|
| [ADR-0001](./decisions/ADR-0001-pnpm-monorepo-contracts-excluded.md) | pnpm monorepo，contracts 不入 workspace | 已接受 |
| [ADR-0002](./decisions/ADR-0002-foundry-solc.md) | Foundry + Solidity 0.8.24 + OZ v5 | 已接受 |
| [ADR-0003](./decisions/ADR-0003-keeper-injected-rng-over-pfda.md) | M0 白名单 keeper 注入随机数，不做 PFDA/VRF | 已接受 |
| [ADR-0004](./decisions/ADR-0004-single-asset-usdc.md) | M0 单资产 USDC + 单一奖币 | 已接受 |
