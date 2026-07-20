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
