// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {GameMath} from "../src/libraries/GameMath.sol";

contract GameMathTest is Test {
    uint256 constant WAD = 1e18;

    // ---- computeNewTraders ----

    function testComputeNewTradersMatchesFormula(uint256 surplusCapital, uint256 openDeskSeats) public pure {
        surplusCapital = bound(surplusCapital, 0, type(uint128).max);
        openDeskSeats = bound(openDeskSeats, 0, type(uint128).max);
        uint256 got = GameMath.computeNewTraders(surplusCapital, openDeskSeats);
        assertEq(got, Math.min(surplusCapital / 2, openDeskSeats));
    }

    function testComputeNewTradersNeverExceedsOpenSeats(uint256 surplusCapital, uint256 openDeskSeats) public pure {
        surplusCapital = bound(surplusCapital, 0, type(uint128).max);
        openDeskSeats = bound(openDeskSeats, 0, type(uint128).max);
        assertLe(GameMath.computeNewTraders(surplusCapital, openDeskSeats), openDeskSeats);
    }

    // ---- computeScoreAdded ----

    function testComputeScoreAddedMatchesFormula(uint256 newTraders, uint256 smallRandomWad) public pure {
        newTraders = bound(newTraders, 0, 1e12);
        smallRandomWad = bound(smallRandomWad, 0, GameMath.SMALL_RANDOM_MAX_WAD - 1);
        uint256 got = GameMath.computeScoreAdded(newTraders, smallRandomWad);
        assertEq(got, newTraders * GameMath.SCORE_PER_TRADER_WAD + smallRandomWad);
    }

    function testComputeScoreAddedZeroTradersIsJustRandom(uint256 smallRandomWad) public pure {
        smallRandomWad = bound(smallRandomWad, 0, GameMath.SMALL_RANDOM_MAX_WAD - 1);
        assertEq(GameMath.computeScoreAdded(0, smallRandomWad), smallRandomWad);
    }

    // ---- scaleSmallRandom ----

    function testScaleSmallRandomAlwaysBounded(uint256 rawRandomWord) public pure {
        uint256 scaled = GameMath.scaleSmallRandom(rawRandomWord);
        assertLt(scaled, GameMath.SMALL_RANDOM_MAX_WAD);
    }

    // ---- computeDeskCost ----

    function testComputeDeskCostFirstDeskIsBaseCost() public pure {
        assertEq(GameMath.computeDeskCost(0), GameMath.DESK_BASE_COST);
    }

    function testComputeDeskCostSecondDeskRoundsUpFromHalf() public pure {
        // 10 * 1.15 = 11.5 -> rounds to 12 (round-half-up per computeDeskCost's `+ WAD/2` term).
        assertEq(GameMath.computeDeskCost(1), 12);
    }

    function testComputeDeskCostMonotonicNonDecreasing(uint8 deskCount) public pure {
        uint256 n = bound(deskCount, 0, 80);
        assertLe(GameMath.computeDeskCost(n), GameMath.computeDeskCost(n + 1));
    }

    // ---- computeRecapCost ----

    function testComputeRecapCostZeroTraders() public pure {
        assertEq(GameMath.computeRecapCost(0), GameMath.RECAP_BASE_COST_WEI);
    }

    function testComputeRecapCostMatchesFormula(uint256 traders) public pure {
        traders = bound(traders, 0, 1e15);
        assertEq(GameMath.computeRecapCost(traders), (GameMath.RECAP_BASE_COST_WEI * (10 + traders)) / 10);
    }

    function testComputeRecapCostMonotonicNonDecreasing(uint32 traders) public pure {
        uint256 t = bound(traders, 0, type(uint32).max - 1);
        assertLe(GameMath.computeRecapCost(t), GameMath.computeRecapCost(t + 1));
    }

    // ---- computeAumMultiplier ----

    function testComputeAumMultiplierZeroAumIsOneX() public pure {
        assertEq(GameMath.computeAumMultiplier(0), WAD);
    }

    function testComputeAumMultiplierNeverExceedsCap(uint256 aum) public pure {
        aum = bound(aum, 0, type(uint128).max);
        assertLe(GameMath.computeAumMultiplier(aum), GameMath.MAX_AUM_MULTIPLIER_WAD);
    }

    function testComputeAumMultiplierNeverBelowOneX(uint256 aum) public pure {
        aum = bound(aum, 0, type(uint128).max);
        assertGe(GameMath.computeAumMultiplier(aum), WAD);
    }

    function testComputeAumMultiplierMonotonicNonDecreasing(uint256 a, uint256 b) public pure {
        a = bound(a, 0, type(uint128).max);
        b = bound(b, 0, type(uint128).max);
        if (a > b) (a, b) = (b, a);
        assertLe(GameMath.computeAumMultiplier(a), GameMath.computeAumMultiplier(b));
    }

    // ---- wadPow ----

    function testWadPowExponentZeroIsOne(uint256 base) public pure {
        base = bound(base, 0, type(uint128).max);
        assertEq(GameMath.wadPow(base, 0), WAD);
    }

    function testWadPowBaseOneIsAlwaysOne(uint8 exponent) public pure {
        assertEq(GameMath.wadPow(WAD, exponent), WAD);
    }

    function testWadPowConcreteCube() public pure {
        // 2^3 = 8
        assertEq(GameMath.wadPow(2e18, 3), 8e18);
    }

    function testWadPowConcreteSquare() public pure {
        // 1.5^2 = 2.25
        assertEq(GameMath.wadPow(1.5e18, 2), 2.25e18);
    }
}
