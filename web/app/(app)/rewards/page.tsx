"use client";

import { useState } from "react";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { Coins, ArrowDownToLine, RefreshCw } from "lucide-react";
import { Card } from "@/components/Card";
import { Button } from "@/components/Button";
import { DemoBanner } from "@/components/DemoBanner";
import { contracts, isDeployed } from "@/config/contracts";
import { formatEth } from "@/lib/format";
import { useMyFund } from "@/lib/useMyFund";
import { useNow } from "@/lib/useNow";
import { useConvertStepAllowed } from "@/lib/useConvertStepAllowed";
import { DEMO_EARNED_ETH, DEMO_WITHDRAWABLE_ETH } from "@/lib/demoData";

export default function RewardsPage() {
  const { address } = useAccount();
  const { tokenId } = useMyFund();
  const now = useNow(5000);
  const [error, setError] = useState<string | null>(null);
  const deployed = isDeployed(contracts.gameEngine.address);
  const convertStep = useConvertStepAllowed();

  const { data: earned, refetch: refetchEarned } = useReadContract({
    ...contracts.rewardsDistributor,
    functionName: "earned",
    args: tokenId !== undefined ? [tokenId] : undefined,
    query: { enabled: deployed && tokenId !== undefined, refetchInterval: 5000 },
  });
  const { data: withdrawable, refetch: refetchWithdrawable } = useReadContract({
    ...contracts.rewardsDistributor,
    functionName: "withdrawable",
    args: address ? [address] : undefined,
    query: { enabled: deployed && !!address, refetchInterval: 5000 },
  });
  const { data: cooldownEnd } = useReadContract({
    ...contracts.rewardsDistributor,
    functionName: "partialRedemptionCooldownEnd",
    args: tokenId !== undefined ? [tokenId] : undefined,
    query: { enabled: deployed && tokenId !== undefined },
  });

  const { writeContractAsync, isPending } = useWriteContract();
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>(undefined);
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash: txHash, query: { enabled: !!txHash } });

  const onCooldown = cooldownEnd !== undefined && Number(cooldownEnd) > now;
  const displayEarned = deployed ? (earned as bigint | undefined) : DEMO_EARNED_ETH;
  const displayWithdrawable = deployed ? (withdrawable as bigint | undefined) : DEMO_WITHDRAWABLE_ETH;

  async function run(fn: "claim" | "claimPartial" | "withdraw") {
    if (fn !== "withdraw" && tokenId === undefined) return;
    setError(null);
    try {
      const hash = await writeContractAsync(
        fn === "withdraw"
          ? { ...contracts.rewardsDistributor, functionName: "withdraw", args: [] }
          : { ...contracts.rewardsDistributor, functionName: fn, args: [tokenId as bigint] }
      );
      setTxHash(hash);
      setTimeout(() => {
        refetchEarned();
        refetchWithdrawable();
      }, 3000);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Transaction failed");
    }
  }

  return (
    <div className="space-y-4">
      {!deployed && <DemoBanner />}

      <Card className="text-center">
        <p className="flex items-center justify-center gap-1.5 text-xs uppercase tracking-wide text-ink-faint">
          <Coins size={14} /> Accrued (this fund)
        </p>
        <p className="tabular mt-1 text-3xl font-black text-profit">{formatEth(displayEarned)} ETH</p>
      </Card>

      {(deployed ? tokenId !== undefined : true) && (
        <div className="grid grid-cols-2 gap-2">
          <Button onClick={() => run("claim")} disabled={!deployed || isPending || isConfirming}>
            Claim Full
          </Button>
          <Button
            variant="ghost"
            onClick={() => run("claimPartial")}
            disabled={!deployed || isPending || isConfirming || onCooldown}
          >
            {onCooldown ? "On Cooldown" : "Claim 50%"}
          </Button>
        </div>
      )}
      <p className="text-center text-[11px] text-ink-faint">
        Full claim resets your fund&apos;s stats to zero. Partial claim pays 50% now with a 50% score haircut and a
        24h cooldown — your fund keeps playing.
      </p>

      <Card className="flex items-center justify-between">
        <span className="flex items-center gap-1.5 text-sm text-ink-muted">
          <ArrowDownToLine size={14} /> Withdrawable
        </span>
        <span className="tabular text-sm font-bold text-ink">{formatEth(displayWithdrawable)} ETH</span>
      </Card>
      <Button
        variant="ghost"
        onClick={() => run("withdraw")}
        disabled={!deployed || isPending || isConfirming || !withdrawable || (withdrawable as bigint) === 0n}
      >
        Withdraw to Wallet
      </Button>

      {convertStep.allowed && displayWithdrawable && displayWithdrawable > 0n && (
        <Card className="space-y-2 border-accent/40">
          <p className="flex items-center gap-1.5 text-sm font-bold text-ink">
            <RefreshCw size={14} /> Convert Payout
          </p>
          <p className="text-xs text-ink-muted">
            Swap withdrawn ETH into a Stock Token (NVDA, AAPL, TSLA…) directly from your wallet via Uniswap. This app
            never holds or routes Stock Tokens — you sign the swap yourself.
          </p>
          <p className="text-xs text-warn">
            TODO: Uniswap router + Stock Token addresses not yet configured for this network — swap UI placeholder.
          </p>
          <Button variant="ghost" disabled>
            Convert (coming soon)
          </Button>
        </Card>
      )}

      {error && <p className="text-center text-xs text-loss">{error}</p>}
    </div>
  );
}
