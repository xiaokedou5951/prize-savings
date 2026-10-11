# frontend 模块架构

Prize Savings 的 Web 端：Next.js 16（App Router, Turbopack）+ React 19 + TypeScript strict + Tailwind v4，Web3 栈为 wagmi v2 / viem v2 / RainbowKit v2 / React Query v5。系统级数据流见 [../docs/architecture/overview.md](../docs/architecture/overview.md)，本篇只讲前端内部结构与本模块约束。

## 目录结构

```text
src/
├── app/                  # App Router 页面（全部为 client component）
│   ├── page.tsx          #   Landing：价值主张 + 奖池卡片
│   ├── vault/            #   存款 / 赎回 / 账户摘要
│   ├── prizes/           #   奖池分级 + 开奖历史
│   ├── account/          #   账户摘要 + 可领奖金
│   └── draw/[drawId]/    #   单期开奖详情（useParams 取参）
├── components/           # 展示组件 + 两个交易表单
├── hooks/                # 链上读写（见下表）
└── lib/
    ├── config/           #   chains.ts（foundry 单链）、wagmi.ts（RainbowKit 组装）
    ├── constants.ts      #   ZERO_ADDRESS / TIER_NAMES / TIER_COUNT
    └── format.ts         #   formatToken / shortAddress / formatCountdown / formatPercent
```

## 数据与状态

Provider 装配在 [providers.tsx](src/app/providers.tsx)：`WagmiProvider → QueryClientProvider → RainbowKitProvider`。

| Hook | 职责 | 数据来源 |
|------|------|----------|
| `useDeployment` | 按当前 chainId 解析地址（env 覆盖 → SSOT） | `@prize-savings/contracts` |
| `useTokens` | USDC/奖币 decimals、symbol、余额、授权 | `useReadContracts` multicall |
| `usePrizeVault` | totalAssets/totalSupply/可清算额/我的份额 | multicall + 单读 |
| `usePrizePool` | 下期开奖时间、奖池余额、3 档名额/占比/预估单份 | 一个 9 项 multicall |
| `useTwab` | 当前周期用户 TWAB、总 TWAB、中奖概率 | 配置读 + TWAB 读两段式 |
| `useDraws` | 历史开奖与领取记录 | `getContractEvents`（5s 轮询） |
| `useDeposit` / `useWithdraw` / `useClaim` | 写交易状态机 | `writeContractAsync` + 回执等待 |

读路径默认 `allowFailure: false` 直接拿解码数组；写路径在 hook 内维护显式状态机（approving → waiting → success/error），组件只渲染状态文案。

## 本模块关键约束（改动必读）

- **Next.js 16 有破坏性变更**：写代码前先翻 `node_modules/next/dist/docs/`，并遵循 [AGENTS.md](AGENTS.md) 的弃用提示；`params`/`searchParams` 是 Promise。
- **BigInt**：Next 的类型检查目标低于 ES2020，代码内一律用 `BigInt(0)` 而非 `0n` 字面量。
- **ABI 不准手写**：只能从 `@prize-savings/contracts` 导入；workspace 包以 TS 源码直编（`main/types → src/index.ts`），靠 `next.config.ts` 的 `transpilePackages` 转译。
- **历史数据直读链上事件**：subgraph 就位前用 viem `getContractEvents`（不是已删 `abi/eventName` 参数的 `getLogs`），仅适用 anvil；subgraph 落地后需替换 `useDraws`。
- 所有地址占位为零地址时查询 hook 必须 `enabled: false`，避免对零合约发请求。

## 环境变量与命令

见 [.env.example](.env.example)（`NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID`、链配置、7 个地址覆盖）。

```bash
pnpm frontend:dev       # 开发
pnpm frontend:build     # 生产构建（含严格类型检查）
```

## 与系统的衔接点

- 消费的合约接口与事件契约：[../docs/architecture/module-contracts.md](../docs/architecture/module-contracts.md)。
- 本地链与地址回填：[../docs/architecture/deployment.md](../docs/architecture/deployment.md)。
