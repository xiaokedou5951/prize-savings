export interface Deployment {
  chainId: number;
  usdc: `0x${string}`;
  prizeToken: `0x${string}`;
  yieldVault: `0x${string}`;
  twabController: `0x${string}`;
  prizePool: `0x${string}`;
  prizeVault: `0x${string}`;
  liquidationPair: `0x${string}`;
}

/**
 * 各链部署地址（SSOT）。
 * 31337（foundry/anvil）地址在本地部署后回填；部署脚本 Deploy.s.sol 会在 stdout 打印全部地址。
 */
export const DEPLOYMENTS: Record<number, Deployment> = {
  31337: {
    chainId: 31337,
    usdc: "0x0000000000000000000000000000000000000000",
    prizeToken: "0x0000000000000000000000000000000000000000",
    yieldVault: "0x0000000000000000000000000000000000000000",
    twabController: "0x0000000000000000000000000000000000000000",
    prizePool: "0x0000000000000000000000000000000000000000",
    prizeVault: "0x0000000000000000000000000000000000000000",
    liquidationPair: "0x0000000000000000000000000000000000000000",
  },
};

const ENV_KEYS = {
  usdc: "NEXT_PUBLIC_USDC",
  prizeToken: "NEXT_PUBLIC_PRIZE_TOKEN",
  yieldVault: "NEXT_PUBLIC_YIELD_VAULT",
  twabController: "NEXT_PUBLIC_TWAB_CONTROLLER",
  prizePool: "NEXT_PUBLIC_PRIZE_POOL",
  prizeVault: "NEXT_PUBLIC_PRIZE_VAULT",
  liquidationPair: "NEXT_PUBLIC_LIQUIDATION_PAIR",
} as const;

function envAddress(key: string): `0x${string}` | undefined {
  const v = process.env[key];
  if (v && /^0x[0-9a-fA-F]{40}$/.test(v)) return v as `0x${string}`;
  return undefined;
}

/**
 * 解析当前链的部署地址：优先 NEXT_PUBLIC_* 环境变量覆盖，缺省回落 DEPLOYMENTS[chainId]。
 * 未知链或地址未配置时抛错（前端应在此之前用 useChainId 判断）。
 */
export function getDeployment(chainId: number): Deployment {
  const base = DEPLOYMENTS[chainId];
  if (!base) {
    throw new Error(`No deployment configured for chainId ${chainId}`);
  }
  return {
    chainId,
    usdc: envAddress(ENV_KEYS.usdc) ?? base.usdc,
    prizeToken: envAddress(ENV_KEYS.prizeToken) ?? base.prizeToken,
    yieldVault: envAddress(ENV_KEYS.yieldVault) ?? base.yieldVault,
    twabController: envAddress(ENV_KEYS.twabController) ?? base.twabController,
    prizePool: envAddress(ENV_KEYS.prizePool) ?? base.prizePool,
    prizeVault: envAddress(ENV_KEYS.prizeVault) ?? base.prizeVault,
    liquidationPair: envAddress(ENV_KEYS.liquidationPair) ?? base.liquidationPair,
  };
}