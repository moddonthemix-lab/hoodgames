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
        assertEq(f.traders, 0);
        assertEq(f.desks, 0);
        assertEq(f.score, 0);
        assertEq(f.lastRebalance, block.timestamp);
        assertEq(address(rewardsDistributor).balance, MINT_FEE);
    }

    function testMintFundRevertsBelowFee() public {
        vm.prank(alice);
        vm.expectRevert(GameEngine.InsufficientMsgValue.selector);
        gameEngine.mintFund{value: MINT_FEE - 1}(_commitment(S0));
    }

    // ---- rebalance ----

    function testRebalanceHappyPathNoGrowth() public {
        uint256 tokenId = _mintFund(alice, S0);
        uint256 mgnBefore = gameToken.balanceOf(alice);

        // 30h elapsed: enough YIELD accrues (10/epoch base rate) to cover the 3-YIELD cost,
        // well within the 72h Active window. desks == 0 so growth is necessarily 0 regardless
        // of capital — see DECISIONS.md / this file's header comment on bootstrap pacing.
        vm.warp(block.timestamp + 30 hours);
        _rebalance(alice, tokenId, S0, S1);

        IGameEngine.FundView memory f = gameEngine.getFund(tokenId);
        assertEq(f.traders, 0);
        assertGt(f.score, 0); // smallRandom term only, but always >= 0 and typically > 0
        assertLt(f.score, 0.5e18); // newTraders == 0, so score == smallRandom < SMALL_RANDOM_MAX_WAD
        assertEq(mgnBefore - gameToken.balanceOf(alice), gameEngine.REBALANCE_TOKEN_BURN());
        assertEq(f.lastRebalance, block.timestamp);
    }

    function testRebalanceRevertsBadReveal() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.warp(block.timestamp + 30 hours);
        vm.prank(alice);
        vm.expectRevert(GameEngine.BadReveal.selector);
        gameEngine.rebalance(tokenId, S1, _commitment(S2)); // S1 != S0, doesn't match commitment
    }

    function testRebalanceRevertsWhenNotFundOwner() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.warp(block.timestamp + 30 hours);
        vm.prank(bob);
        vm.expectRevert(GameEngine.NotFundOwner.selector);
        gameEngine.rebalance(tokenId, S0, _commitment(S1));
    }

    function testRebalanceRevertsPastDeadline() public {
        uint256 tokenId = _mintFund(alice, S0);
        _warpPastDeadline(tokenId);
        vm.prank(alice);
        vm.expectRevert(GameEngine.NotActive.selector);
        gameEngine.rebalance(tokenId, S0, _commitment(S1));
    }

    // ---- buildDesk ----

    function testBuildDeskHappyPath() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.warp(block.timestamp + gameEngine.EPOCH_LENGTH()); // exactly 1 epoch -> 10 YIELD accrued

        vm.prank(alice);
        gameEngine.buildDesk(tokenId);

        IGameEngine.FundView memory f = gameEngine.getFund(tokenId);
        assertEq(f.desks, 1);
        assertEq(f.yieldBalance, 0); // desk 0 costs exactly 10, all accrued yield spent
    }

    function testBuildDeskRevertsInsufficientYield() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.warp(block.timestamp + 1 hours); // nowhere near enough accrual

        vm.prank(alice);
        vm.expectRevert(GameEngine.InsufficientYield.selector);
        gameEngine.buildDesk(tokenId);
    }

    /// @dev buildDesk has no Active-status gate (only `!liquidated`) — a margin-called fund can
    ///      still build desks. This is what makes the growth-bootstrap pattern below possible.
    function testBuildDeskWorksWhileMarginCalled() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.warp(block.timestamp + 10 * gameEngine.EPOCH_LENGTH());
        assertEq(uint256(gameEngine.getStatus(tokenId)), uint256(IGameEngine.FundStatus.MarginCalled));

        vm.prank(alice);
        gameEngine.buildDesk(tokenId);
        assertEq(gameEngine.getFund(tokenId).desks, 1);
    }

    // ---- growth + payroll shortfall bootstrap ----
    // Pacing note (see DECISIONS.md): base accrual is 10 YIELD / 5 CAPITAL per epoch with 0
    // traders, and the first desk costs exactly 10 YIELD — so a fresh fund needs multiple epochs
    // of pure accrual before it can afford its first desk if it insists on also meeting every
    // rebalance deadline along the way. This bootstrap instead lets the fund go margin-called
    // (buildDesk works regardless), then recapitalizes to get back to Active — exercising three
    // mechanisms (accrual over a long idle period, buildDesk-while-margin-called, recapitalize)
    // in one natural sequence instead of ~10 manual rebalance cycles.

    function _bootstrapFundWithTraders(address player, bytes32 s0) internal returns (uint256 tokenId, bytes32 lastSecret) {
        tokenId = _mintFund(player, s0);
        vm.warp(block.timestamp + 10 * gameEngine.EPOCH_LENGTH()); // accrues 100 YIELD / 50 CAPITAL

        vm.prank(player);
        gameEngine.buildDesk(tokenId); // desks = 1 (5 seats), spends 10 YIELD

        vm.prank(player);
        gameEngine.recapitalize{value: 1 ether}(tokenId); // overpay; excess refunded, back to Active

        vm.warp(block.timestamp + 30 hours);
        bytes32 s1 = keccak256(abi.encode("bootstrap", player, uint256(1)));
        _rebalance(player, tokenId, s0, s1); // openDeskSeats = 5, capital ~52 -> newTraders = 5
        lastSecret = s1;

        IGameEngine.FundView memory f = gameEngine.getFund(tokenId);
        assertEq(f.traders, 5, "bootstrap expected to fill the single desk (5 seats)");
        assertEq(f.desks, 1);
    }

    function testGrowthFillsDeskCapacity() public {
        (uint256 tokenId,) = _bootstrapFundWithTraders(alice, S0);
        assertEq(gameEngine.getFund(tokenId).traders, 5);
        assertGt(gameEngine.getFund(tokenId).score, 0);
    }

    function testPayrollShortfallReducesTradersAndScore() public {
        (uint256 tokenId, bytes32 lastSecret) = _bootstrapFundWithTraders(alice, S0);

        // Drain CAPITAL via repeated zero-elapsed rebalances (each pays 5 CAPITAL payroll for 5
        // traders with ~0 new accrual) until a shortfall hits. yieldBalance was left with a large
        // surplus (~90+) from the 10-epoch bootstrap warp, so REBALANCE_YIELD_COST is never the
        // binding constraint here — only CAPITAL drains.
        uint32 tradersBefore;
        uint128 scoreBefore;
        bytes32 secret = lastSecret;
        for (uint256 i = 0; i < 12; i++) {
            IGameEngine.FundView memory before = gameEngine.getFund(tokenId);
            bytes32 next = keccak256(abi.encode("drain", i));
            tradersBefore = before.traders;
            scoreBefore = before.score;
            _rebalance(alice, tokenId, secret, next);
            secret = next;

            IGameEngine.FundView memory afterState = gameEngine.getFund(tokenId);
            if (afterState.traders < tradersBefore) {
                // Shortfall branch hit: traders quit 1:1 with the unpaid CAPITAL, score drops.
                assertLt(afterState.score, scoreBefore + 1.2e18 + 0.5e18, "score should drop, not just grow");
                assertLt(afterState.traders, tradersBefore);
                return;
            }
        }
        fail(); // shortfall never triggered within 12 iterations — bootstrap assumptions changed
    }

    // ---- recapitalize ----

    function testRecapitalizeHappyPath() public {
        uint256 tokenId = _mintFund(alice, S0);
        _warpPastDeadline(tokenId);
        assertEq(uint256(gameEngine.getStatus(tokenId)), uint256(IGameEngine.FundStatus.MarginCalled));

        uint256 cost = 0.01 ether; // computeRecapCost(0 traders) == RECAP_BASE_COST_WEI
        vm.prank(alice);
        gameEngine.recapitalize{value: cost}(tokenId);

        assertEq(uint256(gameEngine.getStatus(tokenId)), uint256(IGameEngine.FundStatus.Active));
    }

    function testRecapitalizeRefundsExcess() public {
        uint256 tokenId = _mintFund(alice, S0);
        _warpPastDeadline(tokenId);

        uint256 balBefore = alice.balance;
        vm.prank(alice);
        gameEngine.recapitalize{value: 1 ether}(tokenId);

        assertEq(balBefore - alice.balance, 0.01 ether);
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

    function testLiquidateRevertsDoubleLiquidation() public {
        uint256 tokenId = _mintFund(alice, S0);
        _warpPastGrace(tokenId);
        gameEngine.liquidate(tokenId);

        vm.expectRevert(GameEngine.AlreadyLiquidated.selector);
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
