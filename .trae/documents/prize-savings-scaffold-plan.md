# 储蓄抽奖应用（Prize Savings）脚手架与架构搭建计划

## 1. Summary（目标）

依据 [prize-savings-lottery-design.md](file:///Users/mac/work/2026/web3/sean-lottery-research/prize-savings-lottery-design.md) 第 6.2 节的仓库结构建议，在当前目录 `/Users/mac/work/2026/web3/sean-lottery-research` 建立一个 **pnpm workspace 单仓（monorepo）**，一次性搭好全部 5 个模块的**目录结构、配置与工具链**，**不编写任何业务代码**。

覆盖模块：
1. `contracts/` — Foundry 合约工程（Solidity）
2. `frontend/` — Next.js 前端工程（React + wagmi/viem）
3. `subgraph/` — The Graph 索引工程
4. `keeper/` — 清算/开奖机器人工程（Node + TypeScript）
5. `packages/` — 共享 SDK（viem 合约封装 / 共享 TS 配置）

**边界（明确不做）**：所有 `.sol` 合约实现、前端业务页面/表单/数据 hook 逻辑、subgraph 的 schema/映射、keeper 的清算/开奖逻辑、SDK 的合约封装实现均**留空占位**，只做工程骨架与可复用的架构约定。

---

## 2. Current State（现状）

- 当前目录仅含一个设计文档 `prize-savings-lottery-design.md`，**非 git 仓库**，无其它文件。
- 工具链已就绪（已探测）：node `v22.22.0`、pnpm `10.33.0`、Foundry（forge/anvil）`1.5.1`、git `2.50.1`。
- 网络可用（可执行 `forge install` / `pnpm install` / create-next-app）。

---

## 3. 决策与假设（Decisions & Assumptions）

| 决策点 | 结论 |
|--------|------|
| 星级编排 | `pnpm-workspace.yaml` 单仓（不含 Turborepo） |
| 模块范围 | 全部 5 个模块（用户已确认） |
| contracts 是否入 workspace | 不入（Foundry 工程无 node 构建需求），用根 package.json scripts + `forge --root` 转发 |
| 前端脚手架方式 | `create-next-app`（App Router + TS + Tailwind + ESLint + `src/` 目录 + `@/*` 别名） |
| Web3 技术栈 | wagmi v2 + viem v2 + RainbowKit v2 + @tanstack/react-query v5 |
| 合约依赖 | forge-std + OpenZeppelin Contracts v5 + Chainlink Contracts（VRF/Automation 接口） |
| Solidity 编译器 | `0.8.24`（OZ v5 / Chainlink 均兼容），optimizer 开 |
| Node 引擎约束 | `>=20`（`engines` + `.nvmrc` = 22） |
| 包命名 | `@prize-savings/*` 作用域（frontend / subgraph / keeper / contracts） |
| git | 执行 `git init` 建仓，**不提交**（用户未要求） |
| 文档 | 不新建 README/*.md（遵循"不主动建文档"要求），工程说明以目录名 + package.json 脚本注释承载 |

---

## 4. 目标目录结构（Target Tree）

```
prize-savings/               # 单仓根（即当前目录）
├── prize-savings-lottery-design.md   # 保留既有设计文档
├── pnpm-workspace.yaml
├── package.json                      # 根，private，聚合脚本
├── .gitignore
├── .nvmrc                            # 22
├── .editorconfig
│
├── contracts/                        # Foundry 工程（非 workspace 成员）
│   ├── foundry.toml
│   ├── remappings.txt
│   ├── .gitignore
│   ├── lib/                          # forge-std / openzeppelin-contracts / chainlink
│   ├── src/
│   │   ├── TwabController/
│   │   ├── PrizeVault/
│   │   ├── PrizePool/
│   │   ├── LiquidationPair/
│   │   ├── Claimer/
│   │   ├── VaultFactory/
│   │   ├── RngRelayAuction/
│   │   └── mocks/                    # VRF mock / ERC4626 mock / 奖币 mock
│   ├── test/
│   └── script/
│
├── frontend/                         # Next.js（workspace 成员）
│   ├── package.json
│   ├── next.config.mjs
│   ├── tsconfig.json
│   ├── postcss.config.mjs
│   ├── .env.example
│   └── src/
│       ├── app/
│       │   ├── layout.tsx
│       │   ├── page.tsx
│       │   └── providers.tsx        # wagmi + RainbowKit Provider
│       ├── components/               # 占位
│       ├── hooks/                    # 占位
│       └── lib/
│           ├── config/
│           │   ├── chains.ts        # 目标链配置（测试网占位）
│           │   └── wagmi.ts         # createConfig / getDefaultConfig
│           └── contracts/           # ABI / 地址 JSON 占位（后续脚本生成）
│
├── subgraph/                         # The Graph（workspace 成员）
│   ├── package.json
│   ├── tsconfig.json
│   ├── subgraph.yaml                 # 占位（空 dataSources）
│   ├── schema.graphql                # 占位（仅注释）
│   ├── abis/                         # 占位
│   └── src/                          # 占位
│
├── keeper/                           # Node + TS 机器人（workspace 成员）
│   ├── package.json
│   ├── tsconfig.json
│   ├── .env.example
│   └── src/
│       └── index.ts                  # 空入口占位（no-op main）
│
└── packages/
    └── contracts/                    # @prize-savings/contracts（workspace 成员）
        ├── package.json
        ├── tsconfig.json
        └── src/
            └── index.ts              # 仅 re-export 占位
```

---

## 5. Proposed Changes（具体改动）

### 5.1 根目录（monorepo 骨架）

**`pnpm-workspace.yaml`**
- `packages: ["frontend", "subgraph", "keeper", "packages/*"]`（contracts 排除）。

**`package.json`**（根，`private: true`，`packageManager: pnpm@10.33.0`，engines node>=20）
- scripts 转发：
  - `"chain": "anvil"`
  - `"contracts:build": "forge build --root contracts"`
  - `"contracts:test": "forge test --root contracts"`
  - `"frontend:dev": "pnpm --filter @prize-savings/frontend dev"`
  - `"frontend:build": "pnpm --filter @prize-savings/frontend build"`
  - `"keeper:dev": "pnpm --filter @prize-savings/keeper dev"`
  - `"subgraph:codegen": "pnpm --filter @prize-savings/subgraph codegen"` 等

**`.gitignore`**（根，聚合）：`node_modules/`、`.next/`、`out/`、`cache/`、`broadcast/`、`.env*`、`!.env.example`、`dist/`、`build/`、`.DS_Store`

**`.nvmrc`**：`22`；**`.editorconfig`**：统一缩进/换行/EOL。

### 5.2 contracts/（Foundry 工程）

**执行方式**：`forge init --no-git --force contracts` 生成标准骨架（foundry.toml / lib/forge-std / remappings / .gitignore），随后：
- 删除模板业务样例 `src/Counter.sol`、`test/Counter.t.sol`、`script/Counter.s.sol`、`README.md`。
- `forge install OpenZeppelin/openzeppelin-contracts@v5.0.0 --no-git`
- `forge install smartcontractkit/chainlink --no-git`（VRF/VRFCoordinatorV2/Automation 接口）

**`foundry.toml`**：`src = "src"`、`test = "test"`、`script = "script"`、`out = "out"`、`libs = ["lib"]`、`solc = "0.8.24"`、`optimizer = true`、`optimizer_runs = 200`、[fmt] 配置。

**`remappings.txt`**：
```
forge-std/=lib/forge-std/src/
@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/
@chainlink/contracts/=lib/chainlink/contracts/src/v0.8/
```

**`src/` 目录**：按第 4 节创建 7 个模块子目录 + `mocks/`，每个子目录放 `.gitkeep`（不写任何 `.sol` 实现）。目录命名对应设计文档 7.1 合约清单，作为后续编码落点。

**`test/`、`script/`**：空目录（`.gitkeep`）。

### 5.3 frontend/（Next.js + Web3）

**执行方式**：`pnpm create next-app@latest frontend --typescript --tailwind --eslint --app --src-dir --import-alias "@/*" --use-pnpm --no-turbopack --yes`

**新增依赖**：`wagmi`、`viem`、`@rainbow-me/rainbowkit`、`@tanstack/react-query`。

**改 `package.json`**：name → `@prize-savings/frontend`。

**`src/app/providers.tsx`**：`'use client'`，用 RainbowKit `getDefaultConfig` 组装 `WagmiProvider` + `RainbowKitProvider`（加载 `src/lib/config/chains.ts` 中的链）。—— 这是架构装配，非业务逻辑。

**`src/lib/config/chains.ts`**：从 `wagmi/chains` 导出 `@zksync` 忽略，占位导出目标测试链（默认 `baseSepolia`，后续按部署链调整，置于 `.env` 可覆盖）。

**`src/lib/config/wagmi.ts`**：`getDefaultConfig({ appName, projectId, chains, ssr: true })`，`projectId` 从 `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` 读。

**`src/lib/contracts/`**：空占位（后续由脚本从 `abi/` 生成 viem 类型；本阶段仅建目录）。

**`src/components/`、`src/hooks/`**：空占位（`.gitkeep`）。

**`.env.example`**：`NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=`、`NEXT_PUBLIC_CHAIN_ID=`、`NEXT_PUBLIC_RPC_URL=`（空值模板）。

> 保留 create-next-app 默认首页/布局模板作为"可运行壳"；不动模板页面内容（非业务代码追加）。

### 5.4 subgraph/（The Graph）

**`package.json`**：name `@prize-savings/subgraph`；deps `@graphprotocol/graph-cli`、`@graphprotocol/graph-ts`；devDeps `typescript`、`@types/node`；scripts `codegen` / `build` / `deploy`。

**`tsconfig.json`**：moduleResolution node、target es2020、types `["node"]`。

**`subgraph.yaml`**：`specVersion: 1.0.0`，`schema.file` 指向 `schema.graphql`，`dataSources: []`（空，占位）。

**`schema.graphql` / `src/` / `abis/`**：占位（`.gitkeep`），不写实体与映射逻辑。

### 5.5 keeper/（机器人）

**`package.json`**：name `@prize-savings/keeper`；deps `viem`、`dotenv`；devDeps `typescript`、`tsx`、`@types/node`；scripts `dev: tsx watch src/index.ts`、`build: tsc`、`start: node dist/index.js`。

**`tsconfig.json`**：target es2022、module NodeNext、strict、outDir `dist`。

**`src/index.ts`**：`async function main() {}` + 仅 `main()` 调用的 no-op 入口（不含清算/开奖逻辑）。

**`.env.example`**：`RPC_URL=`、`PRIVATE_KEY=`（空值模板）。

### 5.6 packages/contracts/（共享 SDK）

**`package.json`**：name `@prize-savings/contracts`；`private`、`main`/`types` 指向 `dist`；devDep `typescript`；`build: tsc`。

**`tsconfig.json`**：同 keeper 风格（NodeNext + declaration）。

**`src/index.ts`**：仅 `export {}` 占位（后续 re-export ABI/地址/viem 封装）。

---

## 6. 依赖与版本清单

| 层 | 依赖 | 版本 |
|----|------|------|
| 合约 | forge-std | latest（forge init 自带） |
| 合约 | openzeppelin-contracts | v5.0.0 |
| 合约 | chainlink（VRF/Automation） | latest master |
| 前端 | next / react / react-dom | create-next-app@latest（Next 15） |
| 前端 | wagmi + viem + rainbowkit | v2 |
| 前端 | @tanstack/react-query | v5 |
| subgraph | @graphprotocol/graph-cli + graph-ts | latest |
| keeper | viem + dotenv + tsx | latest |

---

## 7. 实施步骤（执行顺序）

1. 根目录：写 `pnpm-workspace.yaml`、`package.json`、`.gitignore`、`.nvmrc`、`.editorconfig`；`git init`。
2. contracts：`forge init --no-git --force contracts` → 清理 Counter 样例与 README → `forge install` openzeppelin + chainlink → 调整 `foundry.toml`/`remappings.txt` → 建 `src/*` 模块子目录 + `test/` + `script/` 占位。
3. frontend：`pnpm create next-app@latest ...` → 改名 `@prize-savings/frontend` → 装 wagmi/viem/rainbowkit/react-query → 加 providers/chains/wagmi/config 目录与 `.env.example`。
4. subgraph / keeper / packages/contracts：手写 `package.json` + `tsconfig.json` + 占位文件（见 5.4–5.6）。
5. 根 `pnpm install`（安装 workspace 依赖 + 前端新增依赖）。
6. 运行第 8 节验证命令，确认工程可构建/可运行壳。

---

## 8. Verification（验证步骤）

- `pnpm install` 无报错，锁文件 `pnpm-lock.yaml` 生成。
- `pnpm --filter @prize-savings/frontend build`：Next 模板可构建通过。
- `pnpm --filter @prize-savings/keeper build`：tsc 编译通过（no-op 入口）。
- `pnpm --filter @prize-savings/contracts build`：tsc 编译通过。
- `pnpm --filter @prize-savings/subgraph codegen`：graph-cli 正常解析空 subgraph.yaml（或确认 CLI 已安装可用）。
- `forge build --root contracts`：工程识别配置、依赖 remapping 正确（空 src 编译无合约，属预期）。
- `forge --version` / `anvil --version` 可用。

---

## 9. 明确不做（Out of Scope）

- 不实现任何 Solidity 合约逻辑（TWAB/PrizeVault/PrizePool/清算/开奖）。
- 不写前端业务页面/表单/查询 hook/存款赎回交互。
- 不写 subgraph schema 实体与映射、keeper 清算与开奖机器人逻辑、SDK 合约封装。
- 不部署、不配置真实 Chainlink 订阅、不做 git commit（除非用户后续要求）。