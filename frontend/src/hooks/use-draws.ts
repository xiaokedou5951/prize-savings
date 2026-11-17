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

/**
 * 链上拉取历史开奖与中奖记录（anvil 支持 getLogs；倒序返回）。
 *
 * 注意：anvil fork（如 Base Sepolia 本地 fork）的 eth_getLogs 有区块范围上限
 * （默认 50000），fromBlock=0 会报 "exceed maximum block range"。
 * 因此取最新区块号，fromBlock = max(0, latest - 49999)，卡在范围内。
 * 本地 anvil（31337）latest 很小，等效于从 0 开始扫描。
 */
const MAX_LOG_BLOCK_RANGE = BigInt(49999);

export function useDraws() {
  const d = useDeployment();
  const publicClient = usePublicClient();
  const pool = d?.prizePool;

  return useQuery({
    queryKey: ["draws", pool],
    queryFn: async () => {
      if (!publicClient || !pool) return [] as Draw[];
      const latest = await publicClient.getBlockNumber();
      const fromBlock = latest > MAX_LOG_BLOCK_RANGE ? latest - MAX_LOG_BLOCK_RANGE : BigInt(0);
      const [awards, claims] = await Promise.all([
        publicClient.getContractEvents({
          address: pool,
          abi: prizePoolAbi,
          eventName: "DrawAwarded",
          fromBlock,
          strict: true,
        }),
        publicClient.getContractEvents({
          address: pool,
          abi: prizePoolAbi,
          eventName: "PrizeClaimed",
          fromBlock,
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