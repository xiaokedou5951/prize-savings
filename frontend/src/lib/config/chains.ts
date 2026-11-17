import { baseSepolia, foundry } from "wagmi/chains";
import type { Chain } from "wagmi/chains";

const DEFAULT_CHAIN_ID = Number(process.env.NEXT_PUBLIC_CHAIN_ID ?? "31337");

export const chains: [Chain, ...Chain[]] =
  DEFAULT_CHAIN_ID === 84532
    ? [baseSepolia, foundry]
    : [foundry, baseSepolia];
