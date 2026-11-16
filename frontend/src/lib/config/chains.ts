import { baseSepolia, foundry } from "wagmi/chains";
import type { Chain } from "wagmi/chains";

/**
 * 目标链配置：本地 anvil（31337，默认）与 Base Sepolia（84532）双链。
 * NEXT_PUBLIC_CHAIN_ID 选择默认链（排在数组首位，钱包连接时优先使用）：
 *   - 31337 → 本地联调（pnpm chain + pnpm deploy:local）
 *   - 84532 → Base Sepolia 测试网（部署步骤见 docs/architecture/deployment.md）
 * 部署地址经 useDeployment() 解析：DEPLOYMENTS[84532] 未回填时相关查询自动禁用。
 */
const DEFAULT_CHAIN_ID = Number(process.env.NEXT_PUBLIC_CHAIN_ID ?? "31337");

export const chains: [Chain, ...Chain[]] =
  DEFAULT_CHAIN_ID === 84532 ? [baseSepolia, foundry] : [foundry, baseSepolia];