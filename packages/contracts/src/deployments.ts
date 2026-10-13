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
 *
 * 31337（anvil）：Deploy.s.sol 由 anvil 默认账户 0xf39F…2266 按固定顺序 CREATE
 * 部署，nonce 0–6 决定地址，每次全新 anvil 上地址都相同：
 *   nonce 0 USDC / 1 PRIZE / 2 MockYieldVault / 3 TwabController /
 *   4 PrizePool / 5 PrizeVault / 6 LiquidationPair
 *
 * 注意：浏览器端不要依赖下面的 NEXT_PUBLIC_* env 覆盖——本包经 transpilePackages
 * 编译且使用 `process.env[key]` 动态访问，打包器无法静态内联 NEXT_PUBLIC_* 变量。
 * 浏览器侧以本 map 为准；env 仅在 Node 侧（SSR/脚本）生效。
 */
export const DEPLOYMENTS: Record<number, Deployment> = {
  31337: {
    chainId: 31337,
    usdc: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    prizeToken: "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512",
    yieldVault: "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",
    twabController: "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9",
    prizePool: "0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9",
    prizeVault: "0x5FC8d32690cc91D4c39d9d3abcBD16989F875707",
    liquidationPair: "0x0165878A594ca255338adfa4d48449f69242Eb8F",
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