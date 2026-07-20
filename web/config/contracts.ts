import type { Address } from "viem";
import { gameEngineAbi, gameTokenAbi, rewardsDistributorAbi, aumStakingAbi, fundNftAbi } from "./abis";

const ZERO: Address = "0x0000000000000000000000000000000000000000" as Address;

function envAddress(key: string): Address {
  const v = process.env[key];
  return (v && v.length === 42 ? v : ZERO) as Address;
}

/**
 * Single source of truth for deployed contract addresses. All zero (unset) until
 * script/Deploy.s.sol has actually run against a target network and the addresses are filled
 * into .env.local — see .env.example. Screens should treat ZERO as "not deployed yet" and show
 * an empty/disabled state rather than attempting calls.
 */
export const contracts = {
  fundNFT: { address: envAddress("NEXT_PUBLIC_FUND_NFT_ADDRESS"), abi: fundNftAbi },
  gameToken: { address: envAddress("NEXT_PUBLIC_GAME_TOKEN_ADDRESS"), abi: gameTokenAbi },
  gameEngine: { address: envAddress("NEXT_PUBLIC_GAME_ENGINE_ADDRESS"), abi: gameEngineAbi },
  rewardsDistributor: {
    address: envAddress("NEXT_PUBLIC_REWARDS_DISTRIBUTOR_ADDRESS"),
    abi: rewardsDistributorAbi,
  },
  aumStaking: { address: envAddress("NEXT_PUBLIC_AUM_STAKING_ADDRESS"), abi: aumStakingAbi },
} as const;

export function isDeployed(address: Address): boolean {
  return address !== ZERO;
}

export enum FundStatus {
  Active = 0,
  MarginCalled = 1,
  Liquidated = 2,
}

export const FUND_STATUS_LABEL: Record<FundStatus, string> = {
  [FundStatus.Active]: "ACTIVE",
  [FundStatus.MarginCalled]: "MARGIN CALLED",
  [FundStatus.Liquidated]: "LIQUIDATED",
};
