"use client";

import { useMemo, useState } from "react";
import { formatUnits, parseUnits } from "viem";
import { useAccount } from "wagmi";
import { usePrizeVault } from "@/hooks/use-prize-vault";
import { useTokens } from "@/hooks/use-tokens";
import { useWithdraw } from "@/hooks/use-withdraw";
import { formatToken } from "@/lib/format";

export function WithdrawForm() {
  const { isConnected } = useAccount();
  const vault = usePrizeVault();
  const tokens = useTokens();
  const { withdraw, status, error, reset } = useWithdraw();
  const [value, setValue] = useState("");

  const decimals = tokens.usdcDecimals;
  const max = vault?.userShares ?? BigInt(0);
  const amount = useMemo(() => {
    if (!value) return BigInt(0);
    try {
      return parseUnits(value, decimals);
    } catch {
      return BigInt(0);
    }
  }, [value, decimals]);

  const busy = status === "sending" || status === "waiting";

  const statusText =
    busy
      ? "赎回中…"
      : status === "success"
        ? "赎回成功"
        : error
          ? `失败：${error.message.slice(0, 120)}`
          : "";

  return (
    <section className="rounded-2xl border border-zinc-200 p-6">
      <h2 className="text-lg font-semibold">赎回</h2>
      {!isConnected ? (
        <p className="mt-4 text-sm text-zinc-500">请先连接钱包。</p>
      ) : (
        <>
          <p className="mt-2 text-sm text-zinc-500">
            可赎回 {formatToken(max, decimals)} {tokens.usdcSymbol}
          </p>
          <div className="mt-4 flex gap-2">
            <input
              value={value}
              onChange={(e) => {
                setValue(e.target.value);
                if (status === "success" || status === "error") reset();
              }}
              inputMode="decimal"
              placeholder="0.00"
              className="w-full rounded-lg border border-zinc-300 px-3 py-2 outline-none focus:border-zinc-900"
            />
            <button
              type="button"
              onClick={() => setValue(formatUnits(max, decimals))}
              className="shrink-0 rounded-lg border border-zinc-300 px-3 py-2 text-sm text-zinc-600 hover:bg-zinc-50"
            >
              MAX
            </button>
          </div>
          <p className="mt-2 text-xs text-zinc-400">赎回后按 1:1 取回 USDC 本金。</p>
          {statusText && <p className="mt-2 text-sm text-zinc-600">{statusText}</p>}
          <button
            type="button"
            onClick={() => withdraw(amount)}
            disabled={amount === BigInt(0) || amount > max || busy}
            className="mt-4 w-full rounded-lg bg-zinc-900 py-2.5 text-white disabled:opacity-40"
          >
            {busy ? "处理中…" : "赎回"}
          </button>
        </>
      )}
    </section>
  );
}