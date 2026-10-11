"use client";

import { useMemo, useState } from "react";
import { formatUnits, parseUnits } from "viem";
import { useAccount } from "wagmi";
import { useDeposit } from "@/hooks/use-deposit";
import { useTokens } from "@/hooks/use-tokens";
import { formatToken } from "@/lib/format";

export function DepositForm() {
  const { isConnected } = useAccount();
  const tokens = useTokens();
  const { deposit, status, error, reset } = useDeposit();
  const [value, setValue] = useState("");

  const decimals = tokens.usdcDecimals;
  const amount = useMemo(() => {
    if (!value) return BigInt(0);
    try {
      return parseUnits(value, decimals);
    } catch {
      return BigInt(0);
    }
  }, [value, decimals]);

  const busy =
    status === "approving" ||
    status === "waiting-approval" ||
    status === "depositing" ||
    status === "waiting-deposit";
  const needApprove = amount > BigInt(0) && tokens.usdcAllowance < amount;

  const statusText =
    status === "approving" || status === "waiting-approval"
      ? "授权中…"
      : status === "depositing" || status === "waiting-deposit"
        ? "存款中…"
        : status === "success"
          ? "存款成功"
          : error
            ? `失败：${error.message.slice(0, 120)}`
            : "";

  return (
    <section className="rounded-2xl border border-zinc-200 p-6">
      <h2 className="text-lg font-semibold">存款</h2>
      {!isConnected ? (
        <p className="mt-4 text-sm text-zinc-500">请先连接钱包。</p>
      ) : (
        <>
          <p className="mt-2 text-sm text-zinc-500">
            余额 {formatToken(tokens.usdcBalance, decimals)} {tokens.usdcSymbol}
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
              onClick={() => setValue(formatUnits(tokens.usdcBalance, decimals))}
              className="shrink-0 rounded-lg border border-zinc-300 px-3 py-2 text-sm text-zinc-600 hover:bg-zinc-50"
            >
              MAX
            </button>
          </div>
          <p className="mt-2 text-xs text-zinc-400">存入 USDC 按 1:1 铸造份额（pvUSDC），本金随时可取。</p>
          {statusText && <p className="mt-2 text-sm text-zinc-600">{statusText}</p>}
          <button
            type="button"
            onClick={() => deposit(amount)}
            disabled={amount === BigInt(0) || busy}
            className="mt-4 w-full rounded-lg bg-zinc-900 py-2.5 text-white disabled:opacity-40"
          >
            {busy ? "处理中…" : needApprove ? "授权并存款" : "存款"}
          </button>
        </>
      )}
    </section>
  );
}