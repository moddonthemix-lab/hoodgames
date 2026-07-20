"use client";

import type { ReactNode } from "react";
import { usePathname } from "next/navigation";
import { useReadContract } from "wagmi";
import { TopBar } from "./TopBar";
import { BottomNav } from "./BottomNav";
import { contracts, isDeployed } from "@/config/contracts";
import { formatEth } from "@/lib/format";
import { useMyFund } from "@/lib/useMyFund";

const TITLES: Record<string, string> = {
  "/fund": "My Fund",
  "/build": "Build",
  "/takeovers": "Takeovers",
  "/rewards": "Rewards",
  "/leaderboard": "Leaderboard",
};

export function AppShell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const title = TITLES[pathname ?? ""] ?? "MARGIN";
  const { tokenId } = useMyFund();

  const { data: accrued } = useReadContract({
    ...contracts.rewardsDistributor,
    functionName: "earned",
    args: tokenId !== undefined ? [tokenId] : undefined,
    query: { enabled: tokenId !== undefined && isDeployed(contracts.rewardsDistributor.address) },
  });

  return (
    <div className="flex min-h-screen flex-col">
      <TopBar title={title} accruedEth={formatEth(accrued as bigint | undefined)} />
      <main className="flex-1 overflow-y-auto px-4 py-4">{children}</main>
      <BottomNav />
    </div>
  );
}
