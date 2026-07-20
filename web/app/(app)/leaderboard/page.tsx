"use client";

import { useMemo } from "react";
import { useReadContract, useReadContracts } from "wagmi";
import { Trophy } from "lucide-react";
import { Card } from "@/components/Card";
import { TickerTape } from "@/components/TickerTape";
import { contracts, isDeployed, FundStatus } from "@/config/contracts";
import { formatToken } from "@/lib/format";

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

  const ranked = ids
    .map((id, i) => ({
      id,
      fund: fundsData?.[i]?.result as { score: bigint; status: FundStatus } | undefined,
      owner: ownersData?.[i]?.result as string | undefined,
    }))
    .filter((row) => row.fund && row.fund.status !== FundStatus.Liquidated)
    .sort((a, b) => (b.fund!.score > a.fund!.score ? 1 : b.fund!.score < a.fund!.score ? -1 : 0));

  if (!deployed) {
    return <Card className="text-center text-sm text-warn">Contracts not deployed yet on this network.</Card>;
  }

  return (
    <div className="space-y-4">
      <TickerTape items={[`TOTAL SCORE ${formatToken(totalScore as bigint | undefined, 0)}`, `${total} FUNDS TRACKED`]} />

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
                <p className="tabular text-[10px] text-ink-faint">
                  {row.owner ? `${row.owner.slice(0, 6)}...${row.owner.slice(-4)}` : "—"}
                </p>
              </div>
            </div>
            <span className="flex items-center gap-1 tabular text-sm font-bold text-ink">
              <Trophy size={12} className="text-warn" />
              {formatToken(row.fund?.score, 1)}
            </span>
          </Card>
        ))}
        {ranked.length === 0 && <p className="text-center text-sm text-ink-muted">No active funds yet.</p>}
      </div>
    </div>
  );
}
