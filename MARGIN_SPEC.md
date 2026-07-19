# MARGIN — Onchain Fund Survival Game

> **Working title:** MARGIN (rename freely). Elevator pitch: *Run an onchain fund. Rebalance every 3 days or get margin called. Farm the token, stake it as AUM, earn real ETH from everyone else's activity, and choose your payout asset. Get liquidated and lose everything.*
>
> Inspired by Stoke Fire (stokefire.xyz) — same proven survival-idle loop, rebuilt with a finance theme, a dual-currency economy (farmed token + real ETH yield), and RWA payout options. Deployed on **Robinhood Chain**.

---

## 1. Chain & Environment

| Item | Value |
|---|---|
| Chain | Robinhood Chain (Arbitrum Orbit L2) |
| Chain ID | 4663 |
| Gas token | ETH (native) |
| EVM | Fully EVM-compatible, Solidity works as-is |
| Block time | ~100ms |
| DEX | Uniswap (dedicated AMM on-chain) — used for $TOKEN liquidity AND optional payout swaps |
| Oracles | Chainlink (Data Streams available for Stock Token pricing) |
| Explorer | Blockscout |
| Compliance | Chainalysis KYT monitors all transactions — design must stay clean |

**IMPORTANT:** Verify current RPC URLs, Uniswap router/factory addresses, and Stock Token contract addresses from official Robinhood Chain developer docs at build time. Do not hardcode guessed addresses. Build against a local fork / testnet first.

---

## 2. Core Game Loop (Stoke Fire mechanics → finance theme)

| Stoke Fire | MARGIN | Notes |
|---|---|---|
| Village NFT | **Fund NFT** (ERC-721) | Minted on game start. Represents your fund. |
| Stoke the fire (every 3 days) | **Rebalance** (every 72h) | Costs 3 YIELD + burns $TOKEN. Miss it → drawdown. |
| Fire burns out → revive embers | **Margin call → pay to recapitalize** | 72h grace after missed rebalance. Cost scales with trader count. |
| NFT burned after 4 days dead | **Liquidation** — Fund NFT burned | Permanent. Accrued ETH rewards paid out on liquidation. |
| Villagers | **Traders** | Drive score. |
| Huts (5 villagers, 10 wood, escalating) | **Desks** (5 traders each, 10 YIELD, escalating cost) | |
| Food (1 per villager per stoke) | **Payroll** (1 CAPITAL per trader per rebalance) | Can't make payroll → traders quit, score drops. |
| Wood / food gathering | **YIELD + CAPITAL** resources | Passive accrual + active claim actions. |
| Battles / raids | **Hostile Takeovers** | Attack another fund, steal % of unclaimed rewards, risk losing traders. |
| Score formula | Same shape | `newTraders = min(surplusCapital / 2, openDeskSeats)`; `scoreAdded = newTraders * 1.2 + smallRandom` |
| Redeem rewards → village resets to 0 | **Full redemption resets fund** + **partial redemption option** | Partial: redeem 50% of accrued ETH, take score haircut + cooldown (improvement over Stoke Fire's all-or-nothing). |

### Timing
- **Epoch = 72 hours.** Rebalance window is per-fund (rolling from last rebalance), like Stoke Fire.
- Rewards pool sweep + fee conversion batched **once per epoch** ("Payday" event — visible pool growth, claimable balances tick up).

---

## 3. Economy — Dual Track

### Track 1: $TOKEN (farmable game token, ERC-20)
- **Supply:** 10,000,000, fully minted at TGE. Suggested split: 90% → Uniswap LP (dev seeds ETH), 3% dev, 7% airdrop (targeted at trading/fintwit/TikTok audience).
- **Tax:** 5% on buy/sell → **1% dev / 3% players (rewards pool) / 1% LP**. Tax rate ownable + lowerable, never raisable above 5%.
- **Emissions:** Traders generate P&L each epoch, paid partly in $TOKEN (this is the "farming").
- **Sinks (all burn):** rebalance cost, desk construction premium, takeover entry stake, recapitalization (revival) cost. Target: net-deflationary at healthy activity.
- Contract lineage reference: Stoke Fire forked Fren Pet / Unibot tax-token contracts. Use a modern audited tax-token pattern, not a blind fork.

### Track 2: Real ETH yield (the retention engine)
Rewards pool accrues ETH from:
1. 3% player share of $TOKEN tax volume
2. Small ETH action fees (fund mint, takeover initiation, claim fee)
3. Recapitalization penalties (a cut of every margin-call payment redistributes to surviving funds)
4. Fund NFT secondary royalties (if marketplace supports)

Distribution: pro-rata by `fundScore / totalScore`, accrued continuously, realized on redemption (full reset) or partial redemption (haircut + cooldown).

### Connective tissue: AUM Staking
- Players stake farmed $TOKEN into their fund as **AUM**.
- Staked AUM → score multiplier → larger share of the ETH pool.
- Unstake = cooldown (e.g. 7 days) or exit fee (fee → rewards pool).
- Purpose: gives emissions a lock destination instead of dump-on-sight (GMX-style real-yield loop).

---

## 4. Payouts & RWA Option (compliance-critical — do not deviate)

- **The protocol only ever pays ETH.** Claim functions transfer ETH. No contract ever holds, swaps into, or delivers Stock Tokens.
- The frontend MAY show an optional **"Convert payout"** step after claim: a standard Uniswap router swap (ETH → chosen Stock Token e.g. NVDA/AAPL/TSLA) **signed and executed by the user from their own wallet**. The app is a frontend to Uniswap; eligibility is enforced by the Stock Token's own transfer restrictions.
- **Geo-gate the convert UI: hidden for US users.** Stock Tokens are not available in the US and are structured as debt securities. Default payout everywhere = ETH.
- Marketing may say "get paid in the assets you choose" — the mechanic is always ETH-out + user-signed swap.
- ⚠️ Legal review of the final token + tax + payout structure by a crypto securities attorney is required before mainnet. This spec is a design document, not legal clearance.

---

## 5. Smart Contract Architecture

```
contracts/
├── FundNFT.sol            // ERC-721. Mint (small ETH fee), metadata (score, traders,
│                          //   desks, AUM, lastRebalance), burn-on-liquidation.
├── GameToken.sol          // ERC-20 w/ 5% buy/sell tax (1/3/1 split), burn(), 
│                          //   AMM-pair detection, tax exemptions for game contracts.
├── GameEngine.sol         // Core loop: rebalance(), resource accrual (YIELD/CAPITAL),
│                          //   buildDesk(), payroll check, trader growth/attrition,
│                          //   score math, marginCall state machine, recapitalize(),
│                          //   liquidate(), takeover(), epoch clock.
├── RewardsDistributor.sol // ETH pool. Receives tax share + action fees + penalties.
│                          //   Index-based pro-rata accrual by score (Synthetix-style
│                          //   rewardPerScore accumulator — O(1) per user).
│                          //   claim(): full redemption (reset) or partial (50%,
│                          //   score haircut, cooldown).
├── AUMStaking.sol         // Stake $TOKEN per-fund → score multiplier. Cooldown or
│                          //   exit-fee on unstake.
└── Treasury.sol           // Dev fee collection, epoch sweep: collect fees → 
│                          //   (already ETH; swap any $TOKEN dust) → top up Distributor.
```

**Key invariants:**
- Score accounting and reward accrual must use an accumulator pattern (no loops over players).
- All state transitions (alive → drawdown → margin-called → liquidated) enforced by timestamps, callable permissionlessly (keeper-friendly), with anyone able to trigger `liquidate()` on an expired fund (small ETH bounty to caller).
- Randomness for `smallRandom` in score: use commit-reveal or Chainlink VRF if available on-chain; NEVER blockhash-only for anything of value.
- Reentrancy guards on all ETH-transfer paths. Pull-payment pattern for claims.
- Pausable + timelocked owner for launch phase; document every privileged function.

---

## 6. Frontend

- **Stack:** Next.js 14+ (App Router), TypeScript, Tailwind, wagmi v2 + viem, RainbowKit (or ConnectKit), TanStack Query.
- **Screens:**
  1. **Landing** — pitch, live global stats (total funds, TVL in AUM, ETH distributed), mint CTA.
  2. **My Fund (dashboard)** — the tamagotchi screen: countdown to next required rebalance (big, anxiety-inducing), traders/desks/AUM, score, accrued ETH, one-tap Rebalance.
  3. **Build** — desks, resource claims.
  4. **Takeovers** — browse target funds, attack flow, history.
  5. **Rewards** — accrued ETH, claim (full/partial), optional geo-gated Convert step (user-signed Uniswap swap).
  6. **Leaderboard** — score ranks, season timer.
- **Design language:** Bloomberg-terminal-meets-degen. Dark, monospace numerals, green/red P&L colors, ticker tape. Margin-call states should feel genuinely alarming (red alerts, countdowns).
- Mobile-first — this is a check-in-every-3-days game; most sessions will be phones.
- Geo-gating: IP-based country check server-side (API route) controlling visibility of the Convert step only. Game itself is global.

---

## 7. Launch Plan (phases)

1. **Phase 0 — Local:** contracts + full test suite on local fork. 100% of game math covered by tests incl. fuzz tests on score/reward accounting.
2. **Phase 1 — Testnet:** deploy to Robinhood Chain testnet (or Arbitrum Sepolia if RH testnet unavailable), frontend pointed at it, private playtest.
3. **Phase 2 — Audit + legal:** at minimum a thorough review (Slither/Aderyn + manual), ideally a paid audit of GameToken + RewardsDistributor. Securities attorney review of token/tax/payout structure.
4. **Phase 3 — Mainnet:** deploy contracts → seed LP → airdrop claim live → open minting. Season 1 starts with a fee-funded prize pool.

## 8. Revenue (dev)
- 3% supply allocation
- 1% of all $TOKEN trading volume (tax)
- LP fees on seeded position
- Cut of ETH action fees
- NFT royalties

## 9. Out of scope for v1 (backlog)
Syndicates (team funds), seasonal resets with prize pools, live-market position picking (long/short an asset per epoch for a score multiplier — big differentiator, add in Season 2), Farcaster frame integration, $TOKEN governance.
