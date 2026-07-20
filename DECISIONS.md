# MARGIN — Decisions Log

Running log of every parameter/architecture choice, so we can tune before launch.
Format: `[date] Decision — rationale`

## 2026-07-19 — Project bootstrap
- Spec placed at `/MARGIN_SPEC.md` (source of truth). Monorepo: `/contracts` (Foundry), `/web` (Next.js), `/scripts`.
- Working name kept as **MARGIN**, token symbol **$MGN** for now — purely cosmetic, trivial to rename later (single constant in GameToken.sol + frontend copy). Revisit before mainnet.

## 2026-07-19 — AUM multiplier scope: reward-weight only
- Leaderboard `score` (Fund.score) stays pure trader-growth (`newTraders*1.2 + smallRandom`), unaffected by staking.
- `RewardsDistributor` tracks a separate `weightedScore = score * aumMultiplier(fund) / 1e18` used ONLY for ETH pool pro-rata share.
- Rationale: keeps the leaderboard skill-based (can't buy rank with capital), while still giving AUM stakers a real yield boost — matches GMX-style real-yield design goal in spec §3.
- Interactive question tool was unavailable this session; proceeding with this as the recommended default. Flag if you want unified score instead — it's a moderate refactor (one field instead of two, `notifyScoreChange` signature changes), best done now rather than after Phase 2 tests are written.

## 2026-07-19 — Phase 1 economic constants (DEFAULTS — all owner-adjustable, tune before testnet)

| Constant | Default | Notes |
|---|---|---|
| Epoch length | 72h | Fixed per spec |
| Margin-call grace | 72h | Fixed per spec |
| Rebalance cost | 3 YIELD + burn 5 $MGN | Burn amount is new — spec didn't specify |
| Payroll | 1 CAPITAL / trader / rebalance | Fixed per spec |
| Desk size | 5 traders/desk | Fixed per spec |
| Desk base cost | 10 YIELD | Fixed per spec |
| Desk cost escalation | `cost = 10 * 1.15^deskCount` YIELD (rounded) | Geometric, mirrors Stoke Fire hut scaling |
| newTraders formula | `min(surplusCapital/2, openDeskSeats)` | Fixed per spec |
| scoreAdded | `newTraders*1.2 + smallRandom` (smallRandom ∈ [0, 0.5), commit-reveal) | Fixed shape per spec; random range is new |
| Recapitalization cost | `0.01 ETH * (1 + traders/10)` | "scales with trader count" per spec; ETH not $MGN since it must fund the redistribution penalty (§3 Track 2 item 3) |
| Recap penalty split | 70% → RewardsDistributor pool, 30% → Treasury | New — spec says "a cut... redistributes to surviving funds" |
| Takeover entry stake | 20 $MGN (burned) | New |
| Takeover steal % | 10% of defender's unclaimed accrued ETH | Spec says "steal % of unclaimed rewards" |
| Takeover trader risk | attacker wins → 5% chance defender loses 1 trader | "risk losing traders" per spec |
| Takeover cooldown | defender immune 24h after being attacked | New — prevents pile-on |
| AUM multiplier curve | `1e18 + sqrt(aum) scaled` (diminishing returns) capped at 3x | New — placeholder, needs real tuning/design pass with a spreadsheet before launch |
| AUM unstake cooldown | 7 days | Per spec suggestion |
| AUM unstake exit-fee alt | 5% (if user skips cooldown) → burned | New, optional path per spec "cooldown OR exit fee". Burned rather than routed to RewardsDistributor: the fee is collected in $MGN, and RewardsDistributor only ever holds/pays ETH (MARGIN_SPEC.md section 4 compliance rule) — burning is simpler than adding a $MGN→ETH swap path for this one sink, and still benefits all stakers via deflation (GameToken sinks are already "target: net-deflationary" per spec section 3). |
| Partial redemption | 50% of accrued ETH, remaining 50% forfeited to pool; score haircut 50%; 24h cooldown before next partial/full | Per spec shape; exact haircut/cooldown numbers new |
| Fund mint fee | 0.001 ETH | New — small anti-spam fee to RewardsDistributor |
| Liquidation bounty | 0.0005 ETH to caller | New — keeper incentive, paid from the liquidated fund's forfeited stake or Treasury |
| $TOKEN P&L emission per epoch | `0.5 $MGN * traders` paid to fund's claimable YIELD-adjacent balance, minted from a capped emissions budget (not infinite mint — see below) | **Biggest open item.** See note below. |

### Emission rate — needs a real decision before Phase 1 is "final" (not blocking struct design)
Spec section 3 says traders generate P&L "paid partly in $TOKEN" but total supply is fixed at 10,000,000 (fully minted at TGE, 90/3/7 split). There is **no mint function** implied anywhere else — GameToken is described as fully-minted-at-TGE. So epoch "emissions" to players must come from an already-allocated pool, not inflation. Proposed resolution: carve a portion of the LP/dev allocation (or a new 4th bucket) into a **GameRewardsPool** of $MGN that GameEngine pays out from on each epoch (capped, decreasing over time or simply capped at pool balance — payouts silently stop/scale down when pool is empty, no inflation). Default proposed split: **90% LP / 3% dev / 5% airdrop / 2% GameRewardsPool** (shrunk airdrop by 2pp vs spec's 7% to fund it) — flag if you'd rather shrink LP or dev instead, or mint a small ongoing emission (would require reopening the "fully minted at TGE" decision).
- Placeholder used in Phase 1 code: `GameEngine` pulls from a `$MGN` balance held by itself (funded at deploy time from the GameRewardsPool allocation), pays out `0.5 * traders` $MGN per rebalance capped at its own balance. Fully adjustable/replaceable later.

## 2026-07-19 — Stoke Fire reference check
Fetched stokefire.xyz/docs directly to sanity-check the spec's mapping table. Confirmed match: growth formula (`min(surplusFood/2, hutSpace)`), score formula (`newVillagers*1.2 + smallRandom`), and "rewards realize only on reset" are all faithfully carried into MARGIN_SPEC.md. Stoke Fire's reward pool draws 2% of $FIRE volume (MARGIN uses 3%, per spec). Stoke Fire's "Battles" page exists in nav but has no published mechanics — so the Takeover numeric defaults above (20 $MGN stake, 10% steal, 5% trader-loss chance, 24h immunity) are original to this project, not ported from a reference, and should be treated as the least-validated defaults in this table.

## 2026-07-19 — Compile sanity check + Cancun EVM assumption
Ran `node compile-check.js` (npm `solc` 0.8.24, since `forge` itself isn't installable in this
session — see top of DECISIONS.md / README.md). All 13 `src/` files compile with zero errors and
zero warnings against the OpenZeppelin 5.6.1 remapping. Two things worth flagging:
- OpenZeppelin 5.6.1's `utils/Bytes.sol` (pulled in transitively by `Base64`/`Strings`, used in
  `FundNFT.tokenURI`) uses the `MCOPY` opcode (EIP-5656, Cancun hardfork). `foundry.toml` now sets
  `evm_version = "cancun"` to match. **Assumption, not confirmed:** Robinhood Chain supports Cancun
  opcodes — Arbitrum's ArbOS has supported Cancun since 2024 and Orbit chains typically inherit
  that, but verify for Robinhood Chain specifically before testnet/mainnet deploy. If it doesn't,
  the fix is pinning an older OpenZeppelin 5.x release rather than lowering `evm_version` (the
  MCOPY assembly call itself would still fail to compile against an older EVM target).
- Fixed two real interface/inheritance issues the compiler caught: `FundNFT.ownerOf` and
  `GameToken.burn`/`burnFrom` needed explicit `override(Base, Interface)` since both a concrete
  OZ base contract and this project's own interface declare the same signature — otherwise a
  legitimate ambiguity error, not a Foundry-only quirk. Also added `sweepPendingTax` to
  `IGameToken` (Treasury was calling it through the interface type but the interface didn't
  declare it).
- This check does NOT replace `forge build`/`forge test`: no `via_ir`, no test compilation, no
  Foundry-specific remapping edge cases. Run the real thing wherever `forge` is available.

## 2026-07-20 — Phase 2 complete (test suite written, not executed)
Wrote the full Foundry test suite: `BaseTest.sol` fixture, `GameMath.t.sol` (pure formula unit +
fuzz), `GameEngine.t.sol` (mint/rebalance/buildDesk/recapitalize/liquidate/takeover, incl. a
natural-sequence bootstrap to reach a payroll-shortfall branch without storage cheating),
`RewardsDistributor.t.sol` (mock-isolated accumulator fuzz invariants — monotonic accumulator,
total earned never exceeds total ETH deposited — plus real-stack integration tests),
`AUMStaking.t.sol`, `GameToken.t.sol`, `FundNFT.t.sol`, `LifeOfAFund.t.sol` (the full mint→5x
rebalance→miss→margin-call→recapitalize→redeem flow), and `LiquidationRace.t.sol`. 10 test files,
all pass `node compile-check.js test` (syntax/type check).

Writing these tests found and fixed a real bug in Phase 1: GameEngine's commit-reveal
verification bound the reveal hash to `tokenId`, but `mintFund`'s initial commitment can't be
bound to a tokenId that doesn't exist yet at commit time (the player picks it before minting).
Fixed by dropping tokenId from the verification hash (kept in the *derived* random values, just
not the commitment check itself) — see GameEngine.sol's NatSpec on `rebalance`.

**None of this has been executed.** `lib/forge-std` is vendored locally (fetched from
raw.githubusercontent.com, gitignored) so `forge test` should work immediately once `forge`
itself is available — that remains the actual next step, and it may surface issues this
hand-traced-by-solc-only process couldn't catch (exact rounding behavior, gas, event ordering,
and anywhere my manual arithmetic tracing was simply wrong).

## 2026-07-20 — Phase 3 (frontend) built
Next.js 14 App Router + TypeScript + Tailwind 3 + wagmi v2 (^2.19) + viem 2 + RainbowKit 2, per
the spec's stack. Versions pinned to Next 14.x specifically (not the latest 16/React 19) to match
"Next.js 14+" literally and stay on the well-documented, stable wagmi-v2-era combo the spec asked
for, rather than auto-upgrading to wagmi 3 / React 19 just because they're now "latest".

**Theme**: dark navy-black (`#0a0d14`) base, a violet accent (`#7c6fe0`) carried over from the
Stoke Fire reference screenshots' mauve buttons, green/red (`profit`/`loss`) reserved strictly for
P&L and status semantics per spec section 6, monospace numerals via a `.tabular` utility class.
Bottom tab nav (Fund/Build/Takeovers/Rewards/Leaderboard) + sticky top bar (accrued ETH, screen
title, wallet) mirrors Stoke Fire's card/bottom-nav mobile layout structure.

**Two data-availability gaps, solved differently:**
- "Which fund does this wallet own" and "what's the current commit-reveal secret" — FundNFT has
  no Enumerable extension and secrets never touch the chain until reveal, so both are tracked in
  browser localStorage (`lib/useMyFund.ts`, `lib/commitReveal.ts`). This is a real limitation
  (losing localStorage = losing the ability to act on that fund) flagged in both files' comments
  and in web/README.md — a production build needs an indexer or a contract-level redesign.
- "Total funds minted", "next recap/desk cost" — no indexer needed here, just three small,
  purely-additive view functions added to the contracts during this phase: `FundNFT.totalMinted()`,
  `GameEngine.recapCost()`, `GameEngine.nextDeskCost()`. Zero state-mutation risk, re-ran the solc
  compile check afterward (still 0 errors).

**Geo-gate**: `/api/geo` reads Vercel's `x-vercel-ip-country` / Cloudflare's `cf-ipcountry`
headers rather than calling a third-party geolocation API — zero cost/latency on either platform,
but has a TODO: self-hosting without one of those CDNs in front needs a MaxMind GeoIP2 fallback.
Fails closed (unknown country -> Convert step hidden). Independent global kill switch via
`NEXT_PUBLIC_CONVERT_STEP_ENABLED` (default false) per Phase 4's requirement.

**Dependency snag**: RainbowKit's default wallet set pulls in `@wagmi/connectors`'s Base Account
connector, which transitively requires `@coinbase/cdp-sdk`'s optional `@x402/*` packages
(Coinbase's HTTP-402 payment protocol SDK) that npm didn't install automatically. Installed them
explicitly (`@x402/core`, `@x402/evm`, `@x402/extensions`, `@x402/svm`) rather than hand-rolling a
leaner wallet list, to stay on RainbowKit's supported default path.

**Verified**: `npm run dev` + Playwright (headless Chromium, already present in this sandbox) hit
all 6 routes, confirmed no React crashes/hydration errors and the theme renders as intended.
**Not verified**: connected-wallet + deployed-contract code paths — needs a running chain with
contracts actually deployed, blocked on the same forge/anvil unavailability as Phase 2. Re-check
once `anvil` + `forge script Deploy.s.sol --broadcast` are runnable.

## 2026-07-20 — Phase 2 cleanup: Slither static analysis
`forge`/`anvil` are unavailable in this session (see earlier entries), but Slither itself doesn't
need them — installed via `pip install slither-analyzer` (pypi.org, unlike GitHub, isn't scoped
out of this session) plus a native `solc` via `solc-select install 0.8.24` (downloads from
`binaries.soliditylang.org`, also unaffected). Getting it to actually run took two workarounds
worth recording if this needs repeating:
- crytic-compile auto-detects Foundry from `foundry.toml` and shells out to `forge` even when
  told `--compile-force-framework solc`, so `foundry.toml` had to be moved aside for the run.
- crytic-compile's plain-solc mode only accepts one target, so a throwaway `src/_SlitherAll.sol`
  importing all six concrete contracts was used as the single entrypoint, then deleted — the
  transitive imports pull in everything else.
- Needed `--solc-args "--evm-version cancun"` — same MCOPY/Cancun issue as the npm-solc compile
  check (see earlier entry), crytic-compile's direct solc invocation doesn't read foundry.toml's
  `evm_version`.

Ran with `--filter-paths node_modules` to drop OpenZeppelin-internal noise. 46 results on our own
code. Fixed the real ones:
- **`FundNFT.setGameEngine` had no zero-address check** — and since it's settable only once, a
  zero-address mistake would have permanently bricked minting forever with no recovery path.
  Same fix applied to `GameEngine.setRewardsDistributor` (had the same gap).
- **`Treasury.withdrawTreasuryBalance` had no zero-address check on `to`** — an owner typo would
  burn protocol revenue permanently. Added.
- **Missing events on privileged setters**: `GameEngine.setRewardsDistributor`/`setTreasury` and
  `RewardsDistributor.setGameEngine`/`setAumStaking`/`setFundNFT` now all emit — matches the
  "document every privileged function" bar the rest of the contracts already met.
- **CEI ordering** in `GameEngine.recapitalize` and `RewardsDistributor.claimPartial`: hoisted a
  local state write to before an external call in each. Neither was actually exploitable (both
  functions are `nonReentrant`, and every external call at both sites targets our own trusted
  contracts with no reentrant callback path — verified by reading the callee, not just assumed)
  but it costs nothing to also follow strict checks-effects-interactions.

**Deliberately NOT changed**, with reasoning:
- `rebalance()`/`takeover()`'s internal reentrancy findings — real CEI violations by Slither's
  literal reading, but same story: `nonReentrant`-guarded, external calls only ever hit our own
  `GameToken`/`RewardsDistributor`. Restructuring these functions' internals now risks a subtle
  regression in logic already hand-traced across GameEngine.t.sol/LifeOfAFund.t.sol/
  LiquidationRace.t.sol without being able to re-run those tests to confirm (forge unavailable —
  see above). Not worth the risk for a defense-in-depth-only cleanup. Revisit once `forge test`
  is runnable and can actually confirm a refactor didn't change behavior.
- `Treasury` constructor's missing zero-checks on `_router`/`_lpLockRecipient` — intentional.
  `router` is a confirmed-TODO placeholder (see NetworkConfig.sol) that may legitimately be unset
  at Treasury's deploy time; a zero-address `router` fails loudly the first time `epochSweep`
  actually tries to use it, which is the desired behavior, not a constructor-time guard.
- `divide-before-multiply` in `GameToken._update`'s tax split and `GameMath.wadPow` — inherent to
  bps/fixed-point math (`(a*b)/DENOM` chains), not a bug; same pattern OZ's own `Math.mulDiv` uses
  (also flagged, also fine).
- `elapsed == 0` strict-equality in `_accrueResources` — a pure short-circuit optimization; the
  branch not being taken produces the identical result (0 accrual either way), so there's no
  daylight for a timestamp-manipulating sequencer to exploit here.
- **Confirmed false positive**: `unimplemented-functions` flags `FundNFT.ownerOf` and
  `GameToken.burn`/`burnFrom` as unimplemented. They aren't — both are explicitly implemented via
  `override(ERC721, IFundNFT)` / `override(ERC20Burnable, IGameToken)`, which `compile-check.js`
  already proves compiles (solc would refuse to compile an abstract-but-instantiated contract).
  Looks like a Slither detector limitation with multi-base override resolution across an
  OZ-base + project-interface pair, not a real gap.
- `naming-convention` on `_paramName`-style constructor/setter parameters — intentional, standard
  Solidity practice to avoid shadowing the state variable of the same name.
- Everything else (low-level-calls, timestamp comparisons, assembly-in-OZ, pragma-version-spread,
  dead-code-in-OZ) is either already justified inline via NatSpec or inherent to the design
  (this is a game whose entire mechanic is timestamp-driven state transitions — MARGIN_SPEC.md
  section 5 explicitly requires that).

Re-ran `compile-check.js all` after every fix — still 0 errors.

## Open items carried forward (not blocking Phase 1 contract structure, must resolve before Phase 2/testnet)
- Final tax/emission numbers above need a tokenomics pass (spreadsheet model of supply drain vs sink burn) before testnet.
- Legal review of token/tax/payout structure (spec §4) required before mainnet — unrelated to code correctness.
- Robinhood Chain RPC / Uniswap router+factory / Stock Token addresses: NOT hardcoded, left as TODO placeholders in `contracts/script/config/` and `web/config/`. Pull from official Robinhood Chain developer docs at deploy time.
- **`forge` itself could not be installed in this session** — GitHub access here is scoped to
  `moddonthemix-lab/hoodgames` only, and `foundryup` needs releases from `foundry-rs/foundry`
  which is outside that scope (this is a session policy, not a real network block). All of
  Phase 1 was written and sanity-compiled with npm `solc` instead (see entry above). Before
  Phase 2 (writing/running the Foundry test suite), run in an environment with full GitHub
  access: `curl -L https://foundry.paradigm.xyz | bash && foundryup`, then
  `cd contracts && forge install foundry-rs/forge-std --no-commit && forge build && forge test`.
- Treasury's Uniswap swap calls have no on-chain slippage protection (`minEthOutForPlayers`/
  `minEthOutForLp` are caller-supplied, meant to come from an off-chain keeper's live price
  quote) — fine for Phase 1, but the keeper script (Phase 5) must actually compute real bounds,
  never pass 0.
- Treasury's router interface assumes UniswapV2Router02 shape — confirm against Robinhood
  Chain's actual DEX docs; if it's V3 or a custom AMM, `IUniswapV2Router02Minimal.sol` and
  `Treasury._swapTokensForEth`/`epochSweep` need rewriting.
