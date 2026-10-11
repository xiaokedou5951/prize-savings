"use client";

import { useQuery } from "@tanstack/react-query";
import { usePublicClient } from "wagmi";
import { prizePoolAbi } from "@prize-savings/contracts";
import { useDeployment } from "./use-deployment";

export interface DrawClaim {
  winner: `0x${string}`;
  tier: number;
  amount: bigint;
}

export interface Draw {
  drawId: number;
  winningRandomNumber: bigint;
  drawAmount: bigint;
  claims: DrawClaim[];
}

/** 链上拉取历史开奖与中奖记录（anvil 支持 getLogs；倒序返回）。 */
export function useDraws() {
  const d = useDeployment();
  const publicClient = usePublicClient();
  const pool = d?.prizePool;

  return useQuery({
    queryKey: ["draws", pool],
    queryFn: async () => {
      if (!publicClient || !pool) return [] as Draw[];
      const [awards, claims] = await Promise.all([
        publicClient.getContractEvents({
          address: pool,
          abi: prizePoolAbi,
          eventName: "DrawAwarded",
          fromBlock: BigInt(0),
          strict: true,
        }),
        publicClient.getContractEvents({
          address: pool,
          abi: prizePoolAbi,
          eventName: "PrizeClaimed",
          fromBlock: BigInt(0),
          strict: true,
        }),
      ]);

      const draws = new Map<number, Draw>();
      for (const log of awards) {
        const { drawId, winningRandomNumber, drawAmount } = log.args;
        draws.set(drawId, { drawId, winningRandomNumber, drawAmount, claims: [] });
      }
      for (const log of claims) {
        const { drawId, tier, winner, amount } = log.args;
        draws.get(drawId)?.claims.push({ winner, tier, amount });
      }
      return [...draws.values()].sort((x, y) => y.drawId - x.drawId);
    },
    enabled: !!publicClient && !!pool,
    refetchInterval: 5000,
  });
}