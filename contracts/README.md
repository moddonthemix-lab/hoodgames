# MARGIN contracts — Phase 1

Foundry-layout Solidity project. See `/MARGIN_SPEC.md` (source of truth) and `/DECISIONS.md`
(every parameter/architecture choice + rationale) at the repo root.

## Setup

```bash
npm install                      # pulls @openzeppelin/contracts (remapped, see foundry.toml)
forge install foundry-rs/forge-std --no-commit   # once you have forge with full GitHub access
forge build
forge test
```

`forge` itself was not installable in the session that wrote Phase 1 — see DECISIONS.md's
"forge itself could not be installed" entry. Until then, `node compile-check.js` does a
best-effort syntax/type check of `src/` with npm `solc` (not a substitute for `forge build`/`forge test`).

## What's here (Phase 1 — contracts core)

| File | Purpose |
|---|---|
| `src/FundNFT.sol` | ERC-721 identity token. No gameplay state — reads it from GameEngine. |
| `src/GameToken.sol` | $MGN, 5% buy/sell tax (1% dev / 3% players / 1% LP), fixed 10M supply, no mint(). |
| `src/GameEngine.sol` | Core loop: mint, rebalance, buildDesk, recapitalize, liquidate, takeover. Sole source of truth for fund state. |
| `src/RewardsDistributor.sol` | ETH pool, index-based accumulator keyed by tokenId, full/partial claim, pull-payment. |
| `src/AUMStaking.sol` | Stake $MGN per fund → reward-share multiplier (not leaderboard score). |
| `src/Treasury.sol` | Tax sweep, $MGN→ETH conversion, LP re-deepening, recap-penalty revenue. |
| `src/libraries/GameMath.sol` | All pure formulas (score, desk cost, AUM multiplier, recap cost). |
| `src/interfaces/` | Cross-contract interfaces. |
| `script/Deploy.s.sol` | Deploys + wires everything in dependency order. Needs forge-std. |
| `script/config/NetworkConfig.sol` | TODO placeholders for Robinhood Chain addresses — see its NatSpec for exactly which docs pages to pull them from. |

## Not yet done (Phase 2+)

- Test suite (unit, fuzz, integration "life of a fund", liquidation-race).
- Slither/Aderyn static analysis.
- Owner should be an OZ `TimelockController` (48h delay) before any real deploy — not wired
  automatically by `Deploy.s.sol`, see its NatSpec.
- Real Uniswap/Chainlink/Stock Token addresses for Robinhood Chain.
