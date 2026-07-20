// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title GameMath
/// @notice Pure math for MARGIN's game loop. All "Wad" values are fixed-point, 1e18 = 1.0.
/// @dev Every constant here is a default from DECISIONS.md and is intended to be tunable
///      pre-launch — see GameEngine/RewardsDistributor for where these are consumed.
library GameMath {
    uint256 internal constant WAD = 1e18;

    /// @notice Upper bound (exclusive) of the commit-reveal small random term, in Wad.
    uint256 internal constant SMALL_RANDOM_MAX_WAD = 0.5e18;

    /// @notice Computer base cost (10 YIELD) and per-computer escalation factor (1.15x geometric).
    ///         (Computers were "desks" pre-role-rework — one Computer seats WORKERS_PER_COMPUTER workers.)
    uint256 internal constant COMPUTER_BASE_COST = 10;
    uint256 internal constant COMPUTER_COST_GROWTH_WAD = 1.15e18;

    /// @notice Recapitalization base cost and per-worker scaling: cost = BASE * (10 + workers) / 10.
    uint256 internal constant RECAP_BASE_COST_WEI = 0.01 ether;

    /// @notice AUM staking tiers -> reward-weighting multiplier, capped at 1.5x (per product decision:
    ///         "a certain amount staked -> a certain multiplier, up to 1.5x"). Thresholds are in whole
    ///         $MGN (multiplied by WAD since staked amounts carry 18 decimals). All tunable.
    uint256 internal constant MAX_AUM_MULTIPLIER_WAD = 1.5e18;
    uint256 internal constant AUM_TIER1 = 1_000 ether; // -> 1.1x
    uint256 internal constant AUM_TIER2 = 5_000 ether; // -> 1.2x
    uint256 internal constant AUM_TIER3 = 20_000 ether; // -> 1.3x
    uint256 internal constant AUM_TIER4 = 50_000 ether; // -> 1.4x
    uint256 internal constant AUM_TIER5 = 100_000 ether; // -> 1.5x

    /// @notice Maps a raw random word (e.g. keccak256 of a revealed secret) into [0, SMALL_RANDOM_MAX_WAD).
    function scaleSmallRandom(uint256 rawRandomWord) internal pure returns (uint256) {
        return rawRandomWord % SMALL_RANDOM_MAX_WAD;
    }

    /// @notice YIELD cost to build the (computerCount+1)-th computer, geometric escalation, rounded to nearest int.
    function computeComputerCost(uint256 computerCount) internal pure returns (uint256) {
        uint256 growth = wadPow(COMPUTER_COST_GROWTH_WAD, computerCount);
        return (COMPUTER_BASE_COST * growth + WAD / 2) / WAD;
    }

    /// @notice ETH cost to recapitalize (clear a margin call) for a fund with `workers` total workers.
    function computeRecapCost(uint256 workers) internal pure returns (uint256) {
        return (RECAP_BASE_COST_WEI * (10 + workers)) / 10;
    }

    /// @notice Reward-weighting multiplier from staked AUM, in Wad (1e18 = 1.0x). Discrete tiers,
    ///         capped at 1.5x. Below the first tier a fund is unmultiplied (1.0x).
    /// @param aumWad staked $MGN amount (18 decimals).
    function computeAumMultiplier(uint256 aumWad) internal pure returns (uint256) {
        if (aumWad >= AUM_TIER5) return 1.5e18;
        if (aumWad >= AUM_TIER4) return 1.4e18;
        if (aumWad >= AUM_TIER3) return 1.3e18;
        if (aumWad >= AUM_TIER2) return 1.2e18;
        if (aumWad >= AUM_TIER1) return 1.1e18;
        return WAD;
    }

    /// @notice Wad-fixed-point exponentiation by squaring: (baseWad)^exponent, baseWad in 1e18 terms.
    function wadPow(uint256 baseWad, uint256 exponent) internal pure returns (uint256 result) {
        result = WAD;
        while (exponent > 0) {
            if (exponent & 1 == 1) {
                result = (result * baseWad) / WAD;
            }
            baseWad = (baseWad * baseWad) / WAD;
            exponent >>= 1;
        }
    }
}
