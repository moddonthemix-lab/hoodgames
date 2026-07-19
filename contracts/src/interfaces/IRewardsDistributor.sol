// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IRewardsDistributor
/// @notice ETH rewards pool. Pro-rata by `score * aumMultiplier` (see GameMath), Synthetix-style
///         accumulator keyed by Fund NFT tokenId (so accrued rewards travel with the NFT).
interface IRewardsDistributor {
    /// @notice Re-reads this fund's current score (from GameEngine) and AUM multiplier (from
    ///         AUMStaking), settles pending rewards against the old weighting, then re-weights.
    ///         Permissionless and idempotent — callers just need it to have run before they read
    ///         `rewards(tokenId)`. GameEngine and AUMStaking call this after every state change
    ///         that could move a fund's score or multiplier.
    function syncFund(uint256 tokenId) external;

    /// @notice Generic ETH inflow: tax share sweeps, action fees, recap penalties.
    function depositRewards() external payable;

    /// @notice Called by GameEngine during liquidation to settle this fund's full accrued
    ///         balance to `fundOwner`'s pull-payment balance (never pushed directly — a hostile
    ///         or non-receiving owner must never be able to block liquidation), pay a best-effort
    ///         bounty to `bountyRecipient`, and zero the fund's weighting. Restricted to GameEngine.
    function settleOnLiquidation(uint256 tokenId, address fundOwner, address bountyRecipient, uint256 bountyAmount)
        external
        returns (uint256 totalAccrued);

    /// @notice Called by GameEngine during a takeover to move `bps` of the defender's currently
    ///         accrued unclaimed rewards to the attacker's accrued balance. Restricted to GameEngine.
    function seizeRewards(uint256 fromTokenId, uint256 toTokenId, uint256 bps) external returns (uint256 amount);

    /// @notice Pull-payment withdrawal of any balance credited via settleOnLiquidation.
    function withdraw() external;
}
