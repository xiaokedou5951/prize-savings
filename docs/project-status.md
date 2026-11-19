# Prize Savings 项目状态快照

> 快照时间：2026-11-19 · 对应 commit：`639c05b`（main 分支，版本 0.4.4，建立 CI 流水线，含 P0-1/P0-2）
> 本文件是**时间点快照**，记录项目当前完成度、验证硬证据、已知缺口与下一步规划，便于后续参考与交接。它不替代活文档：系统架构见 [architecture/overview.md](./architecture/overview.md)，冻结设计见 [prd/prize-savings-lottery-design.md](./prd/prize-savings-lottery-design.md)。

---

## 1. 一句话定位

去中心化无损储蓄抽奖（No-Loss Lottery），仿 PoolTogether V5：用户本金永不损失，存款收益汇聚成奖池，按时间加权平均余额（TWAB）每日随机开奖。完整闭环：存款 → 赚取收益 → 清算注入奖池 → 每日开奖 → 派奖 → 随时赎回本金。

权威设计文档（冻结，只读）：[prize-savings-lottery-design.md](./prd/prize-savings-lottery-design.md)。

---

## 2. 当前进度快照

### 2.1 模块状态总览

| 模块 | 状态 | 完成度 | 说明 |
|------|------|--------|------|
| `contracts` | ✅ 闭环完成 | ~90% | 核心合约 + RngRelay(VRF) + 三档收益源 + 测试全绿 |
| `packages/contracts` | ✅ 可用 | ~90% | ABI 常量 + 部署地址 SSOT，前端源码直编消费 |
| `frontend` | ✅ MVP 可构建 | ~80% | 5 路由，存/取/领奖/奖池展示，生产构建通过 |
| 文档体系 | ✅ 已对齐 | ~85% | PRD/ADR/architecture/E2E 完整；P0-2 已修正 overview 的 VRF/收益源漂移（G6 关闭） |
| `keeper` | ⬜ 脚手架 | ~5% | [src/index.ts](../keeper/src/index.ts) 仅空 `main()`，清算/开奖逻辑未实现 |
| `subgraph` | ⬜ 空脚手架 | ~5% | [schema.graphql](../subgraph/schema.graphql) 仅注释，`dataSources: []` |
| CI | ✅ 已建立 | ~100% | [.github/workflows/ci.yml](../.github/workflows/ci.yml)：contracts（fmt+build+test+ABI 生成物 diff）/ frontend:build / keeper:build 三 job 并行；PR 全绿（分支保护需在仓库后台开启） |

> 完成度为综合评估（功能覆盖 + 验证证据 + 文档同步），非精确度量。

### 2.2 验证硬证据（本快照生成时实跑）

| 验证项 | 命令 | 结果 |
|--------|------|------|
| 合约编译 + 测试 | `forge test --root contracts` | **58 passed / 0 failed / 1 skipped**（13 个 test suite；`ForkStataYield` 因无 `BASE_RPC_URL` 预期 skip） |
| 前端生产构建 | `pnpm frontend:build` | ✅ Next 16.3.6（Turbopack）编译通过，TypeScript 严格检查通过，7 个页面生成（含 `/`、`/vault`、`/prizes`、`/account`、`/draw/[drawId]`） |
| CI 流水线 | `.github/workflows/ci.yml`（push/PR 触发） | ✅ 三 job 并行：contracts（`forge fmt --check` + build + test + ABI 生成物无 diff）/ frontend:build / keeper:build；干净环境复验 58 passed / 0 failed / 1 skipped |

合约测试套件明细（来自 `forge test` 实跑输出）：

| 套件 | 通过数 | 覆盖 |
|------|--------|------|
| `RngRelay.t.sol` | 7 | VRF 请求→回调→开奖、在途防重入、时间校验、非 coordinator 注入、awardDraw revert 时 try/catch 清零、安全阀 |
| `Integration.t.sol` | 2 | 端到端闭环（Simple + Observation 两种 TWAB 各一遍） |
| `PrizePool.t.sol` | 9 | 开奖权限/周期、3 档分布、重复领取防护、零供应、单用户全档 |
| `LiquidationPair.t.sol` | 3 | 线性降价、奖币入池/yield 出金、可清算额上钳 |
| `ObservationTwabController.t.sol` | 9 | 时间加权、历史点查询、环形覆盖二分、仅 vault 可写 |
| `AaveYieldVault.t.sol` | 7 | 适配器 roundtrip、计息均摊、通胀攻击防护、市场校验 |
| `Invariants.t.sol` | 2 | fuzz（256 runs/用例）：零损失 + 份额守恒 |
| `InvariantsHandler.t.sol` | 6 | handler 状态机 fuzz（256 runs/用例）：3 条不变量 × Simple/Observation 两种 TWAB 实现，含 TWAB 历史只读（已 mutator 校验非空） |
| 其余（SimpleTwab / PrizeVault / TwabControllerBehavior 等） | 13 | 单测行为覆盖 |

