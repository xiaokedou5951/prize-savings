# subgraph 模块架构

The Graph 索引服务（graph-cli + graph-ts / AssemblyScript）。**当前为空脚手架**：[subgraph.yaml](subgraph.yaml) 的 `dataSources: []`，[schema.graphql](schema.graphql) 只有占位注释，`src/` 与 `abis/` 为空。前端 M0 暂用 viem `getContractEvents` 直读事件代替（见 [../frontend/ARCHITECTURE.md](../frontend/ARCHITECTURE.md)）。

## 规划目标

把合约事件落成可查询实体，支撑开奖历史、中奖记录、存款流水等跨区块聚合视图。**事件 → 实体映射契约已冻结**，见 [../docs/architecture/module-contracts.md](../docs/architecture/module-contracts.md) 第 2 节，落地时直接照表实现：

- `DrawAwarded` → `Draw`；`PrizeClaimed` → `PrizeClaim` + `Winner` 聚合；`DrawManagerSet` → 单例 `ProtocolState`。
- `LiquidationPair.Liquidation` → `Liquidation` 清算流水（sender/receiver indexed，amountIn/amountOut 为钳制后成交值）。
- ERC-4626 `Deposit/Withdraw`（PrizeVault）→ 流水实体与 `VaultAccount` 快照。
- pvUSDC ERC20 `Transfer` → 份额变动明细（可选）。

## 落地步骤与约束

1. `pnpm contracts:abis`（或 `forge build --root contracts`）后，把所需 ABI 从 `contracts/out/**/*.json` 复制到 [abis/](abis/)（或改为从 `@prize-savings/contracts` 取——graph-cli 对 TS 包支持有限，预期仍需 JSON 副本，须在 [module-contracts.md](../docs/architecture/module-contracts.md) 记录该副本链路）。
2. 在 [schema.graphql](schema.graphql) 定义上表实体，在 [subgraph.yaml](subgraph.yaml) 注册 PrizePool / PrizeVault / LiquidationPair 三个 dataSource 及各自事件 handler。
3. `src/` 用 AssemblyScript 写映射；BigInt/小数处理遵循 AssemblyScript 限制（无原生 `bigint`，用 `BigInt` 类，金额按最小单位存 `BigDecimal!` 转换只在展示侧）。

## 命令

```bash
pnpm subgraph:codegen  # graph codegen（生成 AssemblyScript 类型）
pnpm subgraph:build    # graph build
```
