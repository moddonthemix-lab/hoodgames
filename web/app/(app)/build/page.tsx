"use client";

import { useState } from "react";
import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { Building2, Sprout } from "lucide-react";
import { Card } from "@/components/Card";
import { Button } from "@/components/Button";
import { DemoBanner } from "@/components/DemoBanner";
import { contracts, isDeployed } from "@/config/contracts";
import { useMyFund } from "@/lib/useMyFund";
import { DEMO_FUND, DEMO_NEXT_DESK_COST, DEMO_PENDING_YIELD, DEMO_PENDING_CAPITAL } from "@/lib/demoData";

type FundView = { traders: number; desks: number; yieldBalance: bigint; capitalBalance: bigint };

export default function BuildPage() {
  const { tokenId } = useMyFund();
  const [error, setError] = useState<string | null>(null);
  const deployed = isDeployed(contracts.gameEngine.address);

  const { data: fund, refetch: refetchFund } = useReadContract({
    ...contracts.gameEngine,
    functionName: "getFund",
    args: tokenId !== undefined ? [tokenId] : undefined,
    query: { enabled: deployed && tokenId !== undefined, refetchInterval: 5000 },
  });
  const { data: pending, refetch: refetchPending } = useReadContract({
    ...contracts.gameEngine,
    functionName: "pendingResources",
    args: tokenId !== undefined ? [tokenId] : undefined,
    query: { enabled: deployed && tokenId !== undefined, refetchInterval: 5000 },
  });
  const { data: deskCost } = useReadContract({
    ...contracts.gameEngine,
    functionName: "nextDeskCost",
    args: tokenId !== undefined ? [tokenId] : undefined,
    query: { enabled: deployed && tokenId !== undefined },
  });

  const { writeContractAsync, isPending: isTxPending } = useWriteContract();
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>(undefined);
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash: txHash, query: { enabled: !!txHash } });

  const f: FundView | undefined = deployed ? (fund as FundView | undefined) : DEMO_FUND;
  const [pendingYield, pendingCapital] = deployed
    ? (pending as [bigint, bigint] | undefined) ?? [0n, 0n]
    : [DEMO_PENDING_YIELD, DEMO_PENDING_CAPITAL];
  const displayDeskCost = deployed ? (deskCost as bigint | undefined) : DEMO_NEXT_DESK_COST;

  async function run(fn: "claimResources" | "buildDesk") {
    if (tokenId === undefined) return;
    setError(null);
    try {
      const hash = await writeContractAsync({ ...contracts.gameEngine, functionName: fn, args: [tokenId] });
      setTxHash(hash);
      setTimeout(() => {
        refetchFund();
        refetchPending();
      }, 3000);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Transaction failed");
    }
  }

  if (deployed && tokenId === undefined) {
    return <Card className="text-center text-sm text-ink-muted">Mint or load a fund first (see Fund tab).</Card>;
  }

  const openSeats = (f?.desks ?? 0) * 5 - (f?.traders ?? 0);

  return (
    <div className="space-y-4">
      {!deployed && <DemoBanner />}

      <Card>
        <div className="mb-3 flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-ink-muted">
          <Sprout size={16} /> Resources
        </div>
        <div className="grid grid-cols-2 gap-2">
          <div>
            <p className="tabular text-xl font-bold text-ink">{f?.yieldBalance?.toString() ?? "0"}</p>
            <p className="text-[10px] uppercase text-ink-faint">Yield</p>
            {pendingYield > 0n && <p className="tabular text-xs text-profit">+{pendingYield.toString()} pending</p>}
          </div>
          <div>
            <p className="tabular text-xl font-bold text-ink">{f?.capitalBalance?.toString() ?? "0"}</p>
            <p className="text-[10px] uppercase text-ink-faint">Capital</p>
            {pendingCapital > 0n && (
              <p className="tabular text-xs text-profit">+{pendingCapital.toString()} pending</p>
            )}
          </div>
        </div>
        <Button
          variant="ghost"
          className="mt-3"
          onClick={() => run("claimResources")}
          disabled={!deployed || isTxPending || isConfirming}
        >
          Claim Resources
        </Button>
      </Card>

      <Card>
        <div className="mb-3 flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-ink-muted">
          <Building2 size={16} /> Desks
        </div>
        <div className="flex items-center justify-between text-sm text-ink">
          <span>
            {f?.desks ?? 0} desk{f?.desks === 1 ? "" : "s"} built
          </span>
          <span className="tabular text-ink-muted">
            {openSeats >= 0 ? openSeats : 0} open seat{openSeats === 1 ? "" : "s"}
          </span>
        </div>
        <p className="mt-1 text-xs text-ink-faint">Each desk seats 5 traders. Cost escalates per desk (1.15x).</p>
        <Button
          className="mt-3"
          onClick={() => run("buildDesk")}
          disabled={!deployed || isTxPending || isConfirming || displayDeskCost === undefined}
        >
          {isTxPending || isConfirming ? "Confirming…" : `Build Desk (${displayDeskCost?.toString() ?? "—"} YIELD)`}
        </Button>
      </Card>

      {error && <p className="text-center text-xs text-loss">{error}</p>}
    </div>
  );
}
