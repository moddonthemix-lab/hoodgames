// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";
import {IGameEngine} from "../src/interfaces/IGameEngine.sol";

/// @title LifeOfAFundTest
/// @notice Full integration test per the Phase 2 plan: mint -> rebalance x5 -> miss -> margin
///         call -> recapitalize -> redeem. Asserts fund state at every step, not just the end.
contract LifeOfAFundTest is BaseTest {
    function testFullLifeOfAFund() public {
        bytes32[7] memory secrets = [
            keccak256("life0"),
            keccak256("life1"),
            keccak256("life2"),
            keccak256("life3"),
            keccak256("life4"),
            keccak256("life5"),
            keccak256("life6")
        ];

        // ---- 1. Mint ----
        uint256 tokenId = _mintFund(alice, secrets[0]);
        assertEq(uint256(gameEngine.getStatus(tokenId)), uint256(IGameEngine.FundStatus.Active));
        assertEq(gameEngine.getFund(tokenId).score, 0);

        // ---- 2. Rebalance x5, each comfortably inside the 72h window ----
        for (uint256 i = 0; i < 5; i++) {
            vm.warp(block.timestamp + 30 hours);
            _rebalance(alice, tokenId, secrets[i], secrets[i + 1]);
            assertEq(
                uint256(gameEngine.getStatus(tokenId)), uint256(IGameEngine.FundStatus.Active), "should stay Active"
            );
        }
        IGameEngine.FundView memory afterFive = gameEngine.getFund(tokenId);
        assertGt(afterFive.score, 0, "5 rebalances should have accrued some score");

        // ---- 3. Miss the next rebalance deadline -> margin call ----
        _warpPastDeadline(tokenId);
        assertEq(uint256(gameEngine.getStatus(tokenId)), uint256(IGameEngine.FundStatus.MarginCalled));

        // Confirm rebalance is no longer callable in this state (must recapitalize instead).
        vm.prank(alice);
        vm.expectRevert(); // NotActive
        gameEngine.rebalance(tokenId, secrets[5], _commitment(secrets[6]));

        // ---- 4. Recapitalize to clear the margin call ----
        // 0 workers throughout this test (nobody hired) -> recap cost is the flat base cost.
        uint256 recapCost = 0.01 ether;
        vm.prank(alice);
        gameEngine.recapitalize{value: recapCost}(tokenId);
        assertEq(uint256(gameEngine.getStatus(tokenId)), uint256(IGameEngine.FundStatus.Active));

        // ---- 5. Redeem: full claim resets the fund, NFT survives, ETH becomes withdrawable ----
        uint256 accrued = rewardsDistributor.earned(tokenId);
        assertGt(accrued, 0, "mint fee + recap pool-share should have accrued as ETH rewards");

        vm.prank(alice);
        rewardsDistributor.claim(tokenId);

        IGameEngine.FundView memory afterClaim = gameEngine.getFund(tokenId);
        assertEq(afterClaim.score, 0);
        assertEq(afterClaim.hackers, 0);
        assertEq(afterClaim.analysts, 0);
        assertEq(afterClaim.brokers, 0);
        assertEq(afterClaim.computers, 0);
        assertTrue(fundNFT.exists(tokenId), "full redemption resets stats but does not burn the NFT");
        assertEq(fundNFT.ownerOf(tokenId), alice);

        uint256 balBefore = alice.balance;
        vm.prank(alice);
        rewardsDistributor.withdraw();
        assertApproxEqAbs(alice.balance - balBefore, accrued, 1);
        assertEq(rewardsDistributor.withdrawable(alice), 0);
    }
}
