# 储蓄抽奖应用 前端 MVP 实现计划

## 1. Summary（目标）

依据设计文档 [prize-savings-lottery-design.md](file:///Users/mac/work/2026/web3/prize-savings/docs/prd/prize-savings-lottery-design.md) 第 5 节（产品设计，多页面）与第 9 节（前端设计），在已完成的**合约 MVP** 之上实现**前端 MVP**：把「存款 → 查看奖池 → 领取奖金 → 赎回本金」的完整交互闭环落地到一个可运行的 Next.js 应用。

交付物（本次范围）：
1. 共享 SDK `@prize-savings/contracts` 落地（ABI + 部署地址），供 frontend 消费。
2. 前端 5 个页面路由 + 导航 + RainbowKit 钱包连接。
3. 存款/赎回/领取的写交互与「余额/TWAB/中奖概率/奖池/开奖历史」读展示。

**已确认的三项关键决策（来自用户）**：
1. **目标链 = 本地 anvil**（foundry chain id `31337`）。
2. **ABI/地址走共享 SDK** `@prize-savings/contracts`（符合项目 SSOT 规则，后续 keeper/subgraph 复用）。
3. **页面形态 = 多页面路由**（按 PRD 5.1：Landing / Vault / Prize Pool / Dashboard / Draw 详情）。

---

## 2. Current State（现状）

### 2.1 合约侧（已完成，只读依赖）
- 核心合约已实现且通过编译，ABI 已生成在 `contracts/out/**/*.json`（`PrizeVault.sol/PrizeVault.json`、`PrizePool.sol/PrizePool.json`、`ITwabController.sol/ITwabController.json`、`LiquidationPair.sol/LiquidationPair.json`、`IERC20.sol/IERC20.json`）。
- 与前端交互的关键接口（已核实）：
  - **PrizeVault**（ERC-4626 + TWAB）：`deposit(assets, receiver)` / `mint` / `withdraw(assets, receiver, owner)` / `redeem`；读 `totalAssets()`、`totalSupply()`、`liquidatableBalanceOf()`、`balanceOf(user)`、`maxWithdraw(owner)`、`maxRedeem(owner)`、`asset()`、`decimals()`。份额与资产 1:1（`decimals()==6`，同 USDC）。
  - **PrizePool**：`awardDraw(randomNumber)`（仅 drawManager，keeper 职责）、`claimPrize(winner, tier, drawId)`、`isWinner` / `getClaimableAmount`、`prizeCount(tier)` / `tierFraction(tier)` / `TIER_COUNT`(=3)、`nextDrawStart()` / `drawStart(id)` / `drawEnd(id)`、`prizeToken()`；事件 `DrawAwarded(drawId, winningRandomNumber, drawAmount)`、`PrizeClaimed(drawId, tier, winner, amount)`。
  - **TwabController（接口）**：`getTwabBetween(user, start, end)`、`getAverageTotalSupplyBetween(start, end)`、`balanceOf(user)`、`totalSupply()`。
  - **奖金分级（硬编码 3 档）**：tier0 Grand×1(60%)、tier1 secondary×4(25%)、tier2 canary×100(15%)；`FRACTION_SCALE=1e18`。
- 部署脚本 `contracts/script/Deploy.s.sol` **只 console.log 地址，不落 JSON**；keeper（`awardDraw`/清算）仍为空壳 `no-op`（`keeper/src/index.ts`）。→ 前端 MVP 不负责开奖/清算。

### 2.2 前端侧（脚手架壳）
- `frontend/` 为 create-next-app 生成的干净壳 + Web3 装配：
  - `src/app/layout.tsx` 使用 Next 16 的全局类型 `LayoutProps<"/">`（见 §3.4）。
  - `src/app/providers.tsx` 已装配 `WagmiProvider + QueryClientProvider + RainbowKitProvider`（wagmi v2 + RainbowKit v2 + react-query v5）。
  - `src/lib/config/chains.ts` 当前硬编码 `baseSepolia`（需改为 anvil）。
  - `src/lib/config/wagmi.ts` 用 `getDefaultConfig({ appName, projectId, chains, ssr: true })`。
  - `src/lib/contracts/`（空 `.gitkeep`）、`src/hooks/`（空）、`src/components/`（空）均待实现。
  - `package.json` 依赖已齐（wagmi/viem/rainbowkit/react-query），**尚未声明 `@prize-savings/contracts`**。
  - **无 `.env.example`**（脚手架计划里要求过但未落地）。
- `frontend/tsconfig.json`：`strict: true`、`moduleResolution: bundler`、`resolveJsonModule: true`、路径别名 `@/* → ./src/*`；`next.config.ts` 为空配置。

### 2.3 共享 SDK（空占位）
- `packages/contracts/` 仅 `src/index.ts`（`export {}`）、`package.json`（`main/test → dist`、`build: tsc`）、`tsconfig.json`（NodeNext + declaration）。
- 未被任何模块声明依赖。

---

## 3. 决策与假设（Decisions & Assumptions）

| 决策点 | 结论 |
|--------|------|
| 目标链 | 本地 anvil（`foundry` chain，chainId `31337`，RPC `http://127.0.0.1:8545`） |
| ABI/地址来源 | 共享 SDK `@prize-savings/contracts`：ABI 以 `.ts` 常量数组落库，地址以 `deployments.ts` + 环境变量覆盖 |
| SDK 消费方式 | `next.config.ts` 开 `transpilePackages: ["@prize-savings/contracts"]`，SDK `main/types` 指向 `src/index.ts`（源码直编，无需先 build、热更新） |
| 页面形态 | 多页面：`/`、`/vault`、`/prizes`、`/account`、`/draw/[drawId]` |
| 开奖/清算 | **不在前端**（keeper 职责）；前端只读开奖状态、展示历史、`claimPrize` 领奖 |
| 中奖历史来源 | MVP 用链上 `getLogs` 拉取 `DrawAwarded`/`PrizeClaimed` 事件（anvil 支持，**不依赖 subgraph**，subgraph 属后续 M1） |
| 收益/APY 展示 | Mock 收益金库无真实时间 APY（收益靠 keeper `mockHarvest`），前端展示「可清算收益 `liquidatableBalanceOf()`」与「奖池余额」，不展示虚假 APY |
| 资产/币种 | 单一资产 USDC（6 decimals）+ 单一奖币 PRIZE（18 decimals）+ 份额 pvUSDC（6 decimals） |
| 钱包连接 anvil | RainbowKit 默认 injected 连接器；用户在 MetaMask 中添加本地 anvil 网络（`127.0.0.1:8545` / chainId 31337）连接测试账户 |
| 领取方式 | M0 主动 `claimPrize`（设计文档 3.2「开奖后主动 claim」），不做 Claimer 自动派奖 |

---

## 4. 目标文件结构（Target Tree）

```
packages/contracts/
├── package.json                 # 改：main/types 指向 src；无运行时依赖
├── tsconfig.json                # 改：需能 typecheck src（.ts 常量 ABI，无需 JSON 导入）
└── src/
    ├── abis/
    │   ├── PrizeVault.ts        # export const prizeVaultAbi = [...] as const
    │   ├── PrizePool.ts
    │   ├── TwabController.ts    # 接口 ABI（getTwabBetween / getAverageTotalSupplyBetween / balanceOf / totalSupply）
    │   ├── LiquidationPair.ts
    │   └── Erc20.ts             # 最小 ERC20 ABI（approve/allowance/balanceOf/decimals/symbol）
    ├── deployments.ts           # Deployment 类型 + DEPLOYMENTS map + getDeployment(chainId)
    └── index.ts                 # 聚合 re-export

frontend/
├── .env.example                 # 新增：NEXT_PUBLIC_* 空值模板
├── next.config.ts               # 改：transpilePackages
└── src/
    ├── app/
    │   ├── layout.tsx           # 改：Providers 外包 AppShell（含导航）
    │   ├── globals.css          # 改：少量设计 token/基础样式（可选）
    │   ├── page.tsx             # 改：Landing（原 create-next-app 模板替换）
    │   ├── vault/page.tsx       # 新增：存款/赎回
    │   ├── prizes/page.tsx      # 新增：奖池 & 开奖历史
    │   ├── account/page.tsx     # 新增：我的账户（余额/TWAB/概率/领奖）
    │   └── draw/[drawId]/page.tsx  # 新增：单期开奖详情
    ├── components/
    │   ├── app-shell.tsx        # 新增：Header(导航+ConnectButton) + <main>
    │   ├── header.tsx           # 新增：顶部导航（可并入 app-shell）
    │   ├── connect-button.tsx   # 新增：RainbowKit ConnectButton 封装（可选）
    │   ├── deposit-form.tsx     # 新增
    │   ├── withdraw-form.tsx    # 新增
    │   ├── prize-pool-card.tsx  # 新增：奖池总额 + 倒计时 + 分级结构
    │   ├── prize-tiers.tsx      # 新增：3 档分级展示
    │   ├── draw-list.tsx        # 新增：历史开奖列表
    │   ├── winners-list.tsx     # 新增：某期中奖者
    │   ├── account-summary.tsx  # 新增：我的存款/TWAB/概率
    │   ├── claim-prizes.tsx     # 新增：可领取奖金列表 + claim 按钮
    │   └── ui/…                 # 少量基础 UI（卡片/按钮/金额格式化），按需
    ├── hooks/
    │   ├── use-deployment.ts    # 新增：解析当前链的合约地址
    │   ├── use-prize-vault.ts   # 新增：金库读（totalAssets/supply/liquidatable/余额）
    │   ├── use-prize-pool.ts    # 新增：奖池读（奖币余额/倒计时/分级）
    │   ├── use-twab.ts          # 新增：用户 TWAB + 总 TWAB + 中奖概率
    │   ├── use-draws.ts         # 新增：getLogs 拉 DrawAwarded/PrizeClaimed
    │   ├── use-tokens.ts        # 新增：USDC/奖币 decimals+余额+allowance
    │   ├── use-deposit.ts       # 新增：approve + deposit 写封装
    │   ├── use-withdraw.ts      # 新增：withdraw 写封装
    │   └── use-claim.ts         # 新增：claimPrize 写封装
    └── lib/
        ├── config/
        │   ├── chains.ts        # 改：改为 anvil（foundry）
        │   └── wagmi.ts         # 改：projectId 占位不变，chains 引用更新
        ├── contracts.ts         # 新增：SDK 之上的合约地址/ABI 装配（getContract 工厂）
        └── format.ts            # 新增：formatUnits / shortAddress / 倒计时 等纯函数
```

---

## 5. Proposed Changes（具体改动）

### 5.1 共享 SDK `packages/contracts/`

**目标**：成为 ABI + 地址的单一事实源（SSOT），frontend 直接消费；keeper/subgraph 后续复用。

#### `src/abis/*.ts`
- 每个文件 `export const xxxAbi = [ ... ] as const`，内容取自对应 Foundry 产物 JSON 的 `"abi"` 数组：
  - `PrizeVault.ts` ← `contracts/out/PrizeVault.sol/PrizeVault.json`（含 ERC-4626/ERC20 继承函数，全量）。
  - `PrizePool.ts` ← `contracts/out/PrizePool.sol/PrizePool.json`。
  - `TwabController.ts` ← `contracts/out/ITwabController.sol/ITwabController.json`（只需读接口）。
  - `LiquidationPair.ts` ← `contracts/out/LiquidationPair.sol/LiquidationPair.json`（预留，MVP 前端不直接调用）。
  - `Erc20.ts`：手写**最小 ERC20 ABI**——`approve(address,uint256)`、`allowance(address,address)`、`balanceOf(address)`、`decimals()`、`symbol()`（用于 USDC 授权 / 奖币余额）。
- 用 `.ts` 常量而非 `.json`，规避 NodeNext/resolveJsonModule/import-attribute 的兼容坑，且对 frontend（bundler 解析）零摩擦、类型安全。

#### `src/deployments.ts`
```ts
export interface Deployment {
  chainId: number
  usdc: `0x${string}`
  prizeToken: `0x${string}`
  yieldVault: `0x${string}`
  twabController: `0x${string}`
  prizePool: `0x${string}`
  prizeVault: `0x${string}`
  liquidationPair: `0x${string}`
}

export const DEPLOYMENTS: Record<number, Deployment> = {
  31337: { /* anvil：由部署后回填 */ }
}

export function getDeployment(chainId: number): Deployment
```
- `getDeployment(chainId)`：优先读 `process.env.NEXT_PUBLIC_*`（`PRIZE_VAULT`/`PRIZE_POOL`/`TWAB_CONTROLLER`/`LIQUIDATION_PAIR`/`USDC`/`PRIZE_TOKEN`/`YIELD_VAULT`）覆盖，缺省回落到 `DEPLOYMENTS[chainId]`；未知链抛错提示。
- 地址用 `0x${string}` 模板字面量类型，**不引入 viem 依赖**（SDK 保持零运行时依赖）。

#### `src/index.ts`
- `export { prizeVaultAbi, prizePoolAbi, twabControllerAbi, liquidationPairAbi, erc20Abi } from "./abis/…"`
- `export { type Deployment, DEPLOYMENTS, getDeployment } from "./deployments"`

#### `package.json` + `tsconfig.json`
- `package.json`：`"main": "src/index.ts"`、`"types": "src/index.ts"`（供 Next `transpilePackages` 源码直编）；**不加任何运行时依赖**；保留 `build: tsc` 作为类型自检脚本。
- `tsconfig.json`：保持 NodeNext + declaration，确保 `src/**/*.ts` 通过 (`tsc --noEmit` 自检)；因全部是 `.ts` 常量、无 JSON 导入，无需改 `resolveJsonModule`。

> 备选（若 `transpilePackages` 在 Next 16 有坑）：退回 `main/types → dist`，先 `pnpm --filter @prize-savings/contracts build` 再跑前端 dev。

---

### 5.2 前端配置层

#### `frontend/next.config.ts`
- 改为 `const nextConfig: NextConfig = { transpilePackages: ["@prize-savings/contracts"] }`。

#### `frontend/src/lib/config/chains.ts`
- `import { foundry } from "wagmi/chains"`，`export const chains = [foundry] as const`。
- 保留注释：后续可用 `NEXT_PUBLIC_CHAIN_ID` 扩展其它链。

#### `frontend/src/lib/config/wagmi.ts`
- 逻辑不变（`getDefaultConfig` 引用更新后的 `chains`）；`foundry` 默认 RPC 即 `http://127.0.0.1:8545`。

#### `frontend/package.json`
- 新增依赖 `"@prize-savings/contracts": "workspace:*"`。

#### `frontend/.env.example`（新增，空值模板）
```
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=
NEXT_PUBLIC_CHAIN_ID=31337
NEXT_PUBLIC_RPC_URL=http://127.0.0.1:8545
NEXT_PUBLIC_USDC=
NEXT_PUBLIC_PRIZE_TOKEN=
NEXT_PUBLIC_YIELD_VAULT=
NEXT_PUBLIC_TWAB_CONTROLLER=
NEXT_PUBLIC_PRIZE_POOL=
NEXT_PUBLIC_PRIZE_VAULT=
NEXT_PUBLIC_LIQUIDATION_PAIR=
```

---

### 5.3 前端 lib（纯函数与装配）

#### `src/lib/format.ts`
- `formatToken(value: bigint, decimals: number, opts?)`（基于 viem `formatUnits`）、`shortAddress`、`formatCountdown(seconds)`、`formatPercent` 等纯函数，供各组件复用。

#### `src/lib/contracts.ts`
- re-export SDK 的 ABI 与 `getDeployment`。
- 提供类型化 `getContract` 工厂（基于 `getDeployment(chainId)` + viem `getContract`），但**主要读写在 hooks 内用 wagmi `useReadContract/useWriteContract` 完成**，本文件提供地址装配与类型保障。

---

### 5.4 前端 hooks（`src/hooks/`，均 client）

约定：所有读聚合用 wagmi `useReadContracts`（一次 RPC 批量读取）；写用 `useWriteContract` + `waitForTransactionReceipt`；链/账户来自 `useAccount()`。

- `use-deployment.ts`：`const { data: chainId } = useChainId()` → `getDeployment(chainId)`；未连接或未知链返回 `undefined`。
- `use-prize-vault.ts`：`useReadContracts` 批量读 `PrizeVault`：`totalAssets`、`totalSupply`、`liquidatableBalanceOf`、`balanceOf(user)`、`maxWithdraw(user)`、`maxRedeem(user)`、`asset`、`decimals`。
- `use-tokens.ts`：`useReadContracts` 读 USDC/奖币 `decimals`、`balanceOf(user)`、`allowance(user, vault)`。
- `use-prize-pool.ts`：读 `prizeToken`、`prizeToken.balanceOf(pool)`、`nextDrawStart`、`TIER_COUNT` + 各档 `prizeCount(tier)`/`tierFraction(tier)`；用 `useBlockNumber + useInterval`（或 `useBlockTime`）驱动倒计时刷新。
- `use-twab.ts`：读当前开奖周期 `[drawStart, drawEnd]`（由 `nextDrawStart - drawPeriodSeconds` 反推当前周期），`twabController.getTwabBetween(user, start, end)`、`getAverageTotalSupplyBetween(start, end)`；概率 `= userTwab / totalTwab`（分母为 0 时返回 0）。
- `use-draws.ts`：`publicClient.getLogs` 拉 `DrawAwarded`（与 `PrizeClaimed`）事件，倒序组装「开奖历史 + 每期 drawAmount + 中奖者」。用 `useQuery` + `blockNumber` 失效刷新；做最小分页（取最近 N 期，如 20）。
- `use-deposit.ts`：两步流程——先 `ERC20.approve(vault, amount)`（若 `allowance < amount`），再 `PrizeVault.deposit(assets, receiver)`；暴露 `deposit(amount)` 与 `isPending/isConfirming/hash/error`。
- `use-withdraw.ts`：`PrizeVault.withdraw(assets, receiver, owner)`（receiver/owner 默认当前账户）；暴露 `withdraw(amount)`。
- `use-claim.ts`：`PrizePool.claimPrize(winner, tier, drawId)`；暴露 `claim(tier, drawId)`；配合 `isWinner/getClaimableAmount` 只对可领取项启用。

---

### 5.5 前端组件与页面

**共享壳**
- `src/components/app-shell.tsx`（client）：`<Header/>` + `<main className="mx-auto max-w-6xl px-4 py-6">{children}</main>`。
- `src/components/header.tsx`（client）：站点名 + 导航链接（`Link`）+ RainbowKit `<ConnectButton/>`。
- `src/components/connect-button.tsx`：RainbowKit `ConnectButton` 的样式封装（可选，直接在 header 用也可以）。

**业务组件**
- `deposit-form.tsx`：金额输入（USDC，6 位小数）→ 展示 share 预估（1:1）→ `useDeposit` 触发 approve+deposit；含交易状态（批准中/存款中/已确认）与错误提示。
- `withdraw-form.tsx`：金额输入 → `maxWithdraw` 上限（MAX 按钮）→ `useWithdraw`。
- `prize-pool-card.tsx`：奖池总额（奖币，18 位）、下一期开奖倒计时（`formatCountdown`）、`liquidatableBalanceOf` 待清算收益。
- `prize-tiers.tsx`：3 档（Grand/次级/Canary）数量、占比、单份金额（`drawAmount × tierFraction / prizeCount`）。
- `account-summary.tsx`：我的存款（share/底层 USDC）、当前 TWAB、中奖概率（百分比）。
- `claim-prizes.tsx`：列出各期 × 各档 `getClaimableAmount > 0` 的可领金额，`useClaim` 触发；已领取项标记。
- `draw-list.tsx`：历史开奖列表（drawId、drawAmount、中奖次数），进入 `/draw/[drawId]`。
- `winners-list.tsx`：某期中奖者（由 `PrizeClaimed` 事件聚合）。

**页面（`src/app/`）**
- `/`（`page.tsx`，替换模板）：Landing —— 价值主张（存钱+抽奖+零损失）、`prize-pool-card` 速览、CTA 跳 `/vault`。client。
- `/vault`（`vault/page.tsx`）：`deposit-form` + `withdraw-form` + `account-summary`（我的余额/概率）。
- `/prizes`（`prizes/page.tsx`）：`prize-tiers` + `draw-list`。
- `/account`（`account/page.tsx`）：`account-summary` + `claim-prizes` + 历史开奖入口。
- `/draw/[drawId]`（`draw/[drawId]/page.tsx`）：单期详情 —— 随机数、drawAmount、分级奖金、`winners-list`；`params` 按 Next 16 约定 `PageProps<"/draw/[drawId]">` + `await params` 取 `drawId`。

---

## 6. 实施步骤（执行顺序）

1. **SDK**：写 `packages/contracts/src/abis/*.ts`（从 `contracts/out` 拷 ABI 数组）→ `deployments.ts` → `index.ts`；改 `package.json`/`tsconfig.json`。
2. **前端依赖与配置**：`frontend/package.json` 加 `workspace:*`；写 `.env.example`；改 `next.config.ts`（transpilePackages）、`chains.ts`、`wagmi.ts`。
3. **lib**：写 `format.ts`、`contracts.ts`。
4. **hooks**：`use-deployment` → `use-tokens`/`use-prize-vault`/`use-prize-pool` → `use-twab` → `use-draws` → 写封装 `use-deposit`/`use-withdraw`/`use-claim`。
5. **共享壳与业务组件**：app-shell/header → 表单与展示组件 → 金额格式化接入。
6. **页面**：5 个路由页，替换原 `app/page.tsx` 模板。
7. **根 `pnpm install`**（链接 workspace 依赖）→ 跑 §7 验证。

---

## 7. Verification（验证步骤）

环境准备（一次性）：
```bash
pnpm install                                  # 链接 @prize-savings/contracts
pnpm chain                                    # 启动 anvil（127.0.0.1:8545）
# 另开终端部署合约（Deploy.s.sol），记录打印的 8 个地址
DEPLOYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
forge script contracts/script/Deploy.s.sol --root contracts \
  --rpc-url http://127.0.0.1:8545 --broadcast
# 将地址回填到 packages/contracts/src/deployments.ts 的 31337 项（或写入 frontend/.env.local）
```

构建/类型：
```bash
pnpm --filter @prize-savings/contracts build   # SDK 类型自检通过
pnpm frontend:build                            # Next 16 build + TS strict 通过
```

手工联调（`pnpm frontend:dev` + MetaMask 连 anvil）：
1. 连接钱包（导入 anvil 私钥账户）→ 顶部显示地址/网络。
2. `/vault`：先 `approve` 后 `deposit` 一笔 USDC → 我的份额/TWAB 更新；`withdraw` 可全额赎回本金。
3. 用 `cast` 模拟 keeper 注入随机数开奖（MVP 前端不负责）：
   ```bash
   cast send <PRIZE_POOL> "awardDraw(uint256)" <randomNumber> \
     --rpc-url http://127.0.0.1:8545 --private-key <keeperPk>
   ```
4. `/account`、`/draw/[drawId]`：展示开奖历史与本期中奖者；若当前账户命中，`claimPrize` 可领取、已领取状态正确。
5. `/prizes`：奖池总额、倒计时、3 档结构正确渲染。

预期结果：
- 5 个路由均可访问、导航正常、金额小数位正确（USDC/份额 6 位、奖币 18 位）。
- 存款/赎回/领取三条写路径走通，交易状态与错误（如 allowance 不足、本金不足）提示正确。
- `getLogs` 拉取的开奖/中奖历史与链上一致。

---

## 8. 明确不做（Out of Scope）

- 不实现 keeper 的开奖/清算逻辑（`awardDraw`、`LiquidationPair.swapExactAmountOut` 均不在前端触发）。
- 不做 subgraph 索引（中奖历史 MVP 用链上 `getLogs`）。
- 不做 Claimer 自动派奖、TWAB 委托、多资产/多 vault、PFDA 去中心化开奖（对应 PRD P2/M2）。
- 不改动任何 Solidity 合约（前端 MVP 仅消费现有 ABI/地址；如需回填地址不改合约）。
- 不新建文档（README/ARCHITECTURE），遵循项目「不主动建文档」规则；如后续需要，按「就近原则」落 `frontend/ARCHITECTURE.md`。

---

## 9. Next 16 注意事项（写给执行者）

- 本仓库 Next 为 `16.3.6`，与旧版训练数据不同；动手前先读 `frontend/node_modules/next/dist/docs/01-app/**` 相关指引（AGENTS.md 已提示）。
- `params`/`searchParams` 在页面/布局中为 **Promise**，动态路由用全局类型 `PageProps<'/draw/[drawId]'>` 并 `await props.params`；根布局沿用现有 `LayoutProps<"/">`。
- 交互页面均需 `'use client'`（使用 wagmi hooks）；根布局保持 Server Component，仅在其中渲染 client 的 `AppShell`。
- `transpilePackages` 配置字段位于 `next.config.ts` 顶层（Next 16 仍支持，见 `01-app/05-config/01-next-config-js/transpilePackages.md`）。