// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";
import {AUMStaking} from "../src/AUMStaking.sol";
import {GameMath} from "../src/libraries/GameMath.sol";

contract AUMStakingTest is BaseTest {
    bytes32 constant S0 = keccak256("s0");

    uint256 tokenId;

    function setUp() public override {
        super.setUp();
        tokenId = _mintFund(alice, S0);
    }

    // ---- stake ----

    function testStakeHappyPath() public {
        uint256 balBefore = gameToken.balanceOf(alice);

        vm.prank(alice);
        aumStaking.stake(tokenId, 1000 ether);

        assertEq(aumStaking.aumOf(tokenId), 1000 ether);
        assertEq(balBefore - gameToken.balanceOf(alice), 1000 ether);
        assertEq(aumStaking.aumMultiplier(tokenId), GameMath.computeAumMultiplier(1000 ether));
        assertGt(aumStaking.aumMultiplier(tokenId), 1e18); // strictly above 1x once staked
    }

    function testStakeRevertsIfNotFundOwner() public {
        vm.prank(bob);
        vm.expectRevert(AUMStaking.NotFundOwner.selector);
        aumStaking.stake(tokenId, 1000 ether);
    }

    // ---- requestUnstake / completeUnstake ----

    function testRequestUnstakeMovesToPending() public {
        vm.startPrank(alice);
        aumStaking.stake(tokenId, 1000 ether);
        aumStaking.requestUnstake(tokenId, 400 ether);
        vm.stopPrank();

        assertEq(aumStaking.aumOf(tokenId), 600 ether);
        (uint128 staked, uint128 pending, uint64 cooldownEnd) = aumStaking.stakes(tokenId);
        assertEq(staked, 600 ether);
        assertEq(pending, 400 ether);
        assertEq(cooldownEnd, block.timestamp + aumStaking.UNSTAKE_COOLDOWN());
    }

    function testRequestUnstakeRevertsIfPendingExists() public {
        vm.startPrank(alice);
        aumStaking.stake(tokenId, 1000 ether);
        aumStaking.requestUnstake(tokenId, 200 ether);
        vm.expectRevert(AUMStaking.PendingUnstakeExists.selector);
        aumStaking.requestUnstake(tokenId, 100 ether);
        vm.stopPrank();
    }

    function testRequestUnstakeRevertsInsufficientStake() public {
        vm.startPrank(alice);
        aumStaking.stake(tokenId, 100 ether);
        vm.expectRevert(AUMStaking.InsufficientStake.selector);
        aumStaking.requestUnstake(tokenId, 200 ether);
        vm.stopPrank();
    }

    function testCompleteUnstakeRevertsBeforeCooldown() public {
        vm.startPrank(alice);
        aumStaking.stake(tokenId, 1000 ether);
        aumStaking.requestUnstake(tokenId, 400 ether);
        vm.expectRevert(AUMStaking.CooldownNotElapsed.selector);
        aumStaking.completeUnstake(tokenId);
        vm.stopPrank();
    }

    function testCompleteUnstakeRevertsNoPending() public {
        vm.prank(alice);
        vm.expectRevert(AUMStaking.NoPendingUnstake.selector);
        aumStaking.completeUnstake(tokenId);
    }

    function testCompleteUnstakeHappyPath() public {
        vm.startPrank(alice);
        aumStaking.stake(tokenId, 1000 ether);
        aumStaking.requestUnstake(tokenId, 400 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + aumStaking.UNSTAKE_COOLDOWN());
        uint256 balBefore = gameToken.balanceOf(alice);

        vm.prank(alice);
        aumStaking.completeUnstake(tokenId);

        assertEq(gameToken.balanceOf(alice) - balBefore, 400 ether);
        (, uint128 pending, uint64 cooldownEnd) = aumStaking.stakes(tokenId);
        assertEq(pending, 0);
        assertEq(cooldownEnd, 0);
    }

    // ---- unstakeInstant ----

    function testUnstakeInstantChargesFeeAndBurns() public {
        vm.startPrank(alice);
        aumStaking.stake(tokenId, 1000 ether);
        vm.stopPrank();

        uint256 supplyBefore = gameToken.totalSupply();
        uint256 balBefore = gameToken.balanceOf(alice);

        vm.prank(alice);
        aumStaking.unstakeInstant(tokenId, 1000 ether);

        // 5% exit fee: 950 returned, 50 burned from total supply.
        assertEq(gameToken.balanceOf(alice) - balBefore, 950 ether);
        assertEq(supplyBefore - gameToken.totalSupply(), 50 ether);
        assertEq(aumStaking.aumOf(tokenId), 0);
    }

    function testUnstakeInstantRevertsInsufficientStake() public {
        vm.prank(alice);
        vm.expectRevert(AUMStaking.InsufficientStake.selector);
        aumStaking.unstakeInstant(tokenId, 1 ether);
    }
}
