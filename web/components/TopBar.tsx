"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Wallet } from "lucide-react";

export function TopBar({ title, accruedEth }: { title: string; accruedEth?: string }) {
  return (
    <header className="sticky top-0 z-20 flex items-center justify-between border-b border-bg-border bg-bg/95 px-4 py-3 backdrop-blur">
      <div className="flex items-center gap-1.5 text-profit">
        <Wallet size={14} />
        <span className="tabular text-xs font-semibold">{accruedEth ?? "0.0000"} ETH</span>
      </div>
      <h1 className="absolute left-1/2 -translate-x-1/2 text-sm font-bold uppercase tracking-widest text-ink">
        {title}
      </h1>
      <ConnectButton showBalance={false} chainStatus="icon" accountStatus="avatar" />
    </header>
  );
}
