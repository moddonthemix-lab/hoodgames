import type { ReactNode } from "react";
import clsx from "clsx";

export function StatChip({
  icon,
  label,
  value,
  tone = "default",
}: {
  icon: ReactNode;
  label: string;
  value: string;
  tone?: "default" | "profit" | "loss" | "warn";
}) {
  return (
    <div className="flex items-center gap-1.5 rounded-lg border border-bg-border bg-bg-raised px-2.5 py-1.5">
      <span
        className={clsx(
          "shrink-0",
          tone === "profit" && "text-profit",
          tone === "loss" && "text-loss",
          tone === "warn" && "text-warn",
          tone === "default" && "text-ink-muted"
        )}
      >
        {icon}
      </span>
      <span className="tabular text-sm font-medium text-ink">{value}</span>
      <span className="sr-only">{label}</span>
    </div>
  );
}
