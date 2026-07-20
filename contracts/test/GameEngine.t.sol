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
        assertEq(f.hackers, 0);
        assertEq(f.analysts, 0);
        assertEq(f.brokers, 0);
        assertEq(f.computers, 0);
        assertEq(f.score, 0);
        assertEq(f.lastRebalance, block.timestamp);
        assertEq(address(rewardsDistributor).balance, MINT_FEE);
    }

    function testMintFundRevertsBelowFee() public {
        vm.prank(alice);
        vm.expectRevert(GameEngine.InsufficientMsgValue.selector);
        gameEngine.mintFund{value: MINT_FEE - 1}(_commitment(S0));
    }

    // ---- buildComputer ----

    function testBuildComputerHappyPath() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.warp(block.timestamp + gameEngine.EPOCH_LENGTH()); // 1 epoch -> 10 YIELD accrued

        vm.prank(alice);
        gameEngine.buildComputer(tokenId);

        IGameEngine.FundView memory f = gameEngine.getFund(tokenId);
        assertEq(f.computers, 1);
        assertEq(f.yieldBalance, 0); // computer 0 costs exactly 10, all accrued yield spent
    }

    function testBuildComputerRevertsInsufficientYield() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        vm.expectRevert(GameEngine.InsufficientYield.selector);
        gameEngine.buildComputer(tokenId);
    }

    // ---- hire ----

    function testHireFillsSeatsAndBurnsMgn() public {
        uint256 tokenId = _mintFund(alice, S0);
        _buildComputers(alice, tokenId, 1); // 5 seats

        uint256 supplyBefore = gameToken.totalSupply();
        uint256 balBefore = gameToken.balanceOf(alice);

        vm.prank(alice);
        gameEngine.hire(tokenId, IGameEngine.Role.Analyst, 3);

        IGameEngine.FundView memory f = gameEngine.getFund(tokenId);
        assertEq(f.analysts, 3);
        uint256 expectedCost = 3 * gameEngine.HIRE_COST_ANALYST();
        assertEq(balBefore - gameToken.balanceOf(alice), expectedCost);
        assertEq(supplyBefore - gameToken.totalSupply(), expectedCost); // burned
    }

    function testHireDifferentRolesShareSeats() public {
        uint256 tokenId = _mintFund(alice, S0);
        _buildComputers(alice, tokenId, 1); // 5 seats

        _hire(alice, tokenId, IGameEngine.Role.Hacker, 2);
        _hire(alice, tokenId, IGameEngine.Role.Broker, 3);

        assertEq(gameEngine.totalWorkers(tokenId), 5);

        // 6th worker has no seat
        vm.prank(alice);
        vm.expectRevert(GameEngine.NoOpenSeats.selector);
        gameEngine.hire(tokenId, IGameEngine.Role.Analyst, 1);
    }

    function testHireRevertsWithNoComputers() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.prank(alice);
        vm.expectRevert(GameEngine.NoOpenSeats.selector);
        gameEngine.hire(tokenId, IGameEngine.Role.Hacker, 1);
    }

    function testHireRevertsZeroCount() public {
        uint256 tokenId = _mintFund(alice, S0);
        _buildComputers(alice, tokenId, 1);
        vm.prank(alice);
        vm.expectRevert(GameEngine.ZeroCount.selector);
        gameEngine.hire(tokenId, IGameEngine.Role.Hacker, 0);
    }

    function testHireRevertsIfNotOwner() public {
        uint256 tokenId = _mintFund(alice, S0);
        _buildComputers(alice, tokenId, 1);
        vm.prank(bob);
        vm.expectRevert(GameEngine.NotFundOwner.selector);
        gameEngine.hire(tokenId, IGameEngine.Role.Hacker, 1);
    }

    // ---- rebalance ----

    function testRebalanceNoWorkersScoresOnlyRandom() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.warp(block.timestamp + 30 hours);
        _rebalance(alice, tokenId, S0, S1);

        IGameEngine.FundView memory f = gameEngine.getFund(tokenId);
        // No workers -> score is just the smallRandom term, strictly < 0.5 WAD.
        assertLt(f.score, 0.5e18);
        assertEq(f.lastRebalance, block.timestamp);
    }

    function testRebalanceAnalystsDriveScore() public {
        uint256 tokenId = _mintFund(alice, S0);
        _buildComputers(alice, tokenId, 1);
        _hire(alice, tokenId, IGameEngine.Role.Analyst, 4);

        // Ensure capital covers payroll (4 workers -> 4 CAPITAL). Warp ~1 epoch: base capital 5 >= 4.
        vm.warp(block.timestamp + gameEngine.EPOCH_LENGTH());
        _rebalance(alice, tokenId, S0, S1);

        IGameEngine.FundView memory f = gameEngine.getFund(tokenId);
        // 4 analysts * 1.2 = 4.8 WAD, plus < 0.5 random. Should be >= 4.8.
        assertGe(f.score, 4 * gameEngine.ANALYST_SCORE_WAD());
        assertEq(f.analysts, 4); // survived payroll
    }

    function testRebalanceRevertsBadReveal() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.warp(block.timestamp + 30 hours);
        vm.prank(alice);
        vm.expectRevert(GameEngine.BadReveal.selector);
        gameEngine.rebalance(tokenId, S1, _commitment(S2));
    }

    function testRebalanceRevertsPastDeadline() public {
        uint256 tokenId = _mintFund(alice, S0);
        _warpPastDeadline(tokenId);
        vm.prank(alice);
        vm.expectRevert(GameEngine.NotActive.selector);
        gameEngine.rebalance(tokenId, S0, _commitment(S1));
    }

    function testPayrollShortfallLaysOffWorkersHackerFirst() public {
        uint256 tokenId = _mintFund(alice, S0);
        _buildComputers(alice, tokenId, 2); // 10 seats
        // Hire a mix that exceeds base capital income (10 workers -> 10 CAPITAL payroll, base only 5/epoch).
        _hire(alice, tokenId, IGameEngine.Role.Hacker, 4);
        _hire(alice, tokenId, IGameEngine.Role.Analyst, 3);
        _hire(alice, tokenId, IGameEngine.Role.Broker, 3);

        // Rebalance right away: near-zero capital accrued since the last _buildComputers warp,
        // so payroll for 10 workers massively overshoots -> big layoff, hackers first.
        _rebalance(alice, tokenId, S0, S1);

        IGameEngine.FundView memory f = gameEngine.getFund(tokenId);
        // Hackers (4) should be wiped before analysts/brokers are touched.
        assertEq(f.hackers, 0, "hackers laid off first");
        assertLt(gameEngine.totalWorkers(tokenId), 10, "some workers laid off");
    }

    // ---- recapitalize ----

    function testRecapitalizeHappyPath() public {
        uint256 tokenId = _mintFund(alice, S0);
        _warpPastDeadline(tokenId);
        assertEq(uint256(gameEngine.getStatus(tokenId)), uint256(IGameEngine.FundStatus.MarginCalled));

        uint256 cost = gameEngine.recapCost(tokenId); // 0 workers -> base cost
        vm.prank(alice);
        gameEngine.recapitalize{value: cost}(tokenId);

        assertEq(uint256(gameEngine.getStatus(tokenId)), uint256(IGameEngine.FundStatus.Active));
    }

    function testRecapitalizeRevertsWhenActive() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.prank(alice);
        vm.expectRevert(GameEngine.NotMarginCalled.selector);
        gameEngine.recapitalize{value: 1 ether}(tokenId);
    }

    function testRecapitalizeRevertsTooLate() public {
        uint256 tokenId = _mintFund(alice, S0);
        _warpPastGrace(tokenId);
        vm.prank(alice);
        vm.expectRevert(GameEngine.TooLateForRecap.selector);
        gameEngine.recapitalize{value: 1 ether}(tokenId);
    }

    // ---- liquidate ----

    function testLiquidatePermissionlessWithBounty() public {
        uint256 tokenId = _mintFund(alice, S0);
        _warpPastGrace(tokenId);

        uint256 keeperBalBefore = keeper.balance;
        vm.prank(keeper);
        gameEngine.liquidate(tokenId);

        assertFalse(fundNFT.exists(tokenId));
        assertEq(keeper.balance - keeperBalBefore, gameEngine.LIQUIDATION_BOUNTY());
    }

    function testLiquidateRevertsNotYetEligible() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.expectRevert(GameEngine.NotYetLiquidationEligible.selector);
        gameEngine.liquidate(tokenId);
    }

    // ---- takeover ----

    function testTakeoverBurnsStakeAndSetsImmunity() public {
        uint256 attackerId = _mintFund(alice, S0);
        uint256 defenderId = _mintFund(bob, S1);
        uint256 mgnBefore = gameToken.balanceOf(alice);

        vm.prank(alice);
        gameEngine.takeover(attackerId, defenderId, S0, _commitment(S2));

        assertEq(mgnBefore - gameToken.balanceOf(alice), gameEngine.TAKEOVER_STAKE());
        assertEq(uint256(gameEngine.lastAttackedAt(defenderId)), block.timestamp);
    }

    function testTakeoverRevertsSelf() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.prank(alice);
        vm.expectRevert(GameEngine.SelfTakeover.selector);
        gameEngine.takeover(tokenId, tokenId, S0, _commitment(S1));
    }

    function testTakeoverRevertsDuringImmunity() public {
        uint256 attackerId = _mintFund(alice, S0);
        uint256 defenderId = _mintFund(bob, S1);

        vm.prank(alice);
        gameEngine.takeover(attackerId, defenderId, S0, _commitment(S2));

        uint256 secondAttackerId = _mintFund(carol, keccak256("carol0"));
        vm.prank(carol);
        vm.expectRevert(GameEngine.DefenderImmune.selector);
        gameEngine.takeover(secondAttackerId, defenderId, keccak256("carol0"), _commitment(keccak256("carol1")));
    }

    // ---- access control on RewardsDistributor-only callbacks ----

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
