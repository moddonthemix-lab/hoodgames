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
addresses into `.env.local` — **until then every screen shows a "DEMO DATA" banner and renders
with realistic fake data instead of the bare "not deployed" placeholder** (`lib/demoData.ts`,
checked via `config/contracts.ts`'s `isDeployed`), so you can see and click through the actual UI
before anything is deployed. Write actions (Rebalance, Mint, Attack, Claim, etc.) are disabled in
this state — there's nothing to send a transaction to yet.

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
| `app/(app)/fund` | My Fund dashboard — countdown centerpiece, resource claims, and desk building all on one screen, matching Stoke Fire's Village screen (Stoke Fire + Chop Wood + Gather Food + Build stacked together). |
| `components/FundPulse.tsx` | The visual centerpiece replacing Stoke Fire's fire — an animated ticker/chart (green uptrend healthy, red jagged downtrend margin-called, flat grey liquidated), pure SVG. |
| `app/(app)/takeovers` | Attack flow. |
| `app/(app)/rewards` | Claim (full/partial), withdraw, geo-gated Convert step. |
| `app/(app)/leaderboard` | Score ranks. |
| `app/api/geo/route.ts` | Server-side country check gating the Convert step (US hidden). Tries CDN geo headers first (Vercel/Cloudflare), falls back to an IP-based lookup — see its own header comment, this is what actually runs on Railway. |
| `lib/demoData.ts`, `components/DemoBanner.tsx`, `components/ActivityFeed.tsx` | Fake-but-realistic data shown when contracts aren't deployed, so the UI is actually explorable pre-deploy — see "Setup" above. The Activity feed (mirrors Stoke Fire's Activity tab) is demo-only everywhere for now, not just pre-deploy, since it isn't wired to real on-chain events yet. |

## Deploying to Railway

`railway.json` is already set up (Nixpacks builder, `npm run build` / `npm run start` — Next.js
reads Railway's `PORT` automatically, nothing else to configure there).

1. Create a Railway project from this repo, root directory `web/`.
2. Set environment variables in Railway's dashboard **before the first deploy** — `NEXT_PUBLIC_*`
   vars are baked in at build time, so adding/changing one after the fact requires a rebuild, not
   just a restart. At minimum:
   - `NEXT_PUBLIC_CHAIN_ENV` — set to anything other than `local` (or unset it) once you have a
     real network to point at; left as `local`/unset it'll target Anvil, which doesn't exist on
     Railway.
   - `NEXT_PUBLIC_GAME_ENGINE_ADDRESS` and the other four `NEXT_PUBLIC_*_ADDRESS` vars, once
     `contracts/script/Deploy.s.sol` has actually run somewhere.
   - `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` — get one free at cloud.walletconnect.com; without it
     WalletConnect (mobile wallet) connections silently fail, browser-extension wallets still work.
   - See `.env.example` for the full list (Robinhood Chain RPC URLs, etc.).
3. Deploy. Railway auto-detects the Next.js app via Nixpacks.

**Geo-gate on Railway specifically**: `/api/geo` needs to know the visitor's country to gate the
Convert step. Railway doesn't set Vercel's or Cloudflare's geo headers, so the route falls back to
looking up the client IP (from Railway's `x-forwarded-for`) against ip-api.com — free, no API key,
works out of the box. See the file's header comment for the caveats (HTTP-only free tier, ~45
req/min rate limit, in-memory per-instance cache) and the upgrade path (MaxMind/paid API) once
this needs to hold up under real traffic. If you later put Cloudflare in front of Railway instead,
`cf-ipcountry` will be picked up automatically and the IP-lookup fallback won't even run.

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
