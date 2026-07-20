"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { LineChart, Building2, Crosshair, Coins, Trophy } from "lucide-react";
import clsx from "clsx";

const TABS = [
  { href: "/fund", label: "Fund", icon: LineChart },
  { href: "/build", label: "Build", icon: Building2 },
  { href: "/takeovers", label: "Takeovers", icon: Crosshair },
  { href: "/rewards", label: "Rewards", icon: Coins },
  { href: "/leaderboard", label: "Leaderboard", icon: Trophy },
] as const;

export function BottomNav() {
  const pathname = usePathname();

  return (
    <nav className="sticky bottom-0 z-20 flex border-t border-bg-border bg-bg-card/95 backdrop-blur">
      {TABS.map(({ href, label, icon: Icon }) => {
        const active = pathname?.startsWith(href);
        return (
          <Link
            key={href}
            href={href}
            className={clsx(
              "flex flex-1 flex-col items-center gap-1 py-2.5 text-[10px] font-medium uppercase tracking-wide transition-colors",
              active ? "text-accent" : "text-ink-faint hover:text-ink-muted"
            )}
          >
            <Icon size={20} strokeWidth={active ? 2.5 : 2} />
            {label}
          </Link>
        );
      })}
    </nav>
  );
}
