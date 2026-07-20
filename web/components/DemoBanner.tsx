import { Sparkles } from "lucide-react";

export function DemoBanner() {
  return (
    <div className="mb-3 flex items-center gap-2 rounded-lg border border-accent/40 bg-accent-muted/30 px-3 py-2 text-xs text-ink-muted">
      <Sparkles size={14} className="shrink-0 text-accent" />
      <span>
        <span className="font-bold text-accent">DEMO DATA</span> — contracts aren&apos;t deployed on this network
        yet, so this is fake data to preview the UI. Actions are disabled.
      </span>
    </div>
  );
}
