"use client";

import { usePrizePool } from "@/hooks/use-prize-pool";
import { useTokens } from "@/hooks/use-tokens";
import { TIER_NAMES } from "@/lib/constants";
import { formatPercent, formatToken } from "@/lib/format";

export function PrizeTiers() {
  const pool = usePrizePool();
  const tokens = useTokens();

  if (!pool) {
    return <p className="text-sm text-zinc-500">奖池未部署或地址未配置。</p>;
  }

  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
      {pool.tiers.map((t) => (
        <div key={t.tier} className="rounded-2xl border border-zinc-200 p-5">
          <p className="font-semibold">{TIER_NAMES[t.tier]}</p>
          <p className="mt-2 text-sm text-zinc-500">{t.count.toString()} 个名额</p>
          <p className="text-sm text-zinc-500">占比 {formatPercent(Number(t.fraction) / 1e18)}</p>
          <p className="mt-3 text-xl font-semibold">
            {formatToken(t.prizeSize, tokens.prizeDecimals)}{" "}
            <span className="text-sm font-normal text-zinc-500">{tokens.prizeSymbol}</span>
          </p>
        </div>
      ))}
    </div>
  );
}