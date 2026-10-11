"use client";

import Link from "next/link";
import { useDraws } from "@/hooks/use-draws";
import { useTokens } from "@/hooks/use-tokens";
import { formatToken } from "@/lib/format";

export function DrawList() {
  const { data: draws, isLoading } = useDraws();
  const tokens = useTokens();

  if (isLoading) return <p className="text-sm text-zinc-500">加载中…</p>;
  if (!draws?.length) return <p className="text-sm text-zinc-500">暂无开奖记录。</p>;

  return (
    <ul className="divide-y divide-zinc-100 rounded-2xl border border-zinc-200">
      {draws.map((draw) => (
        <li key={draw.drawId}>
          <Link
            href={`/draw/${draw.drawId}`}
            className="flex items-center justify-between px-6 py-4 transition hover:bg-zinc-50"
          >
            <span className="font-semibold">第 {draw.drawId} 期</span>
            <span className="text-sm text-zinc-500">
              {formatToken(draw.drawAmount, tokens.prizeDecimals)} {tokens.prizeSymbol} · {draw.claims.length} 笔领取
            </span>
          </Link>
        </li>
      ))}
    </ul>
  );
}