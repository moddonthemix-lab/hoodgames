export function TickerTape({ items }: { items: string[] }) {
  if (items.length === 0) return null;
  // Duplicate content once so the -50% translateX loop (see tailwind.config.ts `ticker` keyframe)
  // is seamless.
  const doubled = [...items, ...items];

  return (
    <div className="overflow-hidden border-b border-bg-border bg-bg-raised py-1.5">
      <div className="flex w-max animate-ticker gap-8 whitespace-nowrap">
        {doubled.map((item, i) => (
          <span key={i} className="tabular text-xs text-ink-muted">
            {item}
          </span>
        ))}
      </div>
    </div>
  );
}
