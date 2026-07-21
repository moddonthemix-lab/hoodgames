// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGameEngine} from "../../src/interfaces/IGameEngine.sol";

/// @notice Minimal IGameEngine double for isolating RewardsDistributor's accumulator math from
///         full gameplay mechanics. Scores are set directly by the test instead of being derived
///         from rebalance/payroll/takeover logic (that logic is covered by GameEngine.t.sol).
contract MockGameEngineForRewards is IGameEngine {
    mapping(uint256 => uint128) public scoreOf;
    uint256 public totalScore;

    address public rewardsDistributor;

    error NotRewardsDistributor();

    modifier onlyRewardsDistributor() {
        if (msg.sender != rewardsDistributor) revert NotRewardsDistributor();
        _;
    }

    function setRewardsDistributor(address _rewardsDistributor) external {
        rewardsDistributor = _rewardsDistributor;
    }

    function setScore(uint256 tokenId, uint128 newScore) external {
        totalScore = totalScore - scoreOf[tokenId] + newScore;
        scoreOf[tokenId] = newScore;
    }

    function getFund(uint256 tokenId) external view returns (FundView memory) {
        return FundView({
            hackers: 0,
            analysts: 0,
            brokers: 0,
            computers: 0,
            lastRebalance: 0,
            marginCalledAt: 0,
            yieldCooldownEnd: 0,
            capitalCooldownEnd: 0,
            score: scoreOf[tokenId],
            yieldBalance: 0,
            capitalBalance: 0,
            status: FundStatus.Active
        });
    }

    function resetFundForRedemption(uint256 tokenId) external onlyRewardsDistributor {
        totalScore -= scoreOf[tokenId];
        scoreOf[tokenId] = 0;
    }

    function applyScoreHaircut(uint256 tokenId, uint256 bps) external onlyRewardsDistributor {
        uint256 loss = (uint256(scoreOf[tokenId]) * bps) / 10_000;
        scoreOf[tokenId] -= uint128(loss);
        totalScore -= loss;
    }
}
