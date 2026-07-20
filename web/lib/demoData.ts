import { FundStatus } from "@/config/contracts";

/**
 * Realistic-looking fake data shown whenever contracts aren't deployed (config/contracts.ts's
 * `isDeployed` is false), so the UI can actually be seen/tested without a live chain. Every
 * number here is fictional — this never touches the real contracts, and every screen using it
 * shows a "DEMO DATA" banner (components/DemoBanner.tsx) so it's never mistaken for live state.
 */

const nowSec = Math.floor(Date.now() / 1000);
const WAD = 10n ** 18n;

export const DEMO_EPOCH_LENGTH = 72n * 3600n;
export const DEMO_MARGIN_CALL_GRACE = 72n * 3600n;

export const DEMO_FUND = {
  traders: 34,
  desks: 3,
  lastRebalance: BigInt(nowSec - 40 * 3600), // rebalanced 40h ago -> ~32h left on a 72h clock
  marginCalledAt: BigInt(nowSec - 40 * 3600) + DEMO_EPOCH_LENGTH,
  score: 18740n * WAD, // 18,740.0
  yieldBalance: 42n,
  capitalBalance: 68n,
  pendingTokenRewards: 0n,
  status: FundStatus.Active,
};

export const DEMO_FUND_MARGIN_CALLED = {
  ...DEMO_FUND,
  lastRebalance: BigInt(nowSec - 80 * 3600), // 80h ago -> past the 72h deadline
  marginCalledAt: BigInt(nowSec - 80 * 3600) + DEMO_EPOCH_LENGTH,
  status: FundStatus.MarginCalled,
};

export const DEMO_AUM = 12_500n * WAD;
export const DEMO_EARNED_ETH = 876n * 10n ** 15n; // 0.876 ETH
export const DEMO_WITHDRAWABLE_ETH = 210n * 10n ** 15n; // 0.21 ETH
export const DEMO_RECAP_COST = 12n * 10n ** 15n; // 0.012 ETH
export const DEMO_NEXT_DESK_COST = 19n; // YIELD
export const DEMO_PENDING_YIELD = 6n;
export const DEMO_PENDING_CAPITAL = 9n;

export const DEMO_MINT_FEE = 1n * 10n ** 15n; // 0.001 ETH
export const DEMO_TOTAL_FUNDS = 128n;
export const DEMO_TVL_AUM = 842_300n * WAD;
export const DEMO_REWARD_POOL_ETH = 14n * 10n ** 18n + 217n * 10n ** 15n; // 14.217 ETH
export const DEMO_TOTAL_SCORE = 2_140_650n * WAD;

export const DEMO_TAKEOVER_STAKE = 20n * WAD;
export const DEMO_TAKEOVER_IMMUNITY = 24n * 3600n;

export const DEMO_LEADERBOARD = [
  { id: 41n, score: 92_400n * WAD, owner: "0x7a3F2b9c1D4e5F6a7B8c9D0e1F2a3B4c5D6e7F8a", traders: 61 },
  { id: 7n, score: 78_150n * WAD, owner: "0x1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6E7f8A9b0C", traders: 55 },
  { id: 128n, score: 61_800n * WAD, owner: "0x9F8e7D6c5B4a3F2e1D0c9B8a7F6e5D4c3B2a1F0e", traders: 48 },
  { id: 19n, score: 44_200n * WAD, owner: "0x4D5e6F7a8B9c0D1e2F3a4B5c6D7e8F9a0B1c2D3e", traders: 39 },
  { id: 87n, score: 18_740n * WAD, owner: "0x2E3f4A5b6C7d8E9f0A1b2C3d4E5f6A7b8C9d0E1f", traders: 34 },
] as const;

/**
 * Stoke Fire's Activity tab (a live feed of other players' actions) is a big part of what makes
 * it feel alive, and MARGIN doesn't have a real equivalent yet — this is demo-only until it's
 * wired to real GameEngine/RewardsDistributor events (Rebalanced, DeskBuilt, TakeoverExecuted,
 * FundLiquidated, Claimed) once contracts are deployed somewhere queryable.
 */
export const DEMO_ACTIVITY = [
  { text: "Fund #41 rebalanced — 61 traders, +73.4 score", minutesAgo: 2 },
  { text: "Fund #7 attacked Fund #19, stole 0.31 ETH", minutesAgo: 8 },
  { text: "Fund #128 built desk #4", minutesAgo: 12 },
  { text: "Fund #19 was margin called", minutesAgo: 22 },
  { text: "Fund #87 claimed 0.88 ETH (full redemption)", minutesAgo: 31 },
  { text: "Fund #55 minted", minutesAgo: 44 },
  { text: "Fund #41 attacked Fund #33, defender lost 1 trader", minutesAgo: 58 },
  { text: "Fund #12 recapitalized after missing its rebalance", minutesAgo: 71 },
] as const;

export const DEMO_TAKEOVER_TARGETS = [
  { id: 41n, score: 92_400n * WAD, traders: 61, immune: false },
  { id: 7n, score: 78_150n * WAD, traders: 55, immune: true },
  { id: 128n, score: 61_800n * WAD, traders: 48, immune: false },
  { id: 19n, score: 44_200n * WAD, traders: 39, immune: false },
] as const;
