# 部署拓扑

> M0 只有一个目标环境：**本地 anvil**。尚无测试网/主网部署，地址表先承载本地联调流程。

## 链配置

| 网络 | chainId | RPC | 用途 |
|------|---------|-----|------|
| anvil（foundry 本地链） | 31337 | `http://127.0.0.1:8545` | 合约开发、前端联调 |
| 测试网 / 主网 | — | — | 未规划，见 PRD 第 11 节 M0 集成之后 |

前端链配置硬编码为 wagmi `foundry`（[chains.ts](../../frontend/src/lib/config/chains.ts)）；foundry 端点见 [foundry.toml](../../contracts/foundry.toml) 的 `[rpc_endpoints] local`。

## 本地部署步骤

推荐一条命令完成「部署 + 回填前端地址」（[scripts/deploy-local.sh](../../scripts/deploy-local.sh)）：

```bash
# 终端 1：起链（含 Multicall3 注入），保持常驻
pnpm chain

# 终端 2：部署并自动把 7 个地址写入 frontend/.env.local（保留已填的 WalletConnect projectId）
pnpm deploy:local
```

脚本内部等价于执行下列手工步骤；需要自定义时可直接照做：

```bash
# 编译 + 部署（--broadcast 实际发交易）
DEPLOYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
TWAB_MODE=simple \
  forge script script/Deploy.s.sol --root contracts --rpc-url local --broadcast
```

部署脚本 [Deploy.s.sol](../../contracts/script/Deploy.s.sol) 会依次部署 USDC、奖币、`MockERC4626`、TWAB（按 `TWAB_MODE` 二选一）、PrizePool、PrizeVault、LiquidationPair，完成 `setVault` / `setLiquidationPair` 组装，并把 7 个地址打印到 stdout。

| 脚本变量 | 值 | 说明 |
|----------|----|------|
| `DEPLOYER_PRIVATE_KEY` | anvil 测试账户私钥 | anvil 默认预置 10 个带 10000 ETH 的账户 |
| `TWAB_MODE` | `simple`（默认）/ `observation` | 选择 TWAB 实现，两种实现行为测试等价 |

## 已部署地址（SSOT）

权威地址表在代码中：[packages/contracts/src/deployments.ts](../../packages/contracts/src/deployments.ts) 的 `DEPLOYMENTS[31337]`。`pnpm deploy:local` 自动写入 `frontend/.env.local`（默认路径，不入库）。需要共享给团队或换种方式时也可以：

1. 把 stdout 地址写入 `DEPLOYMENTS[31337]`（随仓库共享）；或
2. 手动复制 [frontend/.env.example](../../frontend/.env.example) 为 `frontend/.env.local` 填写（个人本地、不入库）。

> 安全约束：`.env*` 不入库；`PRIVATE_KEY` 只允许存在于本地环境。

## 环境变量清单

### frontend（`NEXT_PUBLIC_` 前缀，构建期注入）

| 变量 | 必填 | 说明 |
|------|------|------|
| `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` | 连钱包时必填 | WalletConnect Cloud projectId；占位值仅能通过构建 |
| `NEXT_PUBLIC_CHAIN_ID` | 否 | 默认 `31337` |
| `NEXT_PUBLIC_RPC_URL` | 否 | 默认 `http://127.0.0.1:8545`（当前前端链配置直接用 foundry 预设） |
| `NEXT_PUBLIC_USDC` / `NEXT_PUBLIC_PRIZE_TOKEN` / `NEXT_PUBLIC_YIELD_VAULT` / `NEXT_PUBLIC_TWAB_CONTROLLER` / `NEXT_PUBLIC_PRIZE_POOL` / `NEXT_PUBLIC_PRIZE_VAULT` / `NEXT_PUBLIC_LIQUIDATION_PAIR` | 否 | 逐项覆盖 SSOT 地址 |

### keeper（运行期注入，[keeper/.env.example](../../keeper/.env.example)）

| 变量 | 说明 |
|------|------|
| `RPC_URL` | 节点 RPC |
| `PRIVATE_KEY` | 清算/开奖机器人签名密钥；需先被 `setDrawManager` 授权并持有奖币 |

### 合约脚本（forge 环境变量）

`DEPLOYER_PRIVATE_KEY`、`TWAB_MODE`（见上）。

## 角色交接（部署后必做）

[Deploy.s.sol](../../contracts/script/Deploy.s.sol) 中 `PrizePool` 的初始 `drawManager` 是部署者本人。keeper 落地后需由 owner 执行一次：

```solidity
PrizePool.setDrawManager(keeperAddress);
```

在此之前，可用部署者账户直接 `cast send` 调 `awardDraw` 完成手工开奖联调。

## keeper 运行形态

规划为常驻 Node 进程（`tsx watch` 开发 / `node dist` 生产，见根 `pnpm keeper:dev|build`），轮询周期边界驱动清算与开奖。**当前为 no-op 脚手架**，无任何部署物；M1 接入 VRF 后需重新评估其可信边界（见 [ADR-0003](../decisions/ADR-0003-keeper-injected-rng-over-pfda.md)）。
