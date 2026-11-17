import { baseSepolia, foundry } from "wagmi/chains";
import type { Chain } from "wagmi/chains";

// fork 联调临时覆盖：baseSepolia 指向本地 anvil fork
const baseSepoliaFork = {
  ...baseSepolia,
  rpcUrls: {
    default: { http: ["http://127.0.0.1:8545"] },
    public: { http: ["http://127.0.0.1:8545"] },
  },
} as const;

const DEFAULT_CHAIN_ID = Number(process.env.NEXT_PUBLIC_CHAIN_ID ?? "31337");

export const chains: [Chain, ...Chain[]] =
  DEFAULT_CHAIN_ID === 84532
    ? [baseSepoliaFork, foundry]
    : [foundry, baseSepolia];