"use client";

import { useState } from "react";
import { useAccount, usePublicClient, useWriteContract } from "wagmi";
import { prizeVaultAbi } from "@prize-savings/contracts";
import { useDeployment } from "./use-deployment";

export type WithdrawStatus = "idle" | "sending" | "waiting" | "success" | "error";

/** 赎回封装：withdraw(assets, receiver, owner)。 */
export function useWithdraw() {
  const { address } = useAccount();
  const d = useDeployment();
  const { writeContractAsync } = useWriteContract();
  const publicClient = usePublicClient();
  const [status, setStatus] = useState<WithdrawStatus>("idle");
  const [error, setError] = useState<Error | null>(null);

  async function withdraw(amount: bigint) {
    if (!d || !address || !publicClient || amount === BigInt(0)) return;
    setError(null);
    try {
      setStatus("sending");
      const h = await writeContractAsync({
        address: d.prizeVault,
        abi: prizeVaultAbi,
        functionName: "withdraw",
        args: [amount, address, address],
      });
      setStatus("waiting");
      await publicClient.waitForTransactionReceipt({ hash: h });
      setStatus("success");
    } catch (e) {
      setError(e instanceof Error ? e : new Error(String(e)));
      setStatus("error");
    }
  }

  function reset() {
    setStatus("idle");
    setError(null);
  }

  return { withdraw, status, error, reset };
}