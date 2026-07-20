// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GameMath} from "../src/libraries/GameMath.sol";

contract GameMathTest is Test {
    uint256 constant WAD = 1e18;

    // ---- scaleSmallRandom ----

    function testScaleSmallRandomAlwaysBounded(uint256 rawRandomWord) public pure {
        uint256 scaled = GameMath.scaleSmallRandom(rawRandomWord);
        assertLt(scaled, GameMath.SMALL_RANDOM_MAX_WAD);
    }

    // ---- computeComputerCost ----

    function testComputeComputerCostFirstIsBaseCost() public pure {
        assertEq(GameMath.computeComputerCost(0), GameMath.COMPUTER_BASE_COST);
    }

    function testComputeComputerCostSecondRoundsUpFromHalf() public pure {
        // 10 * 1.15 = 11.5 -> rounds to 12 (round-half-up per computeComputerCost's `+ WAD/2`).
        assertEq(GameMath.computeComputerCost(1), 12);
    }

    function testComputeComputerCostMonotonicNonDecreasing(uint8 computerCount) public pure {
        uint256 n = bound(computerCount, 0, 80);
        assertLe(GameMath.computeComputerCost(n), GameMath.computeComputerCost(n + 1));
    }

    // ---- computeRecapCost ----

    function testComputeRecapCostZeroWorkers() public pure {
        assertEq(GameMath.computeRecapCost(0), GameMath.RECAP_BASE_COST_WEI);
    }

    function testComputeRecapCostMatchesFormula(uint256 workers) public pure {
        workers = bound(workers, 0, 1e15);
        assertEq(GameMath.computeRecapCost(workers), (GameMath.RECAP_BASE_COST_WEI * (10 + workers)) / 10);
    }

    function testComputeRecapCostMonotonicNonDecreasing(uint32 workers) public pure {
        uint256 w = bound(workers, 0, type(uint32).max - 1);
        assertLe(GameMath.computeRecapCost(w), GameMath.computeRecapCost(w + 1));
    }

    // ---- computeAumMultiplier: tiered, capped at 1.5x ----

    function testAumMultiplierBelowFirstTierIsOneX() public pure {
        assertEq(GameMath.computeAumMultiplier(0), WAD);
        assertEq(GameMath.computeAumMultiplier(999 ether), WAD);
    }

    function testAumMultiplierTierBreakpoints() public pure {
        assertEq(GameMath.computeAumMultiplier(1_000 ether), 1.1e18);
        assertEq(GameMath.computeAumMultiplier(4_999 ether), 1.1e18);
        assertEq(GameMath.computeAumMultiplier(5_000 ether), 1.2e18);
        assertEq(GameMath.computeAumMultiplier(20_000 ether), 1.3e18);
        assertEq(GameMath.computeAumMultiplier(50_000 ether), 1.4e18);
        assertEq(GameMath.computeAumMultiplier(100_000 ether), 1.5e18);
    }

    function testAumMultiplierNeverExceedsCap(uint256 aum) public pure {
        aum = bound(aum, 0, type(uint128).max);
        assertLe(GameMath.computeAumMultiplier(aum), GameMath.MAX_AUM_MULTIPLIER_WAD);
    }

    function testAumMultiplierNeverBelowOneX(uint256 aum) public pure {
        aum = bound(aum, 0, type(uint128).max);
        assertGe(GameMath.computeAumMultiplier(aum), WAD);
    }

    function testAumMultiplierMonotonicNonDecreasing(uint256 a, uint256 b) public pure {
        a = bound(a, 0, type(uint128).max);
        b = bound(b, 0, type(uint128).max);
        if (a > b) (a, b) = (b, a);
        assertLe(GameMath.computeAumMultiplier(a), GameMath.computeAumMultiplier(b));
    }

    function testAumMultiplierHugeStakeStillCappedAt1_5x() public pure {
        assertEq(GameMath.computeAumMultiplier(10_000_000 ether), 1.5e18);
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
        assertEq(GameMath.wadPow(2e18, 3), 8e18); // 2^3 = 8
    }

    function testWadPowConcreteSquare() public pure {
        assertEq(GameMath.wadPow(1.5e18, 2), 2.25e18); // 1.5^2 = 2.25
    }
}
