"use client";

import { useRouter } from "next/navigation";
import { useAccount, useBalance, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { useState } from "react";
import { decodeEventLog } from "viem";
import { Card } from "@/components/Card";
import { Button } from "@/components/Button";
import { TickerTape } from "@/components/TickerTape";
import { contracts, isDeployed } from "@/config/contracts";
import { formatEth, formatToken } from "@/lib/format";
import { generateInitialSecret, commitmentOf, setStoredSecret } from "@/lib/commitReveal";

export default function LandingPage() {
  const router = useRouter();
  const { address, isConnected } = useAccount();
  const [error, setError] = useState<string | null>(null);

  const deployed = isDeployed(contracts.gameEngine.address);

  const { data: totalFunds } = useReadContract({
    ...contracts.fundNFT,
    functionName: "totalMinted",
    query: { enabled: deployed },
  });
  const { data: tvlAum } = useReadContract({
    ...contracts.gameToken,
    functionName: "balanceOf",
    args: [contracts.aumStaking.address],
    query: { enabled: deployed && isDeployed(contracts.aumStaking.address) },
  });
  const { data: rewardPool } = useBalance({
    address: contracts.rewardsDistributor.address,
    query: { enabled: deployed && isDeployed(contracts.rewardsDistributor.address) },
  });
  const { data: mintFee } = useReadContract({
    ...contracts.gameEngine,
    functionName: "MINT_FEE",
    query: { enabled: deployed },
  });

  const { writeContractAsync, isPending } = useWriteContract();
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>(undefined);
  const { data: receipt, isLoading: isConfirming } = useWaitForTransactionReceipt({ hash: txHash });

  async function handleMint() {
    if (!address) return;
    setError(null);
    try {
      const secret = generateInitialSecret();
      const hash = await writeContractAsync({
        ...contracts.gameEngine,
        functionName: "mintFund",
        args: [commitmentOf(secret)],
        value: mintFee ?? 0n,
      });
      setTxHash(hash);

      // Stash the secret under a temp key; once the receipt confirms the tokenId, we re-key it.
      sessionStorage.setItem("margin:pendingSecret", secret);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Mint failed");
    }
  }

  if (receipt && address) {
    const pendingSecret = sessionStorage.getItem("margin:pendingSecret");
    if (pendingSecret) {
      for (const log of receipt.logs) {
        try {
          const decoded = decodeEventLog({ abi: contracts.gameEngine.abi, data: log.data, topics: log.topics });
          if (decoded.eventName === "FundMinted") {
            const tokenId = (decoded.args as { tokenId: bigint }).tokenId;
            setStoredSecret(address, tokenId, pendingSecret as `0x${string}`);
            localStorage.setItem(`margin:fund:${address.toLowerCase()}`, tokenId.toString());
            sessionStorage.removeItem("margin:pendingSecret");
            router.push("/fund");
          }
        } catch {
          // not the log we're looking for
        }
      }
    }
  }

  const tickerItems = [
    `TOTAL FUNDS ${totalFunds?.toString() ?? "—"}`,
    `AUM STAKED ${formatToken(tvlAum as bigint | undefined)} MGN`,
    `REWARD POOL ${formatEth(rewardPool?.value)} ETH`,
    "REBALANCE EVERY 72H OR GET MARGIN CALLED",
  ];

  return (
    <div className="flex min-h-screen flex-col">
      <TickerTape items={tickerItems} />

      <div className="flex flex-1 flex-col justify-center gap-8 px-6 py-10">
        <div className="space-y-3 text-center">
          <p className="tabular text-xs font-bold uppercase tracking-[0.3em] text-accent">Onchain Fund Survival</p>
          <h1 className="text-4xl font-black tracking-tight text-ink">MARGIN</h1>
          <p className="mx-auto max-w-xs text-sm leading-relaxed text-ink-muted">
            Run an onchain fund. Rebalance every 3 days or get margin called. Farm the token, stake it as AUM, earn
            real ETH from everyone else&apos;s activity, and choose your payout asset. Get liquidated and lose
            everything.
          </p>
        </div>

        <div className="grid grid-cols-3 gap-2">
          <Card className="text-center">
            <p className="tabular text-lg font-bold text-ink">{totalFunds?.toString() ?? "—"}</p>
            <p className="text-[10px] uppercase tracking-wide text-ink-faint">Funds</p>
          </Card>
          <Card className="text-center">
            <p className="tabular text-lg font-bold text-ink">{formatToken(tvlAum as bigint | undefined, 0)}</p>
            <p className="text-[10px] uppercase tracking-wide text-ink-faint">AUM (MGN)</p>
          </Card>
          <Card className="text-center">
            <p className="tabular text-lg font-bold text-profit">{formatEth(rewardPool?.value, 3)}</p>
            <p className="text-[10px] uppercase tracking-wide text-ink-faint">Pool (ETH)</p>
          </Card>
        </div>

        {!deployed ? (
          <Card className="border-warn/40 bg-warn/5 text-center text-sm text-warn">
            Contracts not deployed yet on this network. Set the NEXT_PUBLIC_*_ADDRESS env vars once
            script/Deploy.s.sol has run.
          </Card>
        ) : !isConnected ? (
          <div className="flex justify-center">
            <ConnectButton />
          </div>
        ) : (
          <div className="space-y-2">
            <Button onClick={handleMint} disabled={isPending || isConfirming}>
              {isPending || isConfirming ? "Minting…" : `Mint Fund (${formatEth(mintFee as bigint | undefined)} ETH)`}
            </Button>
            {error && <p className="text-center text-xs text-loss">{error}</p>}
          </div>
        )}
      </div>
    </div>
  );
}
