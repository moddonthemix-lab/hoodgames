"use client";

import { useMemo, useState } from "react";
import { useAccount, useReadContract, useReadContracts, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { Crosshair, ShieldCheck } from "lucide-react";
import { Card } from "@/components/Card";
import { Button } from "@/components/Button";
import { contracts, isDeployed, FundStatus } from "@/config/contracts";
import { formatToken } from "@/lib/format";
import { useMyFund } from "@/lib/useMyFund";
import { useNow } from "@/lib/useNow";
import { generateSecret, commitmentOf, getStoredSecret, setStoredSecret } from "@/lib/commitReveal";

const MAX_LISTED = 20;

export default function TakeoversPage() {
  const { address } = useAccount();
  const { tokenId: myTokenId } = useMyFund();
  const now = useNow(5000);
  const [error, setError] = useState<string | null>(null);
  const deployed = isDeployed(contracts.gameEngine.address);

  const { data: totalMinted } = useReadContract({
    ...contracts.fundNFT,
    functionName: "totalMinted",
    query: { enabled: deployed },
  });
  const { data: takeoverStake } = useReadContract({
    ...contracts.gameEngine,
    functionName: "TAKEOVER_STAKE",
    query: { enabled: deployed },
  });
  const { data: takeoverImmunity } = useReadContract({
    ...contracts.gameEngine,
    functionName: "TAKEOVER_IMMUNITY",
    query: { enabled: deployed },
  });
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    ...contracts.gameToken,
    functionName: "allowance",
    args: address ? [address, contracts.gameEngine.address] : undefined,
    query: { enabled: deployed && !!address },
  });

  const total = Number(totalMinted ?? 0n);
  const ids = useMemo(() => {
    const start = Math.max(1, total - MAX_LISTED + 1);
    const list: bigint[] = [];
    for (let i = total; i >= start; i--) list.push(BigInt(i));
    return list;
  }, [total]);

  const { data: fundsData } = useReadContracts({
    contracts: ids.map((id) => ({ ...contracts.gameEngine, functionName: "getFund", args: [id] }) as const),
    query: { enabled: deployed && ids.length > 0, refetchInterval: 8000 },
  });
  const { data: lastAttackedData } = useReadContracts({
    contracts: ids.map((id) => ({ ...contracts.gameEngine, functionName: "lastAttackedAt", args: [id] }) as const),
    query: { enabled: deployed && ids.length > 0, refetchInterval: 8000 },
  });

  const { writeContractAsync, isPending } = useWriteContract();
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>(undefined);
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash: txHash, query: { enabled: !!txHash } });

  const needsApproval = takeoverStake !== undefined && (allowance === undefined || (allowance as bigint) < (takeoverStake as bigint));

  async function handleApprove() {
    setError(null);
    try {
      const hash = await writeContractAsync({
        ...contracts.gameToken,
        functionName: "approve",
        args: [contracts.gameEngine.address, takeoverStake as bigint],
      });
      setTxHash(hash);
      setTimeout(() => refetchAllowance(), 3000);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Approval failed");
    }
  }

  async function handleAttack(defenderId: bigint) {
    if (!address || myTokenId === undefined) return;
    setError(null);
    const secret = getStoredSecret(address, myTokenId);
    if (!secret) {
      setError("No commit-reveal secret found for your fund in this browser — can't attack from here.");
      return;
    }
    try {
      const nextSecret = generateSecret();
      const hash = await writeContractAsync({
        ...contracts.gameEngine,
        functionName: "takeover",
        args: [myTokenId, defenderId, secret, commitmentOf(nextSecret)],
      });
      setTxHash(hash);
      setStoredSecret(address, myTokenId, nextSecret);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Takeover failed");
    }
  }

  if (!deployed) {
    return <Card className="text-center text-sm text-warn">Contracts not deployed yet on this network.</Card>;
  }
  if (myTokenId === undefined) {
    return <Card className="text-center text-sm text-ink-muted">Mint or load a fund first (see Fund tab).</Card>;
  }

  return (
    <div className="space-y-4">
      <Card className="flex items-center justify-between text-sm">
        <span className="flex items-center gap-1.5 text-ink-muted">
          <Crosshair size={14} /> Stake per attack
        </span>
        <span className="tabular font-bold text-ink">{formatToken(takeoverStake as bigint | undefined)} MGN</span>
      </Card>

      {needsApproval && (
        <Button variant="ghost" onClick={handleApprove} disabled={isPending || isConfirming}>
          Approve MGN for Takeovers
        </Button>
      )}

      <div className="space-y-2">
        {ids.map((id, i) => {
          if (id === myTokenId) return null;
          const fund = fundsData?.[i]?.result as
            | { traders: number; score: bigint; status: FundStatus }
            | undefined;
          const lastAttacked = (lastAttackedData?.[i]?.result as bigint | undefined) ?? 0n;
          const immunityEnd = Number(lastAttacked) + Number(takeoverImmunity ?? 0n);
          const isImmune = immunityEnd > now;
          const isLiquidated = fund?.status === FundStatus.Liquidated;

          if (!fund || isLiquidated) return null;

          return (
            <Card key={id.toString()} className="flex items-center justify-between">
              <div>
                <p className="text-sm font-semibold text-ink">Fund #{id.toString()}</p>
                <p className="tabular text-xs text-ink-faint">
                  Score {formatToken(fund.score, 1)} · {fund.traders} traders
                </p>
              </div>
              {isImmune ? (
                <span className="flex items-center gap-1 text-xs text-ink-faint">
                  <ShieldCheck size={14} /> Immune
                </span>
              ) : (
                <Button
                  variant="danger"
                  className="w-auto px-3 py-1.5 text-xs"
                  onClick={() => handleAttack(id)}
                  disabled={needsApproval || isPending || isConfirming}
                >
                  Attack
                </Button>
              )}
            </Card>
          );
        })}
        {ids.length === 0 && <p className="text-center text-sm text-ink-muted">No other funds yet.</p>}
      </div>

      {error && <p className="text-center text-xs text-loss">{error}</p>}
    </div>
  );
}
