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
 * 未在 map 中登记的链（如 84532 Base Sepolia / 本地 fork）完全由 NEXT_PUBLIC_*
 * 环境变量提供地址。env 用静态字面量访问（process.env.NEXT_PUBLIC_FOO），
 * Next.js 可在浏览器端内联；动态 process.env[key] 不会被内联。
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

function envAddress(value: string | undefined): `0x${string}` | undefined {
  if (value && /^0x[0-9a-fA-F]{40}$/.test(value)) return value as `0x${string}`;
  return undefined;
}

/** 静态读取 NEXT_PUBLIC_*，确保浏览器端被 Next.js 内联。 */
function envDeployment(): Partial<Deployment> {
  return {
    usdc: envAddress(process.env.NEXT_PUBLIC_USDC),
    prizeToken: envAddress(process.env.NEXT_PUBLIC_PRIZE_TOKEN),
    yieldVault: envAddress(process.env.NEXT_PUBLIC_YIELD_VAULT),
    twabController: envAddress(process.env.NEXT_PUBLIC_TWAB_CONTROLLER),
    prizePool: envAddress(process.env.NEXT_PUBLIC_PRIZE_POOL),
    prizeVault: envAddress(process.env.NEXT_PUBLIC_PRIZE_VAULT),
    liquidationPair: envAddress(process.env.NEXT_PUBLIC_LIQUIDATION_PAIR),
  };
}

/**
 * 解析当前链的部署地址：
 * - 已知链（DEPLOYMENTS 中有登记）：env 覆盖优先，缺省回落 map 值。
 * - 未知链（如 84532）：完全由 env 提供，缺任意字段则抛错（前端 catch 后显示「未配置」）。
 */
export function getDeployment(chainId: number): Deployment {
  const base = DEPLOYMENTS[chainId];
  const env = envDeployment();

  if (!base) {
    const missing = (Object.keys(env) as (keyof Deployment)[]).filter(
      (k) => k !== "chainId" && !env[k],
    );
    if (missing.length) {
      throw new Error(
        `No deployment for chainId ${chainId}; missing env: ${missing.join(", ")}`,
      );
    }
    return {
      chainId,
      usdc: env.usdc!,
      prizeToken: env.prizeToken!,
      yieldVault: env.yieldVault!,
      twabController: env.twabController!,
      prizePool: env.prizePool!,
      prizeVault: env.prizeVault!,
      liquidationPair: env.liquidationPair!,
    };
  }

  return {
    chainId,
    usdc: env.usdc ?? base.usdc,
    prizeToken: env.prizeToken ?? base.prizeToken,
    yieldVault: env.yieldVault ?? base.yieldVault,
    twabController: env.twabController ?? base.twabController,
    prizePool: env.prizePool ?? base.prizePool,
    prizeVault: env.prizeVault ?? base.prizeVault,
    liquidationPair: env.liquidationPair ?? base.liquidationPair,
  };
}