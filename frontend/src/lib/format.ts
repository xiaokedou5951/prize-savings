import { formatUnits } from "viem";

/** 格式化金额：去掉多余尾零，最多保留 maxFractionDigits 位小数。 */
export function formatToken(
  value: bigint | undefined,
  decimals: number,
  maxFractionDigits = 6,
): string {
  if (value === undefined) return "—";
  const raw = formatUnits(value, decimals);
  const neg = raw.startsWith("-");
  const [int, frac = ""] = (neg ? raw.slice(1) : raw).split(".");
  const f = frac.slice(0, maxFractionDigits).replace(/0+$/, "");
  const sign = neg ? "-" : "";
  return f ? `${sign}${int}.${f}` : `${sign}${int}`;
}

/** 地址缩写：0x1234…abcd。 */
export function shortAddress(addr: string | undefined): string {
  if (!addr) return "—";
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

/** 秒数 → "1d 5h 3m 2s"。 */
export function formatCountdown(totalSeconds: number): string {
  if (!Number.isFinite(totalSeconds) || totalSeconds <= 0) return "已开奖";
  const s = Math.floor(totalSeconds % 60);
  const m = Math.floor((totalSeconds / 60) % 60);
  const h = Math.floor((totalSeconds / 3600) % 24);
  const d = Math.floor(totalSeconds / 86400);
  const parts: string[] = [];
  if (d) parts.push(`${d}d`);
  if (h) parts.push(`${h}h`);
  if (m) parts.push(`${m}m`);
  if (s || parts.length === 0) parts.push(`${s}s`);
  return parts.join(" ");
}

/** 概率/占比（0~1 或更大）→ 百分比字符串。 */
export function formatPercent(ratio: number): string {
  if (!Number.isFinite(ratio) || ratio <= 0) return "0%";
  const pct = ratio * 100;
  if (pct < 0.0001) return "<0.0001%";
  return `${pct.toFixed(4)}%`;
}