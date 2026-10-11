import { foundry } from "wagmi/chains";

/**
 * 目标链配置。
 * MVP 默认本地 anvil（foundry chainId 31337，RPC http://127.0.0.1:8545）。
 * 后续扩展其它链时改这里，并可结合 NEXT_PUBLIC_CHAIN_ID 动态选择。
 */
export const chains = [foundry] as const;