// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";
import {GameToken} from "../src/GameToken.sol";

contract GameTokenTest is BaseTest {
    function testInitialDistribution() public view {
        assertEq(gameToken.totalSupply(), gameToken.TOTAL_SUPPLY());
        assertEq(gameToken.TOTAL_SUPPLY(), 10_000_000 ether);

        // lpRecipient started with 90%, minus what BaseTest.setUp() forwarded to alice/bob/carol.
        uint256 seeded = PLAYER_MGN_SEED * 3;
        assertEq(gameToken.balanceOf(lpRecipient), (gameToken.TOTAL_SUPPLY() * 90) / 100 - seeded);
        assertEq(gameToken.balanceOf(devRecipient), (gameToken.TOTAL_SUPPLY() * 3) / 100);
        assertEq(gameToken.balanceOf(airdropRecipient), (gameToken.TOTAL_SUPPLY() * 5) / 100);

        // gameRewardsPoolHolder's 2% was forwarded to gameEngine in BaseTest.setUp().
        assertEq(gameToken.balanceOf(gameRewardsPoolHolder), 0);
        assertEq(gameToken.balanceOf(address(gameEngine)), (gameToken.TOTAL_SUPPLY() * 2) / 100);
    }

    function testTaxAppliedOnAMMBuy() public {
        address pair = makeAddr("pair");
        vm.prank(owner);
        gameToken.setAMMPair(pair, true);

        vm.prank(lpRecipient); // exempt sender -> this leg is untaxed, just funding the "pool"
        gameToken.transfer(pair, 10_000 ether);

        uint256 aliceBefore = gameToken.balanceOf(alice);
        uint256 devBefore = gameToken.balanceOf(devTreasury);

        vm.prank(pair);
        gameToken.transfer(alice, 1000 ether); // taxed "buy": pair is an AMM pair, alice isn't exempt

        // 5% tax = 50; split 1%/3%/1% of the TRANSFER = 10 dev / 30 players / 10 LP.
        assertEq(gameToken.balanceOf(alice) - aliceBefore, 950 ether);
        assertEq(gameToken.balanceOf(devTreasury) - devBefore, 10 ether);
        assertEq(gameToken.pendingPlayersShare(), 30 ether);
        assertEq(gameToken.pendingLPShare(), 10 ether);
    }

    function testTaxSkippedForExemptRecipient() public {
        address pair = makeAddr("pair");
        vm.prank(owner);
        gameToken.setAMMPair(pair, true);
        vm.prank(owner);
        gameToken.setTaxExempt(alice, true);

        vm.prank(lpRecipient);
        gameToken.transfer(pair, 10_000 ether);

        uint256 aliceBefore = gameToken.balanceOf(alice);
        vm.prank(pair);
        gameToken.transfer(alice, 1000 ether);

        assertEq(gameToken.balanceOf(alice) - aliceBefore, 1000 ether); // full amount, no tax
    }

    function testTaxNotAppliedOnPlainWalletTransfer() public {
        // Neither side is an AMM pair -> no tax regardless of exemption status.
        uint256 bobBefore = gameToken.balanceOf(bob);
        vm.prank(alice);
        gameToken.transfer(bob, 1000 ether);
        assertEq(gameToken.balanceOf(bob) - bobBefore, 1000 ether);
    }

    function testSetTaxBpsCanOnlyLower() public {
        vm.startPrank(owner);
        gameToken.setTaxBps(400);
        assertEq(gameToken.taxBps(), 400);

        vm.expectRevert(GameToken.TaxCannotBeRaised.selector);
        gameToken.setTaxBps(500);
        vm.stopPrank();
    }

    function testBurnFromSpendsAllowance() public {
        vm.prank(alice);
        gameToken.approve(bob, 100 ether);

        uint256 supplyBefore = gameToken.totalSupply();
        vm.prank(bob);
        gameToken.burnFrom(alice, 100 ether);

        assertEq(supplyBefore - gameToken.totalSupply(), 100 ether);
        assertEq(gameToken.allowance(alice, bob), 0);
    }

    function testSweepPendingTaxRevertsIfNotTreasury() public {
        vm.expectRevert(GameToken.NotTreasury.selector);
        gameToken.sweepPendingTax();
    }

    function testSetTreasuryRevertsIfAlreadySet() public {
        // BaseTest.setUp() already called setTreasury once.
        vm.prank(owner);
        vm.expectRevert(GameToken.TreasuryAlreadySet.selector);
        gameToken.setTreasury(makeAddr("otherTreasury"));
    }
}