---

## 3. 各模块状态详情

### 3.1 contracts

Foundry 工程（Solidity 0.8.24，不在 pnpm workspace 内），M0 完整闭环已实现并通过测试。

**已实现合约**（见 [contracts/ARCHITECTURE.md](../contracts/ARCHITECTURE.md) 与 [architecture/contracts.md](./architecture/contracts.md)）：

- `TwabController`（抽象基类）+ 两个可插拔实现：`SimpleTwabController`（追加 checkpoint/线性扫描，默认）与 `ObservationTwabController`（2^16 环形缓冲/二分），共用 `ITwabController` 接口，部署时由 `TWAB_MODE` 切换。
- `PrizeVault` + `TwabERC20`：ERC-4626 金库，份额路由到 TwabController（份额不落地存储，避免双写漂移）。
- `PrizePool`：3 档硬编码分级开奖（Grand 1 / 次级 4 / Canary 100，60%/25%/15%），中奖概率严格正比 TWAB（Algorand/PoolTogether 式加权抽签）。
- `LiquidationPair`：线性降价清算，奖币直转 PrizePool。
- `RngRelay`：Chainlink VRF v2.5 consumer，请求随机数并在回调中调用 `PrizePool.awardDraw`，随机数只能来自 VRF 回调（[ADR-0003](./decisions/ADR-0003-keeper-injected-rng-over-pfda.md) 已废弃，被本实现取代）。
- `AaveYieldVault`：收益源回退适配器（无 StataToken 市场时），含首充通胀攻击防护。

**收益源三档回退**（[ADR-0005](./decisions/ADR-0005-yield-source-stata-first.md)）：现成 ERC-4626（主路径 Aave StataToken）> 自研 AaveYieldVault 适配器 > MockERC4626（仅本地链）。部署脚本按环境变量选择，非本地链缺本金路径配置一律 revert，不静默降级。

**三条全局不变量**（PRD 7.3）：

1. **零损失**：`PrizeVault.totalAssets() >= totalSupply()` —— 有 fuzz 覆盖。
2. **份额守恒**：`TwabController.totalSupply() == PrizeVault.totalSupply()` —— 有 fuzz 覆盖。
3. **TWAB 只读追溯**：`awardDraw` 后存取款不改变历史 draw 的中奖结果 —— ✅ **有 handler 状态机 fuzz 覆盖**（[InvariantsHandler.t.sol](../contracts/test/InvariantsHandler.t.sol)，256 runs × 两种 TWAB 实现；已 mutator 校验非空，G1 关闭）。

### 3.2 frontend

Next.js 16（App Router, Turbopack）+ React 19 + TS strict + Tailwind v4，Web3 栈 wagmi v2 / viem v2 / RainbowKit v2 / React Query v5。5 个路由页面：Landing、Vault（存/赎）、Prizes（奖池分级 + 开奖历史）、Account（摘要 + 可领奖）、Draw（单期详情）。详见 [frontend/ARCHITECTURE.md](../frontend/ARCHITECTURE.md)。

⚠️ 历史开奖/领取数据当前用 viem `getContractEvents` 直读链上事件（仅 anvil/低区块量适用），subgraph 落地后需替换（见缺口 G4）。

### 3.3 packages/contracts

共享 SDK `@prize-savings/contracts`：导出 6 个 ABI 常量（含 `rngRelayAbi`）与 `DEPLOYMENTS` / `getDeployment(chainId)` 地址 SSOT。前端以 TS 源码直编消费（`transpilePackages`）。ABI 由 `pnpm contracts:abis` 从合约产物单向生成，禁止业务代码手写 ABI。详见 [architecture/module-contracts.md](./architecture/module-contracts.md)。

`DEPLOYMENTS` 仅登记了 31337（anvil 确定性地址）；84532（Base Sepolia）留待首次真实部署后回填，未登记时由 `NEXT_PUBLIC_*` 环境变量解析。

