"use client";

import { useAccount, useReadContracts } from "wagmi";
import { erc20Abi } from "@prize-savings/contracts";
import { ZERO_ADDRESS } from "@/lib/constants";
import { useDeployment } from "./use-deployment";

export interface Tokens {
  usdcDecimals: number;
  usdcSymbol: string;
  usdcBalance: bigint;
  usdcAllowance: bigint;
  prizeDecimals: number;
  prizeSymbol: string;
  prizeBalance: bigint;
}

/** USDC / 奖币的元数据与当前账户余额、授权额度。 */
export function useTokens(): Tokens {
  const { address } = useAccount();
  const d = useDeployment();
  const usdc = d?.usdc ?? ZERO_ADDRESS;
  const prizeToken = d?.prizeToken ?? ZERO_ADDRESS;
  const vault = d?.prizeVault ?? ZERO_ADDRESS;

  const { data: meta } = useReadContracts({
    contracts: [
      { address: usdc, abi: erc20Abi, functionName: "decimals" },
      { address: usdc, abi: erc20Abi, functionName: "symbol" },
      { address: prizeToken, abi: erc20Abi, functionName: "decimals" },
      { address: prizeToken, abi: erc20Abi, functionName: "symbol" },
    ],
    allowFailure: false,
    query: { enabled: !!d },
  });

  const { data: userData } = useReadContracts({
    contracts: [
      { address: usdc, abi: erc20Abi, functionName: "balanceOf", args: [address ?? ZERO_ADDRESS] },
      { address: usdc, abi: erc20Abi, functionName: "allowance", args: [address ?? ZERO_ADDRESS, vault] },
      { address: prizeToken, abi: erc20Abi, functionName: "balanceOf", args: [address ?? ZERO_ADDRESS] },
    ],
    allowFailure: false,
    query: { enabled: !!d && !!address },
  });

  return {
    usdcDecimals: meta?.[0] ?? 6,
    usdcSymbol: meta?.[1] ?? "USDC",
    usdcBalance: userData?.[0] ?? BigInt(0),
    usdcAllowance: userData?.[1] ?? BigInt(0),
    prizeDecimals: meta?.[2] ?? 18,
    prizeSymbol: meta?.[3] ?? "PRIZE",
    prizeBalance: userData?.[2] ?? BigInt(0),
  };
}