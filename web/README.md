# MARGIN web — Phase 3

Next.js 14 App Router + TypeScript + Tailwind + wagmi v2 + viem + RainbowKit. See
`/MARGIN_SPEC.md` (source of truth) and `/DECISIONS.md` at the repo root.

## Setup

```bash
npm install
cp .env.example .env.local   # fill in contract addresses once deployed, see below
npm run dev
```

Defaults to targeting local Anvil (`NEXT_PUBLIC_CHAIN_ENV=local`). Nothing will actually work
end-to-end until `contracts/script/Deploy.s.sol` has run somewhere and you copy its output
addresses into `.env.local` — until then every screen shows a "Contracts not deployed yet"
state rather than crashing (checked via `config/contracts.ts`'s `isDeployed`).

## What's here

| Path | Purpose |
|---|---|
| `config/chains.ts` | Robinhood Chain + testnet fallback + local Anvil, RPC URLs from env (TODO placeholders, see file). |
| `config/contracts.ts` | Single typed source of truth for addresses (env-driven) + the `FundStatus` enum. |
| `config/abis.ts` | Hand-authored ABIs — **see the caveat in that file**, there's no compiled artifact JSON to generate these from yet (forge unavailable in the session that wrote this). Re-generate from `forge build` output once available. |
| `lib/wagmi.ts`, `app/providers.tsx` | wagmi + RainbowKit + TanStack Query wiring. |
| `lib/commitReveal.ts` | Client-side commit-reveal secret management — **read this file**, it explains a real UX limitation: secrets live only in `localStorage`. |
| `lib/useMyFund.ts` | Same limitation for "which fund do I own" — FundNFT has no Enumerable extension, so this is also localStorage-tracked. Both are flagged as things a production build should replace with an indexer. |
| `components/AppShell.tsx`, `BottomNav.tsx`, `TopBar.tsx`, `TickerTape.tsx` | Shared mobile-first shell (bottom tab nav + top bar), styled per the Bloomberg-terminal-meets-degen theme in `tailwind.config.ts`. |
| `app/page.tsx` | Landing — pitch, live stats, mint. |
| `app/(app)/fund` | My Fund dashboard — the countdown centerpiece. |
| `app/(app)/build` | Desks + resource claims. |
| `app/(app)/takeovers` | Attack flow. |
| `app/(app)/rewards` | Claim (full/partial), withdraw, geo-gated Convert step. |
| `app/(app)/leaderboard` | Score ranks. |
| `app/api/geo/route.ts` | Server-side country check gating the Convert step (US hidden). Reads CDN geo headers — **has a TODO for self-hosted deploys without Vercel/Cloudflare in front**. |

## Two contract additions made during this phase

`FundNFT.totalMinted()`, `GameEngine.recapCost()`, and `GameEngine.nextDeskCost()` were added to
`contracts/src/` while building this frontend — small, purely-additive view functions with no
state-mutation risk, needed so the UI can show live counts/costs without an indexer. Logged in
`/DECISIONS.md`.

## Verification status

Ran `npm run dev`, hit all 6 routes with Playwright (headless Chromium), confirmed no React
errors/crashes and that the theme renders as intended — screenshots reviewed manually. **Not**
verified: the connected-wallet + deployed-contract code paths (stat chips, live countdown, claim
flows), since that needs a running chain with the contracts actually deployed — blocked on the
same `forge`/`anvil` unavailability as Phase 2. Re-verify those once you can run
`anvil` + `forge script Deploy.s.sol --broadcast` locally.

## Known limitations to fix before this is production-ready

- **Commit-reveal secrets and fund-ownership tracking live only in browser localStorage.** Losing
  it means losing the ability to rebalance/attack from that browser. Needs either an indexer (to
  recover "which tokenId do I own" from FundNFT Transfer events) or a redesign that doesn't
  require client-held secrets at all.
- ABIs are hand-transcribed from the Solidity source, not generated from compiled artifacts.
- "Browse funds" (Takeovers) and "Leaderboard" only look at the most recent 20/50 token IDs —
  fine for early testnet, not for real scale. Needs an indexer/subgraph.
- WalletConnect project ID is a placeholder — get a real one at cloud.walletconnect.com.
- Router/Stock Token addresses for the Convert step are not wired up (Phase 4 work per the spec).
