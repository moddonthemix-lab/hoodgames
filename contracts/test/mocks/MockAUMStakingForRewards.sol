// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAUMStaking} from "../../src/interfaces/IAUMStaking.sol";

/// @notice Minimal IAUMStaking double. Multiplier defaults to 1x (WAD) unless set, so most
///         RewardsDistributor tests can ignore AUM weighting entirely and reason about
///         weightedScore == rawScore.
contract MockAUMStakingForRewards is IAUMStaking {
    uint256 public constant WAD = 1e18;

    mapping(uint256 => uint256) public aumOf;
    mapping(uint256 => uint256) private _multiplierOverride;
    mapping(uint256 => bool) private _hasOverride;

    function setMultiplier(uint256 tokenId, uint256 multiplierWad) external {
        _multiplierOverride[tokenId] = multiplierWad;
        _hasOverride[tokenId] = true;
    }

    function aumMultiplier(uint256 tokenId) external view returns (uint256) {
        return _hasOverride[tokenId] ? _multiplierOverride[tokenId] : WAD;
    }
}
