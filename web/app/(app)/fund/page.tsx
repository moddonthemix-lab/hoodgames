"use client";

import { useState } from "react";
import Link from "next/link";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { Trophy, Users, Building2, TrendingUp, Sprout, AlertTriangle } from "lucide-react";
import clsx from "clsx";
import { Card } from "@/components/Card";
import { Button } from "@/components/Button";
import { StatChip } from "@/components/StatChip";
import { DemoBanner } from "@/components/DemoBanner";
import { FundPulse } from "@/components/FundPulse";
import { contracts, isDeployed, FundStatus } from "@/config/contracts";
import { formatToken, formatEth, formatCountdown } from "@/lib/format";
import { useMyFund } from "@/lib/useMyFund";
import { useNow } from "@/lib/useNow";
import { generateSecret, commitmentOf, getStoredSecret, setStoredSecret } from "@/lib/commitReveal";
import {
  DEMO_FUND,
  DEMO_FUND_MARGIN_CALLED,
  DEMO_EPOCH_LENGTH,
  DEMO_AUM,
  DEMO_RECAP_COST,
  DEMO_NEXT_DESK_COST,
  DEMO_PENDING_YIELD,
  DEMO_PENDING_CAPITAL,
} from "@/lib/demoData";

type FundView = {
  traders: number;
  desks: number;
  lastRebalance: bigint;
  marginCalledAt: bigint;
  score: bigint;
  yieldBalance: bigint;
  capitalBalance: bigint;
  pendingTokenRewards: bigint;
  status: FundStatus;
};

export default function FundPage() {
  const { address } = useAccount();
  const { tokenId, setTokenId } = useMyFund();
  const [manualId, setManualId] = useState("");
  const [demoMarginCalled, setDemoMarginCalled] = useState(false);
  const now = useNow();
  const [error, setError] = useState<string | null>(null);

  const deployed = isDeployed(contracts.gameEngine.address);

  const { data: fund, refetch: refetchFund } = useReadContract({
    ...contracts.gameEngine,
    functionName: "getFund",
    args: tokenId !== undefined ? [tokenId] : undefined,
    query: { enabled: deployed && tokenId !== undefined, refetchInterval: 5000 },
  });
  const { data: epochLength } = useReadContract({
    ...contracts.gameEngine,
    functionName: "EPOCH_LENGTH",
    query: { enabled: deployed },
  });
  const { data: aum } = useReadContract({
    ...contracts.aumStaking,
    functionName: "aumOf",
    args: tokenId !== undefined ? [tokenId] : undefined,
    query: { enabled: deployed && tokenId !== undefined && isDeployed(contracts.aumStaking.address) },
  });
  const { data: recapCost } = useReadContract({
    ...contracts.gameEngine,
    functionName: "recapCost",
    args: tokenId !== undefined ? [tokenId] : undefined,
    query: { enabled: deployed && tokenId !== undefined },
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

  const { writeContractAsync, isPending } = useWriteContract();
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>(undefined);
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({
    hash: txHash,
    query: { enabled: !!txHash },
  });

  const f: FundView | undefined = deployed
    ? (fund as FundView | undefined)
    : demoMarginCalled
      ? DEMO_FUND_MARGIN_CALLED
      : DEMO_FUND;
  const displayEpochLength = deployed ? epochLength ?? 0n : DEMO_EPOCH_LENGTH;
  const displayAum = deployed ? (aum as bigint | undefined) : DEMO_AUM;
  const displayRecapCost = deployed ? (recapCost as bigint | undefined) : DEMO_RECAP_COST;
  const displayDeskCost = deployed ? (deskCost as bigint | undefined) : DEMO_NEXT_DESK_COST;
  const [pendingYield, pendingCapital] = deployed
    ? (pending as [bigint, bigint] | undefined) ?? [0n, 0n]
    : [DEMO_PENDING_YIELD, DEMO_PENDING_CAPITAL];

  const deadline = f ? f.lastRebalance + displayEpochLength : undefined;
  const countdown = formatCountdown(deadline, now);
  const isMarginCalled = f?.status === FundStatus.MarginCalled;
  const isLiquidated = f?.status === FundStatus.Liquidated;
  const openSeats = (f?.desks ?? 0) * 5 - (f?.traders ?? 0);

  async function handleRecapitalize() {
    if (!address || tokenId === undefined || recapCost === undefined) return;
    setError(null);
    try {
      const hash = await writeContractAsync({
        ...contracts.gameEngine,
        functionName: "recapitalize",
        args: [tokenId],
        value: recapCost as bigint,
      });
      setTxHash(hash);
      setTimeout(() => refetchFund(), 3000);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Recapitalize failed");
    }
  }

  async function handleRebalance() {
    if (!address || tokenId === undefined) return;
    setError(null);
    const secret = getStoredSecret(address, tokenId);
    if (!secret) {
      setError("No commit-reveal secret found for this fund in this browser — can't rebalance from here.");
      return;
    }
    try {
      const nextSecret = generateSecret();
      const hash = await writeContractAsync({
        ...contracts.gameEngine,
        functionName: "rebalance",
        args: [tokenId, secret, commitmentOf(nextSecret)],
      });
      setTxHash(hash);
      setStoredSecret(address, tokenId, nextSecret);
      setTimeout(() => refetchFund(), 3000);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Rebalance failed");
    }
  }

  async function handleAction(fn: "claimResources" | "buildDesk") {
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
    return (
      <div className="space-y-4">
        <Card className="text-center text-sm text-ink-muted">
          No fund found in this browser. Mint one from the landing page, or enter a fund ID you already own.
        </Card>
        <Card className="space-y-2">
          <input
            value={manualId}
            onChange={(e) => setManualId(e.target.value)}
            placeholder="Fund ID"
            className="w-full rounded-lg border border-bg-border bg-bg-raised px-3 py-2 text-sm text-ink outline-none focus:border-accent"
          />
          <Button variant="ghost" onClick={() => manualId && setTokenId(BigInt(manualId))}>
            Load Fund
          </Button>
        </Card>
        <Link href="/" className="block text-center text-xs text-accent underline">
          Back to landing to mint
        </Link>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {!deployed && (
        <div>
          <DemoBanner />
          <button onClick={() => setDemoMarginCalled((v) => !v)} className="mb-1 text-[11px] text-accent underline">
            Toggle demo: {demoMarginCalled ? "show Active state" : "show Margin Called state"}
          </button>
        </div>
      )}

      <div className="flex flex-wrap gap-2">
        <StatChip icon={<Trophy size={14} />} label="Score" value={formatToken(f?.score, 1)} />
        <StatChip icon={<Users size={14} />} label="Traders" value={String(f?.traders ?? 0)} />
        <StatChip icon={<Building2 size={14} />} label="Desks" value={String(f?.desks ?? 0)} />
        <StatChip icon={<TrendingUp size={14} />} label="AUM" value={formatToken(displayAum, 0)} tone="profit" />
        <StatChip icon={<Sprout size={14} />} label="Yield" value={f?.yieldBalance?.toString() ?? "0"} />
        <StatChip icon={<Sprout size={14} />} label="Capital" value={f?.capitalBalance?.toString() ?? "0"} />
      </div>

      <Card className={clsx("overflow-hidden text-center", isMarginCalled && "border-loss/50 bg-loss-dim/30")}>
        <FundPulse status={f?.status ?? FundStatus.Active} />
        {isLiquidated ? (
          <p className="text-lg font-bold text-loss">LIQUIDATED</p>
        ) : (
          <>
            <p
              className={clsx(
                "text-[11px] font-bold uppercase tracking-widest",
                isMarginCalled ? "text-loss" : "text-ink-faint"
              )}
            >
              {isMarginCalled ? "MARGIN CALLED — RECAPITALIZE NOW" : "Next Rebalance Due In"}
            </p>
            <p
              className={clsx(
                "tabular mt-1 text-4xl font-black tracking-tight",
                isMarginCalled ? "animate-pulse-danger text-loss" : "text-ink"
              )}
            >
              {countdown}
            </p>
            {isMarginCalled && <AlertTriangle className="mx-auto mt-2 text-loss" size={20} />}
          </>
        )}
      </Card>

      {/* Primary action, matches Stoke Fire's "Stoke Fire" button position */}
      {!isLiquidated && isMarginCalled && (
        <Button onClick={handleRecapitalize} disabled={!deployed || isPending || isConfirming} variant="danger">
          {isPending || isConfirming ? "Confirming…" : `Recapitalize (${formatEth(displayRecapCost)} ETH)`}
        </Button>
      )}
      {!isLiquidated && !isMarginCalled && (
        <Button onClick={handleRebalance} disabled={!deployed || isPending || isConfirming}>
          {isPending || isConfirming ? "Confirming…" : "Rebalance"}
        </Button>
      )}

      {/* Resource gathering, matches Stoke Fire's "Chop Wood" / "Gather Food" buttons */}
      {!isLiquidated && (
        <Button
          variant="ghost"
          onClick={() => handleAction("claimResources")}
          disabled={!deployed || isPending || isConfirming}
        >
          Claim Resources
          {(pendingYield > 0n || pendingCapital > 0n) && (
            <span className="tabular text-profit"> (+{pendingYield.toString()}Y +{pendingCapital.toString()}C)</span>
          )}
        </Button>
      )}

      {/* Build, matches Stoke Fire's "Build: / Hut" section */}
      {!isLiquidated && (
        <div>
          <p className="mb-1.5 text-xs font-bold uppercase tracking-wide text-ink-faint">Build</p>
          <Button
            onClick={() => handleAction("buildDesk")}
            disabled={!deployed || isPending || isConfirming || displayDeskCost === undefined}
          >
            {isPending || isConfirming
              ? "Confirming…"
              : `Desk (${displayDeskCost?.toString() ?? "—"} YIELD) · ${openSeats >= 0 ? openSeats : 0} open seats`}
          </Button>
        </div>
      )}

      {error && <p className="text-center text-xs text-loss">{error}</p>}
    </div>
  );
}
