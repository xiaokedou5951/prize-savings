"use client";

import { useAccount, useReadContract } from "wagmi";
import { prizePoolAbi } from "@prize-savings/contracts";
import { useClaim } from "@/hooks/use-claim";
import { useDeployment } from "@/hooks/use-deployment";
import { useDraws } from "@/hooks/use-draws";
import { useTokens } from "@/hooks/use-tokens";
import { TIER_NAMES, ZERO_ADDRESS } from "@/lib/constants";
import { formatToken } from "@/lib/format";

function ClaimRow({ drawId, tier, claimed }: { drawId: number; tier: number; claimed: boolean }) {
  const { address } = useAccount();
  const d = useDeployment();
  const tokens = useTokens();
  const pool = d?.prizePool ?? ZERO_ADDRESS;
  const { claim, status } = useClaim();

  const { data: amount } = useReadContract({
    address: pool,
    abi: prizePoolAbi,
    functionName: "getClaimableAmount",
    args: address ? [address, tier, drawId] : undefined,
    query: { enabled: !!address && !!d },
  });

  if (claimed) {
    return (
      <li className="flex items-center justify-between py-2 text-sm text-zinc-400">
        <span>
          #{drawId} {TIER_NAMES[tier]} — 已领取
        </span>
      </li>
    );
  }

  if (!amount || amount === BigInt(0)) return null;

  return (
    <li className="flex items-center justify-between py-2">
      <span className="text-sm">
        #{drawId} {TIER_NAMES[tier]} — {formatToken(amount, tokens.prizeDecimals)} {tokens.prizeSymbol}
      </span>
      <button
        type="button"
        onClick={() => claim(tier, drawId)}
        disabled={status === "waiting"}
        className="rounded-lg bg-zinc-900 px-3 py-1.5 text-sm text-white disabled:opacity-40"
      >
        {status === "waiting" ? "领取中…" : "领取"}
      </button>
    </li>
  );
}

export function ClaimPrizes() {
  const { address, isConnected } = useAccount();
  const { data: draws } = useDraws();

  if (!isConnected) {
    return <p className="text-sm text-zinc-500">请先连接钱包。</p>;
  }

  const recent = (draws ?? []).slice(0, 5);
  const rows = recent.flatMap((draw) =>
    [0, 1, 2].map((tier) => ({
      draw,
      tier,
      claimed: draw.claims.some(
        (c) => c.winner.toLowerCase() === address?.toLowerCase() && c.tier === tier,
      ),
    })),
  );

  return (
    <section className="rounded-2xl border border-zinc-200 p-6">
      <h2 className="text-lg font-semibold">可领取的奖金</h2>
      {rows.length === 0 ? (
        <p className="mt-4 text-sm text-zinc-500">暂无开奖记录。</p>
      ) : (
        <ul className="mt-2 divide-y divide-zinc-100">
          {rows.map((r) => (
            <ClaimRow key={`${r.draw.drawId}-${r.tier}`} drawId={r.draw.drawId} tier={r.tier} claimed={r.claimed} />
          ))}
        </ul>
      )}
    </section>
  );
}