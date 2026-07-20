"use client";

import { useMemo } from "react";
import { useReadContract, useReadContracts } from "wagmi";
import { Trophy } from "lucide-react";
import { Card } from "@/components/Card";
import { TickerTape } from "@/components/TickerTape";
import { DemoBanner } from "@/components/DemoBanner";
import { ActivityFeed } from "@/components/ActivityFeed";
import { contracts, isDeployed, FundStatus } from "@/config/contracts";
import { formatToken, shortAddress } from "@/lib/format";
import { DEMO_TOTAL_SCORE, DEMO_TOTAL_FUNDS, DEMO_LEADERBOARD, DEMO_ACTIVITY } from "@/lib/demoData";

const MAX_RANKED = 50;

export default function LeaderboardPage() {
  const deployed = isDeployed(contracts.gameEngine.address);

  const { data: totalMinted } = useReadContract({
    ...contracts.fundNFT,
    functionName: "totalMinted",
    query: { enabled: deployed },
  });
  const { data: totalScore } = useReadContract({
    ...contracts.gameEngine,
    functionName: "totalScore",
    query: { enabled: deployed, refetchInterval: 10000 },
  });

  const total = Number(totalMinted ?? 0n);
  const ids = useMemo(() => {
    const start = Math.max(1, total - MAX_RANKED + 1);
    const list: bigint[] = [];
    for (let i = start; i <= total; i++) list.push(BigInt(i));
    return list;
  }, [total]);

  const { data: fundsData } = useReadContracts({
    contracts: ids.map((id) => ({ ...contracts.gameEngine, functionName: "getFund", args: [id] }) as const),
    query: { enabled: deployed && ids.length > 0, refetchInterval: 10000 },
  });
  const { data: ownersData } = useReadContracts({
    contracts: ids.map((id) => ({ ...contracts.fundNFT, functionName: "ownerOf", args: [id] }) as const),
    query: { enabled: deployed && ids.length > 0 },
  });

  const ranked = deployed
    ? ids
        .map((id, i) => ({
          id,
          score: (fundsData?.[i]?.result as { score: bigint; status: FundStatus } | undefined)?.score,
          status: (fundsData?.[i]?.result as { score: bigint; status: FundStatus } | undefined)?.status,
          owner: ownersData?.[i]?.result as string | undefined,
        }))
        .filter((row) => row.score !== undefined && row.status !== FundStatus.Liquidated)
        .sort((a, b) => (b.score! > a.score! ? 1 : b.score! < a.score! ? -1 : 0))
    : DEMO_LEADERBOARD.map((row) => ({ id: row.id, score: row.score, status: FundStatus.Active, owner: row.owner }));

  const displayTotalScore = deployed ? (totalScore as bigint | undefined) : DEMO_TOTAL_SCORE;
  const displayTotalFunds = deployed ? total : Number(DEMO_TOTAL_FUNDS);

  return (
    <div className="space-y-4">
      {!deployed && <DemoBanner />}
      <TickerTape items={[`TOTAL SCORE ${formatToken(displayTotalScore, 0)}`, `${displayTotalFunds} FUNDS TRACKED`]} />

      <div className="space-y-1.5">
        {ranked.map((row, rank) => (
          <Card key={row.id.toString()} className="flex items-center justify-between py-2.5">
            <div className="flex items-center gap-3">
              <span
                className={
                  "tabular w-6 text-center text-sm font-black " +
                  (rank === 0 ? "text-warn" : rank === 1 ? "text-ink-muted" : rank === 2 ? "text-loss" : "text-ink-faint")
                }
              >
                {rank + 1}
              </span>
              <div>
                <p className="text-xs font-semibold text-ink">Fund #{row.id.toString()}</p>
                <p className="tabular text-[10px] text-ink-faint">{shortAddress(row.owner)}</p>
              </div>
            </div>
            <span className="flex items-center gap-1 tabular text-sm font-bold text-ink">
              <Trophy size={12} className="text-warn" />
              {formatToken(row.score, 1)}
            </span>
          </Card>
        ))}
        {ranked.length === 0 && <p className="text-center text-sm text-ink-muted">No active funds yet.</p>}
      </div>

      {/* Demo-only — see ActivityFeed's header comment. Hidden once real contracts are wired up
          rather than showing fake activity next to real leaderboard data. */}
      {!deployed && <ActivityFeed items={DEMO_ACTIVITY} />}
    </div>
  );
}