### 3.4 keeper

**no-op 脚手架**：[src/index.ts](../keeper/src/index.ts) 仅空 `main()`。规划职责（见 [keeper/ARCHITECTURE.md](../keeper/ARCHITECTURE.md) 与 [module-contracts.md §3](./architecture/module-contracts.md)）：

1. **收益清算**（无许可）：轮询 `liquidatableBalanceOf()`，有可清算收益时调 `swapExactAmountOut`。
2. **到期开奖**（无许可）：轮询 `nextDrawStart()`，到点调 `RngRelay.requestDraw()` 触发 VRF。

当前清算/开奖靠手工 `cast` 模拟（见 [testing/manual-e2e-v2.1.md](./testing/manual-e2e-v2.1.md)）。

### 3.5 subgraph

**空脚手架**：[schema.graphql](../subgraph/schema.graphql) 仅占位注释，[subgraph.yaml](../subgraph/subgraph.yaml) `dataSources: []`。事件→实体的契约约定已在 [module-contracts.md §2](./architecture/module-contracts.md) 定义，落地时直接遵循。

### 3.6 CI

已建立 [.github/workflows/ci.yml](../.github/workflows/ci.yml)，`push` 到 `main` 与 `pull_request` 触发，三个并行 job：

- **contracts**：安装 Foundry 工具链（钉 `1.5.1`，与本地一致，避免新版 stable 改变继承 invariant 的发现行为）→ 缓存 `contracts/lib`（cache key 钉在 `contracts/install-deps.sh` 的 sha256）→ `bash contracts/install-deps.sh`（缓存未命中时）→ `forge fmt --check` → `forge build` → `forge test` → 重新生成 ABI 并 `git diff --exit-code` 校验无漂移。
- **frontend**：node 22 + pnpm 10.33.0 → `pnpm install --frozen-lockfile` → `pnpm frontend:build`。
- **keeper**：同上 → `pnpm keeper:build`。

依赖安装的单一事实源是 [contracts/install-deps.sh](../contracts/install-deps.sh)，钉住 `forge-std@v1.9.6` / `openzeppelin-contracts@v5.0.0` / `chainlink=smartcontractkit/chainlink-evm@contracts-v1.5.0`（Chainlink 已将 Solidity 合约拆分到独立仓库 `smartcontractkit/chainlink-evm`，原 `smartcontractkit/chainlink` v2.x 无 `contracts/` 目录；该仓库 tag 命名为 `contracts-v<ver>`，`contracts-v1.5.0` 即 @chainlink/contracts 1.5.0，commit `86aa5a1d`；用 `chainlink=` 前缀装到 `lib/chainlink/`，与 `remappings.txt` 的 `@chainlink/contracts/=lib/chainlink/contracts/` 对齐），解决干净检出后 `contracts/lib/`（已 gitignore）缺失导致无法编译的可复现性缺口。无需任何密钥：fork 测试缺 `BASE_RPC_URL` 自动 skip，前端 build 有 env 兜底。

> 注意："PR 必须全绿"的分支保护规则（Settings → Branches → Require status checks to pass before merging）是 GitHub 仓库**设置项**，不在 workflow 文件内，需在仓库后台手动开启。

---

## 4. 迭代脉络（git）

| 版本 | commit | 内容 |
|------|--------|------|
| 0.0.1 | `dfed62b` | 脚手架与架构搭建（5 模块 monorepo 骨架） |
| 0.0.2 | `5d78680` | 项目规则 |
| 0.1.0 | `2c29891` | 合约 MVP：TwabController 双实现 + PrizeVault + PrizePool + LiquidationPair，闭环 + fuzz 不变量 + 集成测试 |
| 0.2.0 | `f0a2f4e` | 前端 MVP：5 路由 + 存/取/领奖 |
| 0.2.1–0.2.5 | `98531d7`…`9456145` | Liquidation 事件 + ABI 生成脚本 + 本地 anvil 启动脚本 + 本地部署脚本 + 手工 E2E 文档（含双账户 TWAB 验证） |
| 0.2.5.1 | `b9b3e15` | 修复清算定价未归一化 token 小数位数 |
| 0.3.1 | `8a8873a` | 接入 Base Sepolia 真实收益源：AaveYieldVault 适配器 + StataToken 主路径 + ADR-0005 + ForkStataYield 测试 |
| 0.3.2–0.3.2.3 | `d22ff8f`…`dfb5c0d` | 未知链 env 解析部署地址 + 修复 eth_getLogs 区块范围超限 + 清理临时 fork 配置 |
| 0.4.1 | `d5ff32f` | RngRelay 合约集成 Chainlink VRF v2.5 随机数开奖 |
| 0.4.2 | `5129e5d` | 添加项目状态快照文档并更新 README 链接 |
| **0.4.3** | **`0d8d896`** | 新增 handler 状态机不变量 fuzz 测试（P0-1）并更新相关配置文档 |
| **0.4.4** | **`639c05b`** | 建立 CI 流水线（P0-3）：`.github/workflows/ci.yml` 三 job + `contracts/install-deps.sh` 钉住依赖（修正 chainlink → chainlink-evm 仓库）；更新项目状态文档（当前最新） |

分支：`main`（当前）、`v0.2.6`、`v0.3.2`。

---

## 5. 关键决策摘要（ADR）

| ADR | 主题 | 状态 |
|-----|------|------|
| [ADR-0001](./decisions/ADR-0001-pnpm-monorepo-contracts-excluded.md) | pnpm monorepo，contracts 不入 workspace | 已接受 |
| [ADR-0002](./decisions/ADR-0002-foundry-solc.md) | Foundry + Solidity 0.8.24 + OZ v5 | 已接受 |
| [ADR-0003](./decisions/ADR-0003-keeper-injected-rng-over-pfda.md) | M0 白名单 keeper 注入随机数，不做 PFDA/VRF | **已废弃**（0.4.1 被 RngRelay + VRF 取代） |
| [ADR-0004](./decisions/ADR-0004-single-asset-usdc.md) | M0 单资产 USDC + 单一奖币 | 已接受 |
| [ADR-0005](./decisions/ADR-0005-yield-source-stata-first.md) | 收益源 StataToken 优先、自研回退 | 已接受 |

---

## 6. 已知缺口与风险

按优先级排列（🔴 高 / 🟠 中高 / 🟡 中）：

| 编号 | 缺口 | 优先级 | 说明 |
|------|------|--------|------|
| **G1** | 不变量 3（TWAB 只读追溯）无自动化 fuzz | ✅ 已修复（P0-1） | 新增 [InvariantsHandler.t.sol](../contracts/test/InvariantsHandler.t.sol) handler 状态机 fuzz：3 条不变量 × Simple/Observation 双实现各 256 runs，已 mutator 校验非空；[contracts/ARCHITECTURE.md](../contracts/ARCHITECTURE.md) "待补"已更新 |
| **G2** | keeper 未实现 | 🔴 高 | 测试网无人值守则不会自动开奖/清算，"测试网运行"不成立 |
| **G3** | M0 集成"测试网运行"无落地证据 | 🔴 高 | 路径 D（真实 Base Sepolia）只有 runbook；`DEPLOYMENTS[84532]` 未回填；[manual-e2e 执行记录表](./testing/manual-e2e-v2.1.md) 为空；真实 VRF 回调未验证 |
| **G4** | subgraph 未实现 | 🟠 中高 | 前端历史数据靠 `getContractEvents`，仅 anvil 可用；测试网/主网必然再撞 eth_getLogs 区块范围限制（0.3.2.2 已修过一次） |
| **G5** | 无 CI | ✅ 已修复（P0-3） | [.github/workflows/ci.yml](../.github/workflows/ci.yml) 三 job 覆盖 contracts/frontend/keeper 防回归；[contracts/install-deps.sh](../contracts/install-deps.sh) 钉住依赖版本解决干净检出无法编译；"PR 必须全绿"的分支保护需在 GitHub 仓库后台手动开启 |
| **G6** | 文档漂移 | ✅ 已修复（P0-2） | [overview.md](./architecture/overview.md) 已更新为 VRF 已集成 + 收益源三档回退；[docs/README.md](./README.md) ADR 索引已含 ADR-0005；全仓 grep 无"不做 VRF"残留矛盾 |
| **G7** | M1/M2/M3 未开始 | — | 审计、主网上线（M1）；多资产/多 vault/Claimer/自动派奖（M2）；无许可 vault factory + PFDA（M3）。见 PRD 第 11 节 |

---

## 7. 下一步规划（P0–P3）

对照 PRD 第 11 节里程碑，当前处于 **M0 收尾阶段**。

