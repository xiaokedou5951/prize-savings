"use client";

import { useReadContracts } from "wagmi";
import { erc20Abi, prizePoolAbi } from "@prize-savings/contracts";
import { ZERO_ADDRESS } from "@/lib/constants";
import { useDeployment } from "./use-deployment";

export interface PrizeTier {
  tier: number;
  count: bigint;
  fraction: bigint;
  prizeSize: bigint;
}

export interface PrizePoolData {
  poolBalance: bigint;
  nextDrawStart: number;
  drawPeriodSeconds: number;
  tiers: PrizeTier[];
}

const FRACTION_SCALE = BigInt(10) ** BigInt(18);

/** Prize Pool 奖池余额、下一期开奖时间与 3 档分级结构（单份奖金为按当前余额的预估）。 */
export function usePrizePool(): PrizePoolData | undefined {
  const d = useDeployment();
  const pool = d?.prizePool ?? ZERO_ADDRESS;
  const prizeToken = d?.prizeToken ?? ZERO_ADDRESS;

  const { data: g } = useReadContracts({
    contracts: [
      { address: pool, abi: prizePoolAbi, functionName: "nextDrawStart" },
      { address: pool, abi: prizePoolAbi, functionName: "drawPeriodSeconds" },
      { address: prizeToken, abi: erc20Abi, functionName: "balanceOf", args: [pool] },
      { address: pool, abi: prizePoolAbi, functionName: "prizeCount", args: [0] },
      { address: pool, abi: prizePoolAbi, functionName: "tierFraction", args: [0] },
      { address: pool, abi: prizePoolAbi, functionName: "prizeCount", args: [1] },
      { address: pool, abi: prizePoolAbi, functionName: "tierFraction", args: [1] },
      { address: pool, abi: prizePoolAbi, functionName: "prizeCount", args: [2] },
      { address: pool, abi: prizePoolAbi, functionName: "tierFraction", args: [2] },
    ],
    allowFailure: false,
    query: { enabled: !!d },
  });

  if (!g) return undefined;

  const poolBalance = g[2];
  const tiers: PrizeTier[] = [0, 1, 2].map((tier) => {
    const count = g[3 + tier * 2] as bigint;
    const fraction = g[4 + tier * 2] as bigint;
    const prizeSize = count > BigInt(0) ? (poolBalance * fraction) / (count * FRACTION_SCALE) : BigInt(0);
    return { tier, count, fraction, prizeSize };
  });

  return {
    poolBalance,
    nextDrawStart: g[0],
    drawPeriodSeconds: g[1],
    tiers,
  };
}