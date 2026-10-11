"use client";

import { useChainId } from "wagmi";
import { foundry } from "wagmi/chains";
import { getDeployment, type Deployment } from "@prize-savings/contracts";
import { ZERO_ADDRESS } from "@/lib/constants";

/**
 * 解析当前链的部署地址。
 * 未连接时回落到 foundry(31337)；未知链或地址未配置（占位零地址）时返回 undefined。
 */
export function useDeployment(): Deployment | undefined {
  const chainId = useChainId();
  const cid = chainId ?? foundry.id;
  try {
    const d = getDeployment(cid);
    if (d.prizePool === ZERO_ADDRESS || d.prizeVault === ZERO_ADDRESS) return undefined;
    return d;
  } catch {
    return undefined;
  }
}