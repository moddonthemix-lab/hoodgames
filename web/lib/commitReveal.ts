import { keccak256, type Hex } from "viem";

/**
 * GameEngine's commit-reveal cycle (see contracts/src/GameEngine.sol NatSpec): every fund holds
 * exactly one pending secret at a time. mintFund/rebalance/takeover each consume the currently
 * "committed" secret as their `reveal` argument and simultaneously commit a freshly generated one
 * for next time. The frontend is the only place these secrets exist (never sent to the chain in
 * the clear until reveal, never stored server-side) — losing localStorage means losing the
 * ability to act on that fund, so this is a real limitation worth a visible warning in the UI,
 * not just an implementation detail.
 */

function storageKey(address: string, tokenId: bigint): string {
  return `margin:secret:${address.toLowerCase()}:${tokenId.toString()}`;
}

export function generateSecret(): Hex {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return `0x${Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")}` as Hex;
}

export function commitmentOf(secret: Hex): Hex {
  return keccak256(secret);
}

export function getStoredSecret(address: string, tokenId: bigint): Hex | undefined {
  const v = localStorage.getItem(storageKey(address, tokenId));
  return (v as Hex) || undefined;
}

export function setStoredSecret(address: string, tokenId: bigint, secret: Hex): void {
  localStorage.setItem(storageKey(address, tokenId), secret);
}

/** Call before mint: generates the fund's first secret (there's no tokenId to key it by yet, so
 *  the caller must persist it themselves once the tokenId comes back from the mint receipt). */
export function generateInitialSecret(): Hex {
  return generateSecret();
}
