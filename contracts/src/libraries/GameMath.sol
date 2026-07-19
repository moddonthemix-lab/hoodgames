// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title GameMath
/// @notice Pure math for MARGIN's game loop. All "Wad" values are fixed-point, 1e18 = 1.0.
/// @dev Every constant here is a Phase-1 default from DECISIONS.md and is intended to be
///      tunable pre-launch — see GameEngine/RewardsDistributor for where these are consumed.
library GameMath {
    uint256 internal constant WAD = 1e18;

    /// @notice scoreAdded = newTraders * 1.2 + smallRandom, per MARGIN_SPEC.md section 2.
    uint256 internal constant SCORE_PER_TRADER_WAD = 1.2e18;

    /// @notice Upper bound (exclusive) of the commit-reveal small random term, in Wad.
    uint256 internal constant SMALL_RANDOM_MAX_WAD = 0.5e18;

    /// @notice Desk base cost (10 YIELD) and per-desk escalation factor (1.15x geometric).
    uint256 internal constant DESK_BASE_COST = 10;
    uint256 internal constant DESK_COST_GROWTH_WAD = 1.15e18;

    /// @notice Recapitalization base cost and per-trader scaling: cost = BASE * (10 + traders) / 10.
    uint256 internal constant RECAP_BASE_COST_WEI = 0.01 ether;

    /// @notice AUM -> reward multiplier curve: 1x + sqrt(aum) * K, capped at MAX_AUM_MULTIPLIER_WAD.
    uint256 internal constant AUM_MULTIPLIER_K_WAD = 0.02e18;
    uint256 internal constant MAX_AUM_MULTIPLIER_WAD = 3e18;

    /// @notice newTraders = min(surplusCapital / 2, openDeskSeats), per MARGIN_SPEC.md section 2.
    function computeNewTraders(uint256 surplusCapital, uint256 openDeskSeats) internal pure returns (uint256) {
        return Math.min(surplusCapital / 2, openDeskSeats);
    }

    /// @notice scoreAdded for a rebalance, in Wad. `smallRandomWad` must already be in [0, SMALL_RANDOM_MAX_WAD).
    function computeScoreAdded(uint256 newTraders, uint256 smallRandomWad) internal pure returns (uint256) {
        return newTraders * SCORE_PER_TRADER_WAD + smallRandomWad;
    }

    /// @notice Maps a raw random word (e.g. keccak256 of a revealed secret) into [0, SMALL_RANDOM_MAX_WAD).
    function scaleSmallRandom(uint256 rawRandomWord) internal pure returns (uint256) {
        return rawRandomWord % SMALL_RANDOM_MAX_WAD;
    }

    /// @notice YIELD cost to build the (deskCount+1)-th desk, geometric escalation, rounded to nearest integer.
    function computeDeskCost(uint256 deskCount) internal pure returns (uint256) {
        uint256 growth = wadPow(DESK_COST_GROWTH_WAD, deskCount);
        return (DESK_BASE_COST * growth + WAD / 2) / WAD;
    }

    /// @notice ETH cost to recapitalize (clear a margin call) for a fund with `traders` traders.
    function computeRecapCost(uint256 traders) internal pure returns (uint256) {
        return (RECAP_BASE_COST_WEI * (10 + traders)) / 10;
    }

    /// @notice Reward-weighting multiplier from staked AUM, in Wad (1e18 = 1.0x), capped at MAX_AUM_MULTIPLIER_WAD.
    /// @dev `aumWad` is the staked $MGN amount (18 decimals). Multiplier = 1x + sqrt(aum) * K, capped.
    function computeAumMultiplier(uint256 aumWad) internal pure returns (uint256) {
        // sqrtWad(x) = sqrt(x * 1e18) so the result stays in 1e18 fixed-point terms.
        uint256 sqrtWad = Math.sqrt(aumWad * WAD);
        uint256 bonus = (sqrtWad * AUM_MULTIPLIER_K_WAD) / WAD;
        uint256 multiplier = WAD + bonus;
        return Math.min(multiplier, MAX_AUM_MULTIPLIER_WAD);
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
