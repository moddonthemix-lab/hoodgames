// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IAUMStaking
/// @notice Per-fund $MGN staking. Staked amount feeds GameMath.computeAumMultiplier for
///         reward-share weighting only — it never touches the leaderboard score.
interface IAUMStaking {
    function aumOf(uint256 tokenId) external view returns (uint256);

    /// @notice Wad-scaled (1e18 = 1.0x) reward-weighting multiplier for this fund's staked AUM.
    function aumMultiplier(uint256 tokenId) external view returns (uint256);
}
