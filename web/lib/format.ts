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

  // Always hours / minutes / seconds — no days rollover (e.g. "29h 46m 28s"), matching the
  // Stoke Fire reference. Hours can exceed 24.
  const h = Math.floor(remaining / 3600);
  const m = Math.floor((remaining % 3600) / 60);
  const s = Math.floor(remaining % 60);
  const pad = (v: number) => v.toString().padStart(2, "0");
  return `${h}h ${pad(m)}m ${pad(s)}s`;
}

export function shortAddress(address: string | undefined): string {
  if (!address) return "";
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}
