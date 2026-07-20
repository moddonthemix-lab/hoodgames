import { formatEther } from "viem";

export function formatEth(wei: bigint | undefined, decimals = 4): string {
  if (wei === undefined) return "0.0000";
  const n = Number(formatEther(wei));
  return n.toFixed(decimals);
}

export function formatToken(wei: bigint | undefined, decimals = 2): string {
  if (wei === undefined) return "0.00";
  const n = Number(formatEther(wei));
  return n.toLocaleString(undefined, { maximumFractionDigits: decimals });
}

export function formatCountdown(targetTimestampSec: bigint | number | undefined, nowSec: number): string {
  if (targetTimestampSec === undefined) return "--:--:--";
  const target = Number(targetTimestampSec);
  const remaining = target - nowSec;
  if (remaining <= 0) return "00:00:00";

  const h = Math.floor(remaining / 3600);
  const m = Math.floor((remaining % 3600) / 60);
  const s = Math.floor(remaining % 60);
  const pad = (v: number) => v.toString().padStart(2, "0");

  if (h >= 24) {
    const d = Math.floor(h / 24);
    return `${d}d ${pad(h % 24)}h ${pad(m)}m`;
  }
  return `${pad(h)}:${pad(m)}:${pad(s)}`;
}

export function shortAddress(address: string | undefined): string {
  if (!address) return "";
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}
