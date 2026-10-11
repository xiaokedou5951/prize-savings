"use client";

import { useAccount, useReadContracts } from "wagmi";
import { prizePoolAbi, twabControllerAbi } from "@prize-savings/contracts";
import { ZERO_ADDRESS } from "@/lib/constants";
import { useDeployment } from "./use-deployment";

export interface TwabData {
  userTwab: bigint;
  totalTwab: bigint;
  probability: number;
  drawStart: number;
}

/**
 * 当前开奖周期的用户 TWAB、总 TWAB 与中奖概率。
 * 开奖周期起点 = nextDrawStart - drawPeriodSeconds；终点近似取当前墙钟时间（区块时间戳）。
 */
export function useTwab(): TwabData {
  const { address } = useAccount();
  const d = useDeployment();
  const pool = d?.prizePool ?? ZERO_ADDRESS;
  const twab = d?.twabController ?? ZERO_ADDRESS;
  const now = Math.floor(Date.now() / 1000);

  const { data: cfg } = useReadContracts({
    contracts: [
      { address: pool, abi: prizePoolAbi, functionName: "nextDrawStart" },
      { address: pool, abi: prizePoolAbi, functionName: "drawPeriodSeconds" },
    ],
    allowFailure: false,
    query: { enabled: !!d },
  });

  const start = cfg ? cfg[0] - cfg[1] : 0;

  const { data: t } = useReadContracts({
    contracts: [
      { address: twab, abi: twabControllerAbi, functionName: "getTwabBetween", args: [address ?? ZERO_ADDRESS, start, now] },
      { address: twab, abi: twabControllerAbi, functionName: "getAverageTotalSupplyBetween", args: [start, now] },
    ],
    allowFailure: false,
    query: { enabled: !!d && !!address && start > 0 && now > start },
  });

  const userTwab = t?.[0] ?? BigInt(0);
  const totalTwab = t?.[1] ?? BigInt(0);
  const probability = totalTwab > BigInt(0) ? Number(userTwab) / Number(totalTwab) : 0;

  return { userTwab, totalTwab, probability, drawStart: start };
}