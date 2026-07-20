import { Activity } from "lucide-react";
import { Card } from "./Card";

function timeAgo(minutesAgo: number): string {
  if (minutesAgo < 60) return `${minutesAgo}m ago`;
  const h = Math.floor(minutesAgo / 60);
  return `${h}h ${minutesAgo % 60}m ago`;
}

/**
 * Mirrors Stoke Fire's Activity tab — a live feed of other players' actions is a big part of
 * what makes that game feel alive. Demo-only for now (see lib/demoData.ts's DEMO_ACTIVITY);
 * wiring this to real GameEngine/RewardsDistributor events is the natural next step once
 * contracts are deployed somewhere queryable.
 */
export function ActivityFeed({ items }: { items: readonly { text: string; minutesAgo: number }[] }) {
  return (
    <Card>
      <div className="mb-3 flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-ink-muted">
        <Activity size={16} /> Activity
      </div>
      <ul className="space-y-2.5">
        {items.map((item, i) => (
          <li key={i} className="flex items-baseline justify-between gap-3 text-xs">
            <span className="text-ink-muted">{item.text}</span>
            <span className="tabular shrink-0 text-ink-faint">{timeAgo(item.minutesAgo)}</span>
          </li>
        ))}
      </ul>
    </Card>
  );
}
