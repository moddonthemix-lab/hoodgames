// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FundNFT} from "../src/FundNFT.sol";
import {GameToken} from "../src/GameToken.sol";
import {GameEngine} from "../src/GameEngine.sol";
import {RewardsDistributor} from "../src/RewardsDistributor.sol";
import {AUMStaking} from "../src/AUMStaking.sol";
import {Treasury} from "../src/Treasury.sol";
import {IFundNFT} from "../src/interfaces/IFundNFT.sol";
import {IGameToken} from "../src/interfaces/IGameToken.sol";
import {IRewardsDistributor} from "../src/interfaces/IRewardsDistributor.sol";

/// @title BaseTest
/// @notice Shared fixture: deploys and wires the full MARGIN suite exactly like
///         script/Deploy.s.sol, and provides commit-reveal / time-warp helpers reused across
///         every other test file.
abstract contract BaseTest is Test {
    FundNFT internal fundNFT;
    GameToken internal gameToken;
    GameEngine internal gameEngine;
    RewardsDistributor internal rewardsDistributor;
    AUMStaking internal aumStaking;
    Treasury internal treasury;

    address internal owner = makeAddr("owner");
    address internal devTreasury = makeAddr("devTreasury");
    address internal lpRecipient = makeAddr("lpRecipient");
    address internal devRecipient = makeAddr("devRecipient");
    address internal airdropRecipient = makeAddr("airdropRecipient");
    address internal gameRewardsPoolHolder = makeAddr("gameRewardsPoolHolder");
    address internal lpLockRecipient = address(0x000000000000000000000000000000000000dEaD);
    address internal mockRouter = makeAddr("mockRouter");

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal keeper = makeAddr("keeper");

    uint256 internal constant MINT_FEE = 0.001 ether;
    uint256 internal constant PLAYER_MGN_SEED = 100_000 ether;

    function setUp() public virtual {
        vm.startPrank(owner);

        fundNFT = new FundNFT(owner);
        gameToken =
            new GameToken(owner, devTreasury, lpRecipient, devRecipient, airdropRecipient, gameRewardsPoolHolder);
        gameEngine = new GameEngine(owner, IFundNFT(address(fundNFT)), IGameToken(address(gameToken)));
        fundNFT.setGameEngine(address(gameEngine));

        rewardsDistributor = new RewardsDistributor(owner);
        gameEngine.setRewardsDistributor(IRewardsDistributor(address(rewardsDistributor)));
        rewardsDistributor.setGameEngine(address(gameEngine));
        rewardsDistributor.setFundNFT(address(fundNFT));

        aumStaking = new AUMStaking(
            owner, IFundNFT(address(fundNFT)), IGameToken(address(gameToken)), IRewardsDistributor(address(rewardsDistributor))
        );
        rewardsDistributor.setAumStaking(address(aumStaking));

        treasury = new Treasury(
            owner, IGameToken(address(gameToken)), IRewardsDistributor(address(rewardsDistributor)), mockRouter, lpLockRecipient
        );
        gameEngine.setTreasury(address(treasury));
        gameToken.setTreasury(address(treasury));

        gameToken.setTaxExempt(address(gameEngine), true);
        gameToken.setTaxExempt(address(aumStaking), true);
        gameToken.setTaxExempt(address(rewardsDistributor), true);

        vm.stopPrank();

        vm.prank(gameRewardsPoolHolder);
        gameToken.transfer(address(gameEngine), gameToken.balanceOf(gameRewardsPoolHolder));

        vm.startPrank(lpRecipient);
        gameToken.transfer(alice, PLAYER_MGN_SEED);
        gameToken.transfer(bob, PLAYER_MGN_SEED);
        gameToken.transfer(carol, PLAYER_MGN_SEED);
        vm.stopPrank();

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
        vm.deal(keeper, 10 ether);

        // Rebalance/takeover burns and AUM staking both need standing approval from test players.
        vm.prank(alice);
        gameToken.approve(address(gameEngine), type(uint256).max);
        vm.prank(bob);
        gameToken.approve(address(gameEngine), type(uint256).max);
        vm.prank(carol);
        gameToken.approve(address(gameEngine), type(uint256).max);

        vm.prank(alice);
        gameToken.approve(address(aumStaking), type(uint256).max);
        vm.prank(bob);
        gameToken.approve(address(aumStaking), type(uint256).max);
        vm.prank(carol);
        gameToken.approve(address(aumStaking), type(uint256).max);
    }

    // ---- Commit-reveal helpers ----
    // GameEngine's reveal check is keccak256(reveal) == storedCommitment, deliberately NOT bound
    // to tokenId (see GameEngine.sol NatSpec — the tokenId doesn't exist yet at mint time).

    function _commitment(bytes32 secret) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(secret));
    }

    function _mintFund(address player, bytes32 secret) internal returns (uint256 tokenId) {
        vm.prank(player);
        tokenId = gameEngine.mintFund{value: MINT_FEE}(_commitment(secret));
    }

    /// @notice Warps forward and rebalances using `secret` (must match the currently-committed
    ///         value) then re-arms with `nextSecret`.
    function _rebalance(address player, uint256 tokenId, bytes32 secret, bytes32 nextSecret) internal {
        vm.prank(player);
        gameEngine.rebalance(tokenId, secret, _commitment(nextSecret));
    }

    /// @notice Warps forward just enough for resource accrual to cover rebalance costs, then
    ///         calls rebalance. Convenience for tests that don't care about exact timing.
    function _warpAndRebalance(address player, uint256 tokenId, bytes32 secret, bytes32 nextSecret) internal {
        vm.warp(block.timestamp + gameEngine.EPOCH_LENGTH() - 1 hours);
        _rebalance(player, tokenId, secret, nextSecret);
    }

    function _warpPastDeadline(uint256 tokenId) internal {
        uint64 lastRebalance = gameEngine.getFund(tokenId).lastRebalance;
        vm.warp(uint256(lastRebalance) + gameEngine.EPOCH_LENGTH() + 1);
    }

    function _warpPastGrace(uint256 tokenId) internal {
        uint64 lastRebalance = gameEngine.getFund(tokenId).lastRebalance;
        vm.warp(uint256(lastRebalance) + gameEngine.EPOCH_LENGTH() + gameEngine.MARGIN_CALL_GRACE() + 1);
    }
}
