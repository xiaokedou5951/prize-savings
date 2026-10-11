"use client";

import { useState } from "react";
import { useAccount, usePublicClient, useWriteContract } from "wagmi";
import { erc20Abi, prizeVaultAbi } from "@prize-savings/contracts";
import { useDeployment } from "./use-deployment";
import { useTokens } from "./use-tokens";

export type DepositStatus =
  | "idle"
  | "approving"
  | "waiting-approval"
  | "depositing"
  | "waiting-deposit"
  | "success"
  | "error";

/** 存款封装：若授权不足则先 approve，再 deposit；逐步等待交易确认。 */
export function useDeposit() {
  const { address } = useAccount();
  const d = useDeployment();
  const { usdcAllowance } = useTokens();
  const { writeContractAsync } = useWriteContract();
  const publicClient = usePublicClient();
  const [status, setStatus] = useState<DepositStatus>("idle");
  const [error, setError] = useState<Error | null>(null);

  async function deposit(amount: bigint) {
    if (!d || !address || !publicClient || amount === BigInt(0)) return;
    setError(null);
    try {
      if (usdcAllowance < amount) {
        setStatus("approving");
        const h1 = await writeContractAsync({
          address: d.usdc,
          abi: erc20Abi,
          functionName: "approve",
          args: [d.prizeVault, amount],
        });
        setStatus("waiting-approval");
        await publicClient.waitForTransactionReceipt({ hash: h1 });
      }
      setStatus("depositing");
      const h2 = await writeContractAsync({
        address: d.prizeVault,
        abi: prizeVaultAbi,
        functionName: "deposit",
        args: [amount, address],
      });
      setStatus("waiting-deposit");
      await publicClient.waitForTransactionReceipt({ hash: h2 });
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

  return { deposit, status, error, reset };
}