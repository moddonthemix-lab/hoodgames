"use client";

import { useCallback, useEffect, useState } from "react";
import { useAccount } from "wagmi";

/**
 * MARGIN's FundNFT is a plain ERC-721 (no Enumerable extension — see contracts/DECISIONS.md /
 * README for why), so there's no on-chain "which tokenId does this wallet own" lookup without an
 * indexer/subgraph. For now this is tracked client-side: mintFund's tokenId gets saved to
 * localStorage keyed by address as soon as it's minted, and the user can also punch in a tokenId
 * manually (e.g. after switching devices) via `setTokenId`. A production build should replace
 * this with an indexer or add ERC721Enumerable to FundNFT.
 */
export function useMyFund() {
  const { address } = useAccount();
  const [tokenId, setTokenIdState] = useState<bigint | undefined>(undefined);

  useEffect(() => {
    if (!address) {
      setTokenIdState(undefined);
      return;
    }
    const stored = localStorage.getItem(`margin:fund:${address.toLowerCase()}`);
    setTokenIdState(stored ? BigInt(stored) : undefined);
  }, [address]);

  const setTokenId = useCallback(
    (id: bigint) => {
      if (!address) return;
      localStorage.setItem(`margin:fund:${address.toLowerCase()}`, id.toString());
      setTokenIdState(id);
    },
    [address]
  );

  const clearTokenId = useCallback(() => {
    if (!address) return;
    localStorage.removeItem(`margin:fund:${address.toLowerCase()}`);
    setTokenIdState(undefined);
  }, [address]);

  return { tokenId, setTokenId, clearTokenId };
}
