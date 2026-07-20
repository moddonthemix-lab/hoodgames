// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";
import {GameEngine} from "../src/GameEngine.sol";
import {IGameEngine} from "../src/interfaces/IGameEngine.sol";

/// @title LiquidationRaceTest
/// @notice liquidate() is permissionless and keeper-bountied, so multiple actors racing for the
///         same bounty (or a fund owner racing to recapitalize before a keeper liquidates) is a
///         realistic scenario. The EVM is single-threaded — there's no real concurrency to test —
///         but these tests confirm the SEQUENCE of two competing transactions resolves cleanly:
///         exactly one winner, no double-payout, no stuck state.
contract LiquidationRaceTest is BaseTest {
    bytes32 constant S0 = keccak256("s0");
    bytes32 constant S1 = keccak256("s1");

    function testSecondLiquidatorLosesTheRace() public {
        uint256 tokenId = _mintFund(alice, S0);
        _warpPastGrace(tokenId);

        address keeper1 = makeAddr("keeper1");
        address keeper2 = makeAddr("keeper2");

        vm.prank(keeper1);
        gameEngine.liquidate(tokenId);
        assertEq(keeper1.balance, gameEngine.LIQUIDATION_BOUNTY(), "winner gets the bounty");

        vm.prank(keeper2);
        vm.expectRevert(GameEngine.AlreadyLiquidated.selector);
        gameEngine.liquidate(tokenId);
        assertEq(keeper2.balance, 0, "loser gets nothing, not a partial or duplicate payout");
    }

    function testIndependentFundsEachPayTheirOwnBounty() public {
        uint256 id1 = _mintFund(alice, S0);
        uint256 id2 = _mintFund(bob, S1);
        _warpPastGrace(id1);
        _warpPastGrace(id2);

        address keeper1 = makeAddr("keeper1");
        address keeper2 = makeAddr("keeper2");

        vm.prank(keeper1);
        gameEngine.liquidate(id1);
        vm.prank(keeper2);
        gameEngine.liquidate(id2);

        assertEq(keeper1.balance, gameEngine.LIQUIDATION_BOUNTY());
        assertEq(keeper2.balance, gameEngine.LIQUIDATION_BOUNTY());
        assertFalse(fundNFT.exists(id1));
        assertFalse(fundNFT.exists(id2));
    }

    /// @dev isLiquidationEligible uses a strict `>` on (deadline + grace) — exactly at the
    ///      boundary the fund is still recap-eligible, not yet liquidation-eligible. This is the
    ///      race the owner is actually trying to win in practice: get a recapitalize() into a
    ///      block before a keeper's liquidate() lands.
    function testOwnerRecapitalizingExactlyAtGraceBoundaryBeatsLiquidation() public {
        uint256 tokenId = _mintFund(alice, S0);
        IGameEngine.FundView memory f = gameEngine.getFund(tokenId);
        vm.warp(uint256(f.lastRebalance) + gameEngine.EPOCH_LENGTH() + gameEngine.MARGIN_CALL_GRACE());

        vm.prank(alice);
        gameEngine.recapitalize{value: 1 ether}(tokenId);
        assertEq(uint256(gameEngine.getStatus(tokenId)), uint256(IGameEngine.FundStatus.Active));

        // A keeper racing to liquidate in the very next transaction now correctly fails: the
        // owner's recapitalize landed first and reset the clock.
        vm.expectRevert(GameEngine.NotYetLiquidationEligible.selector);
        gameEngine.liquidate(tokenId);
    }

    function testLiquidateRevertsExactlyAtGraceBoundary() public {
        uint256 tokenId = _mintFund(alice, S0);
        IGameEngine.FundView memory f = gameEngine.getFund(tokenId);
        vm.warp(uint256(f.lastRebalance) + gameEngine.EPOCH_LENGTH() + gameEngine.MARGIN_CALL_GRACE());

        vm.expectRevert(GameEngine.NotYetLiquidationEligible.selector);
        gameEngine.liquidate(tokenId);
    }

    function testLiquidateSucceedsOneSecondAfterGraceExpires() public {
        uint256 tokenId = _mintFund(alice, S0);
        _warpPastGrace(tokenId); // deadline + grace + 1
        gameEngine.liquidate(tokenId);
        assertFalse(fundNFT.exists(tokenId));
    }

    /// @dev A recapitalize() attempt landing AFTER a keeper's liquidate() has already gone
    ///      through should fail cleanly (fund no longer exists in an active state) rather than
    ///      corrupt state or double-charge the owner.
    function testRecapitalizeAfterLiquidationFails() public {
        uint256 tokenId = _mintFund(alice, S0);
        _warpPastGrace(tokenId);
        gameEngine.liquidate(tokenId);

        vm.prank(alice);
        vm.expectRevert(GameEngine.AlreadyLiquidated.selector);
        gameEngine.recapitalize{value: 1 ether}(tokenId);
    }
}
