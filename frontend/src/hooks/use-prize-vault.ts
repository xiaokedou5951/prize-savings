"use client";

import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { prizeVaultAbi } from "@prize-savings/contracts";
import { ZERO_ADDRESS } from "@/lib/constants";
import { useDeployment } from "./use-deployment";

export interface VaultData {
  totalAssets: bigint;
  totalSupply: bigint;
  liquidatable: bigint;
  decimals: number;
  userShares?: bigint;
}

/** Prize Vault 全局状态与当前账户份额。 */
export function usePrizeVault(): VaultData | undefined {
  const { address } = useAccount();
  const d = useDeployment();
  const vault = d?.prizeVault ?? ZERO_ADDRESS;

  const { data: g } = useReadContracts({
    contracts: [
      { address: vault, abi: prizeVaultAbi, functionName: "totalAssets" },
      { address: vault, abi: prizeVaultAbi, functionName: "totalSupply" },
      { address: vault, abi: prizeVaultAbi, functionName: "liquidatableBalanceOf" },
      { address: vault, abi: prizeVaultAbi, functionName: "decimals" },
    ],
    allowFailure: false,
    query: { enabled: !!d },
  });

  const { data: userShares } = useReadContract({
    address: vault,
    abi: prizeVaultAbi,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!d && !!address },
  });

  if (!g) return undefined;
  return {
    totalAssets: g[0],
    totalSupply: g[1],
    liquidatable: g[2],
    decimals: g[3],
    userShares,
  };
}