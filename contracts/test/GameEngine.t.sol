// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";
import {IGameEngine} from "../src/interfaces/IGameEngine.sol";
import {GameEngine} from "../src/GameEngine.sol";

contract GameEngineTest is BaseTest {
    bytes32 constant S0 = keccak256("s0");
    bytes32 constant S1 = keccak256("s1");
    bytes32 constant S2 = keccak256("s2");

    // ---- mintFund ----

    function testMintFundHappyPath() public {
        uint256 tokenId = _mintFund(alice, S0);
        assertEq(fundNFT.ownerOf(tokenId), alice);
        assertEq(uint256(gameEngine.getStatus(tokenId)), uint256(IGameEngine.FundStatus.Active));

        IGameEngine.FundView memory f = gameEngine.getFund(tokenId);
        assertEq(f.hackers + f.analysts + f.brokers, 0);
        assertEq(f.computers, 0);
        assertEq(f.score, 0);
        assertEq(address(rewardsDistributor).balance, MINT_FEE);
    }

    function testMintFundRevertsBelowFee() public {
        vm.prank(alice);
        vm.expectRevert(GameEngine.InsufficientMsgValue.selector);
        gameEngine.mintFund{value: MINT_FEE - 1}(_commitment(S0));
    }

    // ---- gather ----

    function testGatherYieldGivesFixedAmountAndSetsCooldown() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.prank(alice);
        gameEngine.gatherYield(tokenId);

        IGameEngine.FundView memory f = gameEngine.getFund(tokenId);
        assertEq(f.yieldBalance, gameEngine.YIELD_PER_GATHER());
        assertEq(f.yieldCooldownEnd, block.timestamp + gameEngine.GATHER_COOLDOWN());
    }

    function testGatherRevertsOnCooldown() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.prank(alice);
        gameEngine.gatherYield(tokenId);
        vm.prank(alice);
        vm.expectRevert(GameEngine.GatherOnCooldown.selector);
        gameEngine.gatherYield(tokenId);
    }

    function testGatherAgainAfterCooldown() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.prank(alice);
        gameEngine.gatherCapital(tokenId);
        vm.warp(block.timestamp + gameEngine.GATHER_COOLDOWN());
        vm.prank(alice);
        gameEngine.gatherCapital(tokenId);
        assertEq(gameEngine.getFund(tokenId).capitalBalance, 2 * gameEngine.CAPITAL_PER_GATHER());
    }

    function testGatherRevertsIfNotOwner() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.prank(bob);
        vm.expectRevert(GameEngine.NotFundOwner.selector);
        gameEngine.gatherYield(tokenId);
    }

    // ---- rebalance ----

    function testRebalanceGrantsComputerAndScore() public {
        uint256 tokenId = _mintFund(alice, S0);
        _doRebalance(alice, tokenId, S0, S1);

        IGameEngine.FundView memory f = gameEngine.getFund(tokenId);
        assertEq(f.computers, 1, "rebalance grants a computer");
        assertGt(f.score, 0, "rebalance adds score (random even with 0 workers)");
        assertEq(f.lastRebalance, block.timestamp);
    }

    function testRebalanceRevertsTooSoon() public {
        uint256 tokenId = _mintFund(alice, S0);
        // Gather resources but don't wait out MIN_REBALANCE_INTERVAL.
        vm.prank(alice);
        gameEngine.gatherYield(tokenId);
        vm.prank(alice);
        gameEngine.gatherCapital(tokenId);
        vm.prank(alice);
        vm.expectRevert(GameEngine.RebalanceTooSoon.selector);
        gameEngine.rebalance(tokenId, S0, _commitment(S1));
    }

    function testRebalanceRevertsInsufficientYield() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.warp(block.timestamp + gameEngine.MIN_REBALANCE_INTERVAL() + 1);
        vm.prank(alice);
        vm.expectRevert(GameEngine.InsufficientYield.selector);
        gameEngine.rebalance(tokenId, S0, _commitment(S1));
    }

    function testRebalanceRevertsBadReveal() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.warp(block.timestamp + gameEngine.MIN_REBALANCE_INTERVAL() + 1);
        vm.prank(alice);
        gameEngine.gatherYield(tokenId);
        vm.prank(alice);
        gameEngine.gatherCapital(tokenId);
        vm.prank(alice);
        vm.expectRevert(GameEngine.BadReveal.selector);
        gameEngine.rebalance(tokenId, S1, _commitment(S2)); // S1 != committed S0
    }

    function testRebalanceRevertsPastDeadline() public {
        uint256 tokenId = _mintFund(alice, S0);
        _warpPastDeadline(tokenId);
        vm.prank(alice);
        vm.expectRevert(GameEngine.NotActive.selector);
        gameEngine.rebalance(tokenId, S0, _commitment(S1));
    }

    function testRebalanceAnalystsDriveScore() public {
        uint256 tokenId = _mintFund(alice, S0);
        bytes32 s = _growComputers(alice, tokenId, 1, S0); // 1 computer -> 5 seats
        _hire(alice, tokenId, IGameEngine.Role.Analyst, 4);

        bytes32 next = keccak256("after-analysts");
        uint256 scoreBefore = gameEngine.getFund(tokenId).score;
        _doRebalance(alice, tokenId, s, next);
        uint256 gained = gameEngine.getFund(tokenId).score - scoreBefore;

        // 4 analysts * 1.2 = 4.8 WAD floor (plus <0.5 random).
        assertGe(gained, 4 * gameEngine.ANALYST_SCORE_WAD());
        assertEq(gameEngine.getFund(tokenId).analysts, 4);
    }

    function testPayrollShortfallLaysOffHackersFirst() public {
        uint256 tokenId = _mintFund(alice, S0);
        bytes32 s = _growComputers(alice, tokenId, 2, S0); // 2 computers -> 10 seats
        _hire(alice, tokenId, IGameEngine.Role.Hacker, 4);
        _hire(alice, tokenId, IGameEngine.Role.Analyst, 3);
        _hire(alice, tokenId, IGameEngine.Role.Broker, 3);

        // Rebalance with only minimal capital (gather exactly one lot of yield + capital).
        // Payroll for 10 workers = base 3 + 10 = 13 > one gather (10) -> shortfall -> layoffs.
        uint256 minTime = gameEngine.getFund(tokenId).lastRebalance + gameEngine.MIN_REBALANCE_INTERVAL() + 1;
        vm.warp(minTime);
        vm.prank(alice);
        gameEngine.gatherYield(tokenId);
        vm.prank(alice);
        gameEngine.gatherCapital(tokenId);
        _rebalance(alice, tokenId, s, keccak256("post"));

        IGameEngine.FundView memory f = gameEngine.getFund(tokenId);
        assertEq(f.hackers, 0, "hackers laid off first");
        assertLt(f.hackers + f.analysts + f.brokers, 10, "some workers laid off");
    }

    // ---- hire ----

    function testHireRevertsWithNoComputers() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.prank(alice);
        vm.expectRevert(GameEngine.NoOpenSeats.selector);
        gameEngine.hire(tokenId, IGameEngine.Role.Hacker, 1);
    }

    function testHireFillsSeatsAndBurnsMgn() public {
        uint256 tokenId = _mintFund(alice, S0);
        _growComputers(alice, tokenId, 1, S0); // 5 seats

        uint256 supplyBefore = gameToken.totalSupply();
        _hire(alice, tokenId, IGameEngine.Role.Analyst, 3);

        assertEq(gameEngine.getFund(tokenId).analysts, 3);
        assertEq(supplyBefore - gameToken.totalSupply(), 3 * gameEngine.HIRE_COST_ANALYST());
    }

    function testHireRevertsNoOpenSeats() public {
        uint256 tokenId = _mintFund(alice, S0);
        _growComputers(alice, tokenId, 1, S0); // 5 seats
        _hire(alice, tokenId, IGameEngine.Role.Broker, 5);
        vm.prank(alice);
        vm.expectRevert(GameEngine.NoOpenSeats.selector);
        gameEngine.hire(tokenId, IGameEngine.Role.Hacker, 1);
    }

    // ---- recapitalize / liquidate ----

    function testRecapitalizeHappyPath() public {
        uint256 tokenId = _mintFund(alice, S0);
        _warpPastDeadline(tokenId);
        assertEq(uint256(gameEngine.getStatus(tokenId)), uint256(IGameEngine.FundStatus.MarginCalled));

        uint256 cost = gameEngine.recapCost(tokenId);
        vm.prank(alice);
        gameEngine.recapitalize{value: cost}(tokenId);
        assertEq(uint256(gameEngine.getStatus(tokenId)), uint256(IGameEngine.FundStatus.Active));
    }

    function testLiquidatePermissionlessWithBounty() public {
        uint256 tokenId = _mintFund(alice, S0);
        _warpPastGrace(tokenId);

        uint256 keeperBalBefore = keeper.balance;
        vm.prank(keeper);
        gameEngine.liquidate(tokenId);

        assertFalse(fundNFT.exists(tokenId));
        assertEq(keeper.balance - keeperBalBefore, gameEngine.LIQUIDATION_BOUNTY());
    }

    // ---- takeover gating ----

    function testTakeoverLockedWithoutComputers() public {
        uint256 attackerId = _mintFund(alice, S0);
        uint256 defenderId = _mintFund(bob, S1);
        vm.prank(alice);
        vm.expectRevert(GameEngine.TakeoverLockedNeedComputers.selector);
        gameEngine.takeover(attackerId, defenderId, S0, _commitment(S2));
    }

    function testTakeoverLockedWithoutWorker() public {
        uint256 attackerId = _mintFund(alice, S0);
        uint256 defenderId = _mintFund(bob, keccak256("bob0"));
        bytes32 s = _growComputers(alice, attackerId, 4, S0); // 4 computers, but no workers hired
        assertFalse(gameEngine.canAttack(attackerId));

        vm.prank(alice);
        vm.expectRevert(GameEngine.TakeoverLockedNeedWorker.selector);
        gameEngine.takeover(attackerId, defenderId, s, _commitment(keccak256("next")));
    }

    function testTakeoverSucceedsWhenEstablished() public {
        uint256 attackerId = _mintFund(alice, S0);
        uint256 defenderId = _mintFund(bob, keccak256("bob0"));
        bytes32 s = _growComputers(alice, attackerId, 4, S0);
        _hire(alice, attackerId, IGameEngine.Role.Hacker, 1);
        assertTrue(gameEngine.canAttack(attackerId));

        uint256 mgnBefore = gameToken.balanceOf(alice);
        vm.prank(alice);
        gameEngine.takeover(attackerId, defenderId, s, _commitment(keccak256("next")));

        assertEq(mgnBefore - gameToken.balanceOf(alice), gameEngine.TAKEOVER_STAKE());
        assertEq(uint256(gameEngine.lastAttackedAt(defenderId)), block.timestamp);
    }

    function testTakeoverRevertsSelf() public {
        uint256 tokenId = _mintFund(alice, S0);
        bytes32 s = _growComputers(alice, tokenId, 4, S0);
        _hire(alice, tokenId, IGameEngine.Role.Hacker, 1);
        vm.prank(alice);
        vm.expectRevert(GameEngine.SelfTakeover.selector);
        gameEngine.takeover(tokenId, tokenId, s, _commitment(keccak256("n")));
    }

    // ---- access control ----

    function testResetFundForRedemptionRevertsIfNotRewardsDistributor() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.expectRevert(GameEngine.NotRewardsDistributor.selector);
        gameEngine.resetFundForRedemption(tokenId);
    }

    function testApplyScoreHaircutRevertsIfNotRewardsDistributor() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.expectRevert(GameEngine.NotRewardsDistributor.selector);
        gameEngine.applyScoreHaircut(tokenId, 5000);
    }
}
