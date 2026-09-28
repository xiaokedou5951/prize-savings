import { baseSepolia } from "wagmi/chains";

/**
 * 目标链配置（脚手架占位）。
 * MVP 默认 Base Sepolia 测试网；后续按部署链调整，可结合 NEXT_PUBLIC_CHAIN_ID 覆盖。
 */
export const chains = [baseSepolia] as const;