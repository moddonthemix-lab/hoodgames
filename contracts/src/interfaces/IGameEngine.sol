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

    struct FundView {
        uint32 traders;
        uint32 desks;
        uint64 lastRebalance;
        /// @dev The rebalance deadline (lastRebalance + EPOCH_LENGTH), always populated —
        ///      NOT "0 if not margin-called". Check `status` for the derived current state;
        ///      compare against this timestamp for a countdown regardless of status.
        uint64 marginCalledAt;
        uint128 score;
        uint128 yieldBalance;
        uint128 capitalBalance;
        /// @dev Always 0 — $MGN emissions are paid directly on rebalance, not accrued as a
        ///      separate claimable balance. Kept for frontend/ABI stability; may be removed.
        uint128 pendingTokenRewards;
        FundStatus status;
    }

    function getFund(uint256 tokenId) external view returns (FundView memory);

    function totalScore() external view returns (uint256);

    /// @notice Resets a fund's stats to zero on full redemption (NFT is NOT burned — the fund
    ///         lives on from zero, matching Stoke Fire's "village resets to 0"). Restricted to
    ///         RewardsDistributor, called from its claim().
    function resetFundForRedemption(uint256 tokenId) external;

    /// @notice Reduces a fund's score by `bps` (out of 10,000) on partial redemption. Restricted
    ///         to RewardsDistributor, called from its claimPartial().
    function applyScoreHaircut(uint256 tokenId, uint256 bps) external;
}
