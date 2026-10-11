#!/usr/bin/env node
/**
 * 从 Foundry 编译产物（contracts/out/**.json）提取 abi 字段，
 * 生成 packages/contracts/src/abis/*.ts（as const 常量，供 viem/wagmi 字面量类型推断）。
 *
 * 用法（仓库根目录）：
 *   pnpm contracts:build   # 先编译，产出 contracts/out
 *   node scripts/gen-abis.mjs
 * 或一条命令：
 *   pnpm contracts:abis
 *
 * 注意：Erc20.ts 是手写最小 ABI，不在本脚本生成范围内，改动需手工维护。
 */
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const outDir = join(root, "contracts", "out");
const abiDir = join(root, "packages", "contracts", "src", "abis");

/** artifact 相对 contracts/out 的路径 → 生成文件与导出名 */
const TARGETS = [
  { artifact: "PrizeVault.sol/PrizeVault.json", file: "PrizeVault.ts", name: "prizeVaultAbi" },
  { artifact: "PrizePool.sol/PrizePool.json", file: "PrizePool.ts", name: "prizePoolAbi" },
  { artifact: "ITwabController.sol/ITwabController.json", file: "TwabController.ts", name: "twabControllerAbi" },
  { artifact: "LiquidationPair.sol/LiquidationPair.json", file: "LiquidationPair.ts", name: "liquidationPairAbi" },
];

if (!existsSync(outDir)) {
  console.error("contracts/out 不存在，请先运行：pnpm contracts:build");
  process.exit(1);
}

for (const target of TARGETS) {
  const artifactPath = join(outDir, target.artifact);
  if (!existsSync(artifactPath)) {
    console.error(`缺少编译产物 ${target.artifact}，请先运行：pnpm contracts:build`);
    process.exit(1);
  }

  const artifact = JSON.parse(readFileSync(artifactPath, "utf8"));
  if (!Array.isArray(artifact.abi)) {
    console.error(`${target.artifact} 中没有 abi 字段`);
    process.exit(1);
  }

  const content = `export const ${target.name} = ${JSON.stringify(artifact.abi, null, 2)} as const;\n`;
  writeFileSync(join(abiDir, target.file), content);
  console.log(`generated ${target.file} (${artifact.abi.length} entries) <- ${target.artifact}`);
}