### P0 · M0 安全加固与文档对齐（1–2 天，本地，无外部依赖）

| # | 任务 | 验收标准 |
|---|------|----------|
| ✅ P0-1 | 不变量 3 fuzz + 真正的状态机 handler fuzz | 已完成：新增 `InvariantsHandler.t.sol` handler 测试，3 条不变量 × Simple/Observation 双实现各 256 runs 通过，已 mutator 校验非空 |
| ✅ P0-2 | 修正文档漂移 | 已完成：[overview.md](./architecture/overview.md) 更新为 VRF 已集成 + 收益源三档回退；[docs/README.md](./README.md) ADR 索引已含 ADR-0005；grep 全仓无"不做 VRF"残留矛盾 |
| ✅ P0-3 | 建立 CI 流水线 | 已完成：`.github/workflows/ci.yml` 三 job（contracts fmt/build/test/ABI diff + frontend:build + keeper:build）；`contracts/install-deps.sh` 钉住依赖（chainlink-evm 仓库修正）；干净环境复验 58 passed / 1 skipped；分支保护需仓库后台开启 |

### P1 · M0 集成落地——真实测试网跑通（1 天，需测试网资源）

| # | 任务 | 验收标准 |
|---|------|----------|
| P1-1 | Base Sepolia 真实部署 + 冒烟 | 按 [deployment.md runbook](./architecture/deployment.md) 部署；VRF 订阅创建+注资+RngRelay 加 consumer；`cast call` 验证 `drawManager()==RngRelay`、`totalAssets()>=totalSupply()`；小额 deposit→redeem roundtrip 成功 |
| P1-2 | 真实 VRF 开奖验证 | 到点后 `requestDraw`，等待真实 VRF 回调（~1–2 分钟），确认 `DrawFulfilled` 事件与 `_drawId` 递增；填写 manual-e2e 执行记录表 |
| P1-3 | 回填测试网 SSOT（可选） | 把 84532 地址提交到 `DEPLOYMENTS[84532]`，团队共享 |

### P2 · 自动化补全——keeper + subgraph（3–5 天，M0→M1 桥梁）

| # | 任务 | 验收标准 | 依赖 |
|---|------|----------|------|
| P2-1 | keeper 清算循环 | 接入 `@prize-savings/contracts`；轮询 `liquidatableBalanceOf()` 出价清算；交易 revert/nonce 冲突有重试退避；幂等可重入；`keeper:build` 通过 | P1-1 |
| P2-2 | keeper 开奖循环 | 轮询 `nextDrawStart()`，到点调 `requestDraw()`；监控 `DrawFulfilled/DrawFailed`，失败仅告警不重复请求 | P2-1 |
| P2-3 | subgraph 落地 | 按 [module-contracts.md §2](./architecture/module-contracts.md) 实现 schema 与映射；`subgraph:codegen && build` 通过；部署一个实例 | P1-1 |
| P2-4 | 前端切换到 subgraph | `useDraws` 从 `getContractEvents` 改查 subgraph；保留零地址 `enabled:false` 守卫 | P2-3 |

### P3 · M1 审计与上线（按需，依赖 P0–P2 完成）

- P3-1 审计准备包（不变量文档、攻击面分析、已知风险）
- P3-2 主网 fork 全链路 dry-run
- P3-3 主网部署 + bug bounty

---

## 8. 常用命令速查

在仓库根执行：

```bash
pnpm chain                  # 启动 anvil 本地链（含 Multicall3 注入）
pnpm deploy:local           # 本地部署并回填 frontend/.env.local
pnpm deploy:testnet         # Base Sepolia 部署
pnpm contracts:build        # forge build --root contracts
pnpm contracts:test         # forge test --root contracts
pnpm contracts:abis         # 重新生成 ABI 到 packages/contracts
pnpm frontend:dev / build
pnpm keeper:dev / build
pnpm subgraph:codegen / build
```

---

## 9. 维护说明

- 本快照是**时间点记录**，每次里程碑推进（如完成 P0/P1/P2 任一阶段、或合约/前端有重大变更）时应更新本文件的"进度快照""硬证据""缺口""规划"四节。
- 活文档（`architecture/` 系列、各模块 `ARCHITECTURE.md`）随代码同步更新；本快照只在阶段节点刷新，不随每次提交改动。
- 若本快照与活文档冲突，以**代码与活文档**为准，本快照需尽快订正。
