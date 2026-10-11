"use client";

import { useEffect, useState } from "react";
import { usePrizePool } from "@/hooks/use-prize-pool";
import { useTokens } from "@/hooks/use-tokens";
import { formatCountdown, formatToken } from "@/lib/format";

export function PrizePoolCard() {
  const pool = usePrizePool();
  const tokens = useTokens();
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000));

  useEffect(() => {
    const t = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000);
    return () => clearInterval(t);
  }, []);

  if (!pool) {
    return (
      <section className="rounded-2xl border border-zinc-200 p-6 text-sm text-zinc-500">
        奖池未部署或地址未配置。
      </section>
    );
  }

  return (
    <section className="rounded-2xl border border-zinc-200 bg-gradient-to-br from-zinc-50 to-white p-6">
      <p className="text-sm text-zinc-500">当前奖池</p>
      <p className="mt-1 text-4xl font-bold tracking-tight">
        {formatToken(pool.poolBalance, tokens.prizeDecimals)}{" "}
        <span className="text-lg font-medium text-zinc-500">{tokens.prizeSymbol}</span>
      </p>
      <p className="mt-3 text-sm text-zinc-600">下一期开奖倒计时：{formatCountdown(pool.nextDrawStart - now)}</p>
    </section>
  );
}