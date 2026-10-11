"use client";

import type { Draw } from "@/hooks/use-draws";
import { useTokens } from "@/hooks/use-tokens";
import { TIER_NAMES } from "@/lib/constants";
import { formatToken, shortAddress } from "@/lib/format";

export function WinnersList({ draw }: { draw: Draw }) {
  const tokens = useTokens();

  if (draw.claims.length === 0) {
    return <p className="text-sm text-zinc-500">暂无中奖记录。</p>;
  }

  return (
    <ul className="divide-y divide-zinc-100 rounded-2xl border border-zinc-200">
      {draw.claims.map((c, i) => (
        <li key={i} className="flex items-center justify-between px-6 py-3 text-sm">
          <span>
            {TIER_NAMES[c.tier]} · <span className="font-mono">{shortAddress(c.winner)}</span>
          </span>
          <span>
            {formatToken(c.amount, tokens.prizeDecimals)} {tokens.prizeSymbol}
          </span>
        </li>
      ))}
    </ul>
  );
}