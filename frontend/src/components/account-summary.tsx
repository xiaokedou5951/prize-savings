"use client";

import { useAccount } from "wagmi";
import { usePrizeVault } from "@/hooks/use-prize-vault";
import { useTwab } from "@/hooks/use-twab";
import { formatPercent, formatToken, shortAddress } from "@/lib/format";

export function AccountSummary() {
  const { address, isConnected } = useAccount();
  const vault = usePrizeVault();
  const { userTwab, probability } = useTwab();

  if (!isConnected) {
    return <p className="text-sm text-zinc-500">请先连接钱包。</p>;
  }

  return (
    <section className="rounded-2xl border border-zinc-200 p-6">
      <h2 className="text-lg font-semibold">我的账户</h2>
      <dl className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-3">
        <div>
          <dt className="text-sm text-zinc-500">地址</dt>
          <dd className="mt-1 font-mono text-sm">{shortAddress(address)}</dd>
        </div>
        <div>
          <dt className="text-sm text-zinc-500">我的存款</dt>
          <dd className="mt-1 text-2xl font-semibold">
            {formatToken(vault?.userShares, 6)} <span className="text-sm font-normal text-zinc-500">USDC</span>
          </dd>
        </div>
        <div>
          <dt className="text-sm text-zinc-500">当前 TWAB</dt>
          <dd className="mt-1 text-2xl font-semibold">{formatToken(userTwab, 6)}</dd>
        </div>
        <div>
          <dt className="text-sm text-zinc-500">中奖概率</dt>
          <dd className="mt-1 text-2xl font-semibold">{formatPercent(probability)}</dd>
        </div>
      </dl>
    </section>
  );
}