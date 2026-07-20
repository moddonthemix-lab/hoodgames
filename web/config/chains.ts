import { defineChain } from "viem";
import { anvil } from "wagmi/chains";

/**
 * Robinhood Chain (Arbitrum Orbit L2) — MARGIN_SPEC.md section 1.
 *
 * TODO (do not hardcode a guessed RPC URL — see MARGIN_SPEC.md ground rules): the RPC URL below
 * is a placeholder read from NEXT_PUBLIC_ROBINHOOD_RPC_URL. Pull the real one from Robinhood
 * Chain's official developer documentation portal before pointing this at anything real. Same
 * caveat as contracts/script/config/NetworkConfig.sol — keep the two in sync.
 */
export const robinhoodChain = defineChain({
  id: 4663,
  name: "Robinhood Chain",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: {
      http: [process.env.NEXT_PUBLIC_ROBINHOOD_RPC_URL || "https://TODO-fill-in-from-robinhood-chain-docs.example"],
    },
  },
  blockExplorers: {
    // TODO: confirm the Blockscout instance URL for Robinhood Chain.
    default: { name: "Blockscout", url: process.env.NEXT_PUBLIC_ROBINHOOD_EXPLORER_URL || "https://TODO.example" },
  },
  testnet: false,
});

/**
 * Fallback testnet target per the ground rules ("Arbitrum Sepolia if RH testnet unavailable").
 * Only used if NEXT_PUBLIC_USE_ARBITRUM_SEPOLIA=true — otherwise local Anvil is the dev default.
 */
export const robinhoodTestnetChain = defineChain({
  id: Number(process.env.NEXT_PUBLIC_ROBINHOOD_TESTNET_CHAIN_ID || 4663),
  name: "Robinhood Chain Testnet",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: [process.env.NEXT_PUBLIC_ROBINHOOD_TESTNET_RPC_URL || "https://TODO-testnet.example"] },
  },
  testnet: true,
});

export const localChain = anvil;

export const isLocalDev = process.env.NEXT_PUBLIC_CHAIN_ENV === "local" || !process.env.NEXT_PUBLIC_CHAIN_ENV;
