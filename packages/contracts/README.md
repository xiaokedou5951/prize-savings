# @prize-savings/contracts

Prize Savings 合约对 TypeScript 世界的唯一出口：ABI 常量 + 部署地址 SSOT。frontend（未来还有 keeper/subgraph 工具链）只允许从本包导入合约接口，禁止在业务代码内联手写 ABI。

## 导出

```ts
import {
  prizeVaultAbi, prizePoolAbi, twabControllerAbi, liquidationPairAbi, erc20Abi,
  DEPLOYMENTS, getDeployment,
  type Deployment,
} from "@prize-savings/contracts";
```

| 导出 | 说明 |
|------|------|
| `*Abi`（[src/abis/](src/abis/)） | 从 Foundry `contracts/out/**/*.json` 提取的 ABI，以 `as const` 数组导出，供 viem/wagmi 做字面量类型推断；`erc20Abi` 为手写最小集 |
| `DEPLOYMENTS` | 按 chainId 索引的地址表，当前仅 `31337`（零地址占位，本地部署后回填） |
| `getDeployment(chainId)` | 先读 `NEXT_PUBLIC_*` 环境变量覆盖（带地址正则校验），未设置再回落 `DEPLOYMENTS`；未知链抛错 |

## 消费方式

本包**不预编译**：`main`/`types` 直接指向 `src/index.ts`，由消费方转译。

- Next.js：已在 `next.config.ts` 配置 `transpilePackages: ["@prize-savings/contracts"]`，workspace 依赖 `workspace:*`。
- Node（keeper）：用 `tsx` 运行可直接吃 TS 源码；`tsc` 消费时需 NodeNext 解析。

类型自检：`pnpm --filter @prize-savings/contracts build`（仅 `tsc --noEmit` 性质的检查，产物 `dist/` 不作为消费入口）。

## ABI 再生成

合约改接口后，在仓库根执行一条命令（自动先编译再提取）：

```bash
pnpm contracts:abis      # forge build --root contracts && node scripts/gen-abis.mjs
```

生成器 [scripts/gen-abis.mjs](../../scripts/gen-abis.mjs) 从 `contracts/out/` 读取 4 个产物（PrizeVault / PrizePool / ITwabController / LiquidationPair），覆盖写出 [src/abis/](src/abis/) 中同名导出（保持 `as const`）。`erc20Abi` 是手写最小集，不生成。

生成物为确定性输出：接口未变时重跑无 diff，可据此检查 ABI 是否漂移。接口/事件变化后还须同步 [../../docs/architecture/module-contracts.md](../../docs/architecture/module-contracts.md) 的事件/接口表——跨模块接口改动不同步该文档视为不完整提交。

## 地址回填

本地部署后（部署流程见 [../../docs/architecture/deployment.md](../../docs/architecture/deployment.md)）：把 `Deploy.s.sol` stdout 的地址写入 `DEPLOYMENTS[31337]`，或在 `frontend/.env.local` 用 `NEXT_PUBLIC_*` 覆盖。
