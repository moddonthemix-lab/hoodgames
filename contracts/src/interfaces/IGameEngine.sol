// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IGameEngine
/// @notice Core game loop and sole source of truth for fund state. Consumed by FundNFT
///         (dynamic tokenURI) and off-chain indexers/frontend.
interface IGameEngine {
    enum FundStatus {
        Active,
        MarginCalled,
        Liquidated
    }

    /// @notice The three hireable worker roles (see hire()). Each specializes on one axis:
    ///         Hacker = takeover offense/defense, Analyst = score/P&L per rebalance, Broker = income.
    enum Role {
        Hacker,
        Analyst,
        Broker
    }

    struct FundView {
        uint32 hackers;
        uint32 analysts;
        uint32 brokers;
        uint32 computers;
        uint64 lastRebalance;
        /// @dev The rebalance deadline (lastRebalance + EPOCH_LENGTH), always populated. Check
        ///      `status` for the derived current state; compare against this for a countdown.
        uint64 marginCalledAt;
        uint128 score;
        uint128 yieldBalance;
        uint128 capitalBalance;
        FundStatus status;
    }

    function getFund(uint256 tokenId) external view returns (FundView memory);

    function totalScore() external view returns (uint256);

    /// @notice Resets a fund's stats to zero on full redemption (NFT is NOT burned — the fund
    ///         lives on from zero). Restricted to RewardsDistributor, called from its claim().
    function resetFundForRedemption(uint256 tokenId) external;

    /// @notice Reduces a fund's score by `bps` (out of 10,000) on partial redemption. Restricted
    ///         to RewardsDistributor, called from its claimPartial().
    function applyScoreHaircut(uint256 tokenId, uint256 bps) external;
}
