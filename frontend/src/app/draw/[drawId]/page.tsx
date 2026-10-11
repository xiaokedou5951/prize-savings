"use client";

import { useParams } from "next/navigation";
import Link from "next/link";
import { WinnersList } from "@/components/winners-list";
import { useDraws } from "@/hooks/use-draws";
import { useTokens } from "@/hooks/use-tokens";
import { formatToken } from "@/lib/format";

export default function DrawPage() {
  const params = useParams<{ drawId: string }>();
  const drawId = Number(params.drawId);
  const { data: draws, isLoading } = useDraws();
  const tokens = useTokens();

  if (isLoading) return <p className="text-sm text-zinc-500">加载中…</p>;

  const draw = draws?.find((d) => d.drawId === drawId);
  if (!draw) return <p className="text-sm text-zinc-500">未找到该期开奖。</p>;

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">第 {draw.drawId} 期开奖</h1>
        <Link href="/prizes" className="text-sm text-zinc-500 hover:underline">
          ← 返回列表
        </Link>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div className="rounded-2xl border border-zinc-200 p-5">
          <p className="text-sm text-zinc-500">奖池总额</p>
          <p className="mt-1 text-2xl font-semibold">
            {formatToken(draw.drawAmount, tokens.prizeDecimals)} {tokens.prizeSymbol}
          </p>
        </div>
        <div className="rounded-2xl border border-zinc-200 p-5">
          <p className="text-sm text-zinc-500">随机数（seed）</p>
          <p className="mt-1 break-all font-mono text-sm">{draw.winningRandomNumber.toString()}</p>
        </div>
      </div>

      <section>
        <h2 className="mb-4 text-lg font-semibold">中奖者</h2>
        <WinnersList draw={draw} />
      </section>
    </div>
  );
}