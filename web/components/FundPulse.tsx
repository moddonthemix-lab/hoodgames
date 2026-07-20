import { FundStatus } from "@/config/contracts";

/**
 * The visual centerpiece of the Fund screen — Stoke Fire's equivalent is a pixel-art fire that
 * dies down as the countdown runs out. MARGIN's theme is Bloomberg-terminal-meets-degen, so this
 * is a ticker/chart pulse instead: a rising green line when the fund is healthy, a jagged falling
 * red line (with the same danger-pulse animation used elsewhere) when margin-called, a flat dead
 * line when liquidated. Pure SVG, no external art assets.
 */
export function FundPulse({ status }: { status: FundStatus }) {
  const isMarginCalled = status === FundStatus.MarginCalled;
  const isLiquidated = status === FundStatus.Liquidated;

  const color = isLiquidated ? "#5a6280" : isMarginCalled ? "#ff4d6a" : "#22e5a0";
  const gradientId = isLiquidated ? "pulse-dead" : isMarginCalled ? "pulse-loss" : "pulse-profit";

  const linePath = isLiquidated
    ? "M0,120 L300,120"
    : isMarginCalled
      ? "M0,25 L28,42 L52,32 L80,58 L108,48 L136,74 L164,62 L192,88 L220,78 L248,102 L276,92 L300,112"
      : "M0,112 L28,98 L52,104 L80,72 L108,82 L136,52 L164,62 L192,36 L220,46 L248,22 L276,32 L300,12";

  const areaPath = `${linePath} L300,140 L0,140 Z`;
  const [endX, endY] = linePath
    .split("L")
    .slice(-1)[0]
    .trim()
    .split(",")
    .map(Number);

  return (
    <svg viewBox="0 0 300 140" className="h-32 w-full" preserveAspectRatio="none" aria-hidden="true">
      <defs>
        <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity="0.35" />
          <stop offset="100%" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={areaPath} fill={`url(#${gradientId})`} />
      <path
        d={linePath}
        fill="none"
        stroke={color}
        strokeWidth="2.5"
        strokeLinecap="round"
        strokeLinejoin="round"
        className={isMarginCalled ? "animate-pulse-danger" : undefined}
      />
      {!isLiquidated && <circle cx={endX} cy={endY} r="4" fill={color} className="animate-pulse" />}
    </svg>
  );
}
