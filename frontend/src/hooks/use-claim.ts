"use client";

import { useState } from "react";
import { useAccount, usePublicClient, useWriteContract } from "wagmi";
import { prizePoolAbi } from "@prize-savings/contracts";
import { useDeployment } from "./use-deployment";

export type ClaimStatus = "idle" | "waiting" | "success" | "error";

/** 领取封装：claimPrize(winner, tier, drawId)。 */
export function useClaim() {
  const { address } = useAccount();
  const d = useDeployment();
  const { writeContractAsync } = useWriteContract();
  const publicClient = usePublicClient();
  const [status, setStatus] = useState<ClaimStatus>("idle");
  const [error, setError] = useState<Error | null>(null);

  async function claim(tier: number, drawId: number) {
    if (!d || !address || !publicClient) return;
    setError(null);
    try {
      setStatus("waiting");
      const h = await writeContractAsync({
        address: d.prizePool,
        abi: prizePoolAbi,
        functionName: "claimPrize",
        args: [address, tier, drawId],
      });
      await publicClient.waitForTransactionReceipt({ hash: h });
      setStatus("success");
    } catch (e) {
      setError(e instanceof Error ? e : new Error(String(e)));
      setStatus("error");
    }
  }

  return { claim, status, error };
}