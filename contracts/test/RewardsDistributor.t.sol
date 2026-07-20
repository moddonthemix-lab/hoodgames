// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaseTest} from "./BaseTest.sol";
import {RewardsDistributor} from "../src/RewardsDistributor.sol";
import {MockGameEngineForRewards} from "./mocks/MockGameEngineForRewards.sol";
import {MockAUMStakingForRewards} from "./mocks/MockAUMStakingForRewards.sol";
import {MockFundNFTForRewards} from "./mocks/MockFundNFTForRewards.sol";

/// @title RewardsDistributorMathTest
/// @notice Isolates RewardsDistributor's accumulator math from full gameplay by wiring it to
///         mock IGameEngine/IAUMStaking/IFundNFT doubles with directly-settable state. This is
///         where the fuzz invariants required by the Phase 2 plan live: total claimed/earned
///         never exceeds total ETH received, and the accumulator is monotonic non-decreasing.
///         See RewardsDistributorIntegrationTest below for end-to-end tests against the real stack.
contract RewardsDistributorMathTest is Test {
    RewardsDistributor rd;
    MockGameEngineForRewards mockEngine;
    MockAUMStakingForRewards mockAum;
    MockFundNFTForRewards mockNft;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        vm.startPrank(owner);
        rd = new RewardsDistributor(owner);
        mockEngine = new MockGameEngineForRewards();
        mockAum = new MockAUMStakingForRewards();
        mockNft = new MockFundNFTForRewards();
        rd.setGameEngine(address(mockEngine));
        rd.setAumStaking(address(mockAum));
        rd.setFundNFT(address(mockNft));
        vm.stopPrank();

        mockEngine.setRewardsDistributor(address(rd));
    }

    // ---- syncFund / weighting ----

    function testSyncFundSetsWeightedScoreToRawScoreAtOneX() public {
        mockEngine.setScore(1, 500);
        rd.syncFund(1);
        assertEq(rd.weightedScore(1), 500);
        assertEq(rd.totalWeightedScore(), 500);
    }

    function testSyncFundAppliesAumMultiplier() public {
        mockEngine.setScore(1, 1000);
        mockAum.setMultiplier(1, 2e18); // 2x
        rd.syncFund(1);
        assertEq(rd.weightedScore(1), 2000);
    }

    function testSyncFundTotalWeightedScoreTracksMultipleFunds() public {
        mockEngine.setScore(1, 100);
        mockEngine.setScore(2, 300);
        rd.syncFund(1);
        rd.syncFund(2);
        assertEq(rd.totalWeightedScore(), 400);

        mockEngine.setScore(1, 150);
        rd.syncFund(1);
        assertEq(rd.totalWeightedScore(), 450);
    }

    // ---- FUZZ INVARIANT: accumulator is monotonic non-decreasing ----

    function testFuzzAccumulatorMonotonicNonDecreasing(uint96 deposit1, uint96 deposit2, uint96 deposit3) public {
        uint256 d1 = bound(deposit1, 0, 1000 ether);
        uint256 d2 = bound(deposit2, 0, 1000 ether);
        uint256 d3 = bound(deposit3, 0, 1000 ether);

        mockEngine.setScore(1, 1_000e18);
        rd.syncFund(1);

        uint256 acc0 = rd.rewardPerWeightedScoreStored();
        vm.deal(address(this), d1);
        rd.depositRewards{value: d1}();
        uint256 acc1 = rd.rewardPerWeightedScoreStored();
        assertGe(acc1, acc0);

        vm.deal(address(this), d2);
        rd.depositRewards{value: d2}();
        uint256 acc2 = rd.rewardPerWeightedScoreStored();
        assertGe(acc2, acc1);

        vm.deal(address(this), d3);
        rd.depositRewards{value: d3}();
        uint256 acc3 = rd.rewardPerWeightedScoreStored();
        assertGe(acc3, acc2);
    }

    // ---- FUZZ INVARIANT: total earned never exceeds total ETH received ----
    // This is the core Synthetix/MasterChef-style accumulator safety property: every division in
    // the accumulator rounds DOWN, so the sum of what funds can claim can never exceed what was
    // actually deposited, only ever fall (negligibly) short due to rounding dust.

    function testFuzzTotalEarnedNeverExceedsTotalDeposited(
        uint128 score1,
        uint128 score2,
        uint128 score3,
        uint96 deposit1,
        uint96 deposit2,
        uint96 deposit3
    ) public {
        uint256 s1 = bound(score1, 1, 1e24);
        uint256 s2 = bound(score2, 1, 1e24);
        uint256 s3 = bound(score3, 1, 1e24);
        uint256 d1 = bound(deposit1, 0, 1000 ether);
        uint256 d2 = bound(deposit2, 0, 1000 ether);
        uint256 d3 = bound(deposit3, 0, 1000 ether);

        mockEngine.setScore(1, uint128(s1));
        rd.syncFund(1);
        vm.deal(address(this), d1);
        rd.depositRewards{value: d1}();

        mockEngine.setScore(2, uint128(s2));
        rd.syncFund(2);
        vm.deal(address(this), d2);
        rd.depositRewards{value: d2}();

        mockEngine.setScore(3, uint128(s3));
        rd.syncFund(3);
        vm.deal(address(this), d3);
        rd.depositRewards{value: d3}();

        rd.syncFund(1);
        rd.syncFund(2);
        rd.syncFund(3);

        uint256 totalEarned = rd.earned(1) + rd.earned(2) + rd.earned(3);
        uint256 totalDeposited = d1 + d2 + d3;
        assertLe(totalEarned, totalDeposited);
    }

    function testFuzzSingleFundNeverEarnsMoreThanDeposited(uint128 score, uint96 depositAmount) public {
        uint256 s = bound(score, 1, 1e24);
        uint256 d = bound(depositAmount, 0, 1000 ether);

        mockEngine.setScore(1, uint128(s));
        rd.syncFund(1);
        vm.deal(address(this), d);
        rd.depositRewards{value: d}();
        rd.syncFund(1);

        assertLe(rd.earned(1), d);
    }

    function testDepositBeforeAnyScoreExistsIsNotLost() public {
        // totalWeightedScore == 0 here -> deposit rolls into undistributedRewards instead of
        // being silently stranded (see RewardsDistributor._depositInternal).
        vm.deal(address(this), 1 ether);
        rd.depositRewards{value: 1 ether}();
        assertEq(rd.undistributedRewards(), 1 ether);
        assertEq(rd.rewardPerWeightedScoreStored(), 0);

        mockEngine.setScore(1, 100);
        rd.syncFund(1);
        vm.deal(address(this), 1 ether);
        rd.depositRewards{value: 1 ether}();

        assertEq(rd.undistributedRewards(), 0);
        assertApproxEqAbs(rd.earned(1), 2 ether, 1);
    }

    // ---- claim / claimPartial ----

    function testClaimFullResetsWeightingAndCreditsWithdrawable() public {
        mockNft.setOwner(1, alice);
        mockEngine.setScore(1, 1000);
        rd.syncFund(1);
        vm.deal(address(this), 10 ether);
        rd.depositRewards{value: 10 ether}();

        vm.prank(alice);
        rd.claim(1);

        assertEq(rd.rewards(1), 0);
        assertEq(rd.weightedScore(1), 0);
        assertEq(mockEngine.scoreOf(1), 0); // resetFundForRedemption was called
        assertApproxEqAbs(rd.withdrawable(alice), 10 ether, 1);
    }

    function testClaimRevertsIfNotFundOwner() public {
        mockNft.setOwner(1, alice);
        vm.prank(bob);
        vm.expectRevert(RewardsDistributor.NotFundOwner.selector);
        rd.claim(1);
    }

    function testClaimPartialPaysHalfAndHaircutsScore() public {
        mockNft.setOwner(1, alice);
        mockEngine.setScore(1, 1000);
        rd.syncFund(1);
        vm.deal(address(this), 10 ether);
        rd.depositRewards{value: 10 ether}();

        vm.prank(alice);
        rd.claimPartial(1);

        assertApproxEqAbs(rd.withdrawable(alice), 5 ether, 1); // 50% payout
        assertEq(mockEngine.scoreOf(1), 500); // 50% haircut applied via mock GameEngine callback
    }

    function testClaimPartialRevertsDuringCooldown() public {
        mockNft.setOwner(1, alice);
        mockEngine.setScore(1, 1000);
        rd.syncFund(1);
        vm.deal(address(this), 10 ether);
        rd.depositRewards{value: 10 ether}();

        vm.startPrank(alice);
        rd.claimPartial(1);
        vm.expectRevert(RewardsDistributor.CooldownActive.selector);
        rd.claimPartial(1);
        vm.stopPrank();
    }

    function testClaimPartialForfeitedShareStaysInPool() public {
        mockNft.setOwner(1, alice);
        mockNft.setOwner(2, bob);
        mockEngine.setScore(1, 1000);
        mockEngine.setScore(2, 1000);
        rd.syncFund(1);
        rd.syncFund(2);
        vm.deal(address(this), 10 ether);
        rd.depositRewards{value: 10 ether}();

        vm.prank(alice);
        rd.claimPartial(1); // forfeits ~2.5 ETH back to the pool

        rd.syncFund(2);
        // bob's 5 ETH original share + roughly half of alice's forfeited share (pro-rata by
        // weighted score, which by this point favors bob since alice's was just haircut).
        assertGt(rd.earned(2), 5 ether);
    }

    // ---- settleOnLiquidation / seizeRewards access control ----

    function testSettleOnLiquidationRevertsIfNotGameEngine() public {
        vm.expectRevert(RewardsDistributor.NotGameEngine.selector);
        rd.settleOnLiquidation(1, alice, bob, 0);
    }

    function testSeizeRewardsRevertsIfNotGameEngine() public {
        vm.expectRevert(RewardsDistributor.NotGameEngine.selector);
        rd.seizeRewards(1, 2, 1000);
    }

    function testSeizeRewardsMovesAccruedBalanceBetweenFunds() public {
        mockEngine.setScore(1, 1000);
        mockEngine.setScore(2, 1000);
        rd.syncFund(1);
        rd.syncFund(2);
        vm.deal(address(this), 10 ether);
        rd.depositRewards{value: 10 ether}();

        vm.prank(address(mockEngine));
        uint256 seized = rd.seizeRewards(1, 2, 1000); // 10% of fund 1's ~5 ETH accrued

        assertApproxEqAbs(seized, 0.5 ether, 1);
        assertApproxEqAbs(rd.earned(1), 4.5 ether, 1);
        assertApproxEqAbs(rd.earned(2), 5.5 ether, 1);
    }

    // ---- withdraw ----

    function testWithdrawTransfersCreditedBalance() public {
        mockNft.setOwner(1, alice);
        mockEngine.setScore(1, 1000);
        rd.syncFund(1);
        vm.deal(address(this), 10 ether);
        rd.depositRewards{value: 10 ether}();

        vm.prank(alice);
        rd.claim(1);

        uint256 balBefore = alice.balance;
        vm.prank(alice);
        rd.withdraw();
        assertApproxEqAbs(alice.balance - balBefore, 10 ether, 1);
        assertEq(rd.withdrawable(alice), 0);
    }

    function testWithdrawRevertsWithNothingOwed() public {
        vm.prank(alice);
        vm.expectRevert(RewardsDistributor.NothingToWithdraw.selector);
        rd.withdraw();
    }
}

/// @title RewardsDistributorIntegrationTest
/// @notice End-to-end tests against the real GameEngine/FundNFT/AUMStaking stack (via BaseTest),
///         confirming the accumulator wiring described above actually gets invoked correctly
///         from real gameplay (liquidation payout, takeover seizure).
contract RewardsDistributorIntegrationTest is BaseTest {
    bytes32 constant S0 = keccak256("s0");
    bytes32 constant S1 = keccak256("s1");

    function testLiquidationCreditsOwnerWithdrawableBalance() public {
        uint256 tokenId = _mintFund(alice, S0);
        _warpPastGrace(tokenId);

        gameEngine.liquidate(tokenId);

        // Fund never accrued score (liquidated on its very first epoch), so accrued rewards are
        // 0 — this asserts the settlement path runs without reverting and leaves a sane (zero)
        // balance, not a stuck/negative one.
        assertEq(rewardsDistributor.withdrawable(alice), 0);
    }

    function testTakeoverSeizesRewardsBetweenRealFunds() public {
        uint256 attackerId = _mintFund(alice, S0);
        uint256 defenderId = _mintFund(bob, S1);

        // Both funds start at score 0 (neither has rebalanced), so weightedScore is 0 for both
        // and a deposit right now would accrue to nobody (see MockGameEngineForRewards-based
        // tests above for that mechanism in isolation). Give the defender a nonzero score first
        // — a plain rebalance always adds >0 via the smallRandom term even with 0 traders — so
        // the deposit below actually has something for the defender to accrue, and thus for the
        // attacker to steal.
        vm.warp(block.timestamp + 30 hours);
        _rebalance(bob, defenderId, S1, keccak256("bob-next"));

        vm.deal(address(this), 1 ether);
        rewardsDistributor.depositRewards{value: 1 ether}();
        rewardsDistributor.syncFund(defenderId);
        assertGt(rewardsDistributor.earned(defenderId), 0);

        vm.prank(alice);
        gameEngine.takeover(attackerId, defenderId, S0, _commitment(keccak256("s2")));

        // seizeRewards moves a slice of `rewards[defenderId]` directly into `rewards[attackerId]`
        // regardless of the attacker's own weightedScore, so this holds even though alice never rebalanced.
        assertGt(rewardsDistributor.earned(attackerId), 0);
    }
}
