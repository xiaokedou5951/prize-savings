# ADR-0001：pnpm monorepo，contracts 不纳入 workspace

- 状态：**已接受**
- 日期：2026-09（脚手架期决策，事后补记）

## 背景

仓库需要同时承载 Foundry 合约工程与多个 Node/TypeScript 模块（frontend、subgraph、keeper、共享 SDK）。两种工具链的依赖模型完全不同：Forge 用 git submodule / `lib/` 管理 Solidity 依赖（forge-std、OpenZeppelin、Chainlink），Node 侧用 pnpm workspace。

## 决策

采用 pnpm workspace monorepo，workspace 成员为 `frontend`、`subgraph`、`keeper`、`packages/*`；**`contracts/` 明确排除在 workspace 之外**（见 [pnpm-workspace.yaml](../../pnpm-workspace.yaml)）。对合约的构建/测试通过根 `package.json` scripts 以 `forge build/test --root contracts` 转发。

合约对 Node 侧的输出（ABI、地址）收敛到 `packages/contracts` 这一个共享 SDK，TS 模块只依赖它，不直接读 `contracts/` 目录。

## 后果

- 正：合约工程保持纯净 Foundry 布局，无需 `package.json`、无需伪造 Node 构建链；`forge` 与 `pnpm` 各自的缓存/锁文件互不污染。
- 正：TS 侧对合约的依赖面被 SDK 收窄，ABI 提取方式可独立演进。
- 负：跨工程操作要靠根 scripts 转发，无法用一条 `pnpm -r build` 覆盖合约（已在根 scripts 提供 `contracts:build/test` 缓解）。
- 负：SDK 的 ABI 是提取产物而非自动依赖，存在漂移面（见 [module-contracts.md](../architecture/module-contracts.md) 第 1 节已知缺口）。

## 备选方案（被否）

1. **contracts 也放进 workspace**：需给 Foundry 工程加 `package.json` 与空构建脚本，且 pnpm 会尝试管理其不存在的 JS 依赖，徒增噪音。
2. **完全拆仓（合约一个 repo，应用一个 repo）**：M0 单团队、接口高频变动，跨仓同步 ABI 与版本的成本高于收益；M2 协议稳定后再评估。
3. **Turborepo**：当前只有 4 个 Node 包、任务拓扑简单，pnpm 原生 workspace + 根 scripts 已足够，不引入额外编排层。
