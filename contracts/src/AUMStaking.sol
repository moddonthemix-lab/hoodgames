// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAUMStaking} from "./interfaces/IAUMStaking.sol";
import {IGameToken} from "./interfaces/IGameToken.sol";
import {IFundNFT} from "./interfaces/IFundNFT.sol";
import {IRewardsDistributor} from "./interfaces/IRewardsDistributor.sol";
import {GameMath} from "./libraries/GameMath.sol";

/// @title AUMStaking
/// @notice Per-fund $MGN staking. Staked amount feeds GameMath.computeAumMultiplier, which
///         RewardsDistributor reads to weight ETH reward share — it never touches the leaderboard
///         score in GameEngine (see DECISIONS.md "AUM multiplier scope"). Two unstake paths per
///         MARGIN_SPEC.md section 3: a free 7-day cooldown, or an instant 5% exit fee (burned).
contract AUMStaking is Ownable, Pausable, ReentrancyGuard, IAUMStaking {
    using SafeERC20 for IGameToken;

    struct StakeInfo {
        uint128 staked;
        uint128 pendingUnstake;
        uint64 cooldownEnd;
    }

    uint256 public constant UNSTAKE_COOLDOWN = 7 days;
    uint256 public constant EXIT_FEE_BPS = 500;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    IFundNFT public immutable fundNFT;
    IGameToken public immutable gameToken;
    IRewardsDistributor public immutable rewardsDistributor;

    mapping(uint256 => StakeInfo) public stakes;

    event Staked(uint256 indexed tokenId, uint256 amount);
    event UnstakeRequested(uint256 indexed tokenId, uint256 amount, uint64 cooldownEnd);
    event UnstakeCompleted(uint256 indexed tokenId, uint256 amount);
    event UnstakeInstant(uint256 indexed tokenId, uint256 amount, uint256 fee);

    error NotFundOwner();
    error InsufficientStake();
    error PendingUnstakeExists();
    error NoPendingUnstake();
    error CooldownNotElapsed();

    modifier onlyFundOwner(uint256 tokenId) {
        if (msg.sender != fundNFT.ownerOf(tokenId)) revert NotFundOwner();
        _;
    }

    constructor(address initialOwner, IFundNFT _fundNFT, IGameToken _gameToken, IRewardsDistributor _rewardsDistributor)
        Ownable(initialOwner)
    {
        fundNFT = _fundNFT;
        gameToken = _gameToken;
        rewardsDistributor = _rewardsDistributor;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc IAUMStaking
    function aumOf(uint256 tokenId) external view returns (uint256) {
        return stakes[tokenId].staked;
    }

    /// @inheritdoc IAUMStaking
    function aumMultiplier(uint256 tokenId) external view returns (uint256) {
        return GameMath.computeAumMultiplier(stakes[tokenId].staked);
    }

    /// @notice Stakes `amount` of $MGN into `tokenId`'s AUM. Requires prior ERC20 approval.
    function stake(uint256 tokenId, uint256 amount) external whenNotPaused nonReentrant onlyFundOwner(tokenId) {
        gameToken.safeTransferFrom(msg.sender, address(this), amount);
        stakes[tokenId].staked += uint128(amount);
        rewardsDistributor.syncFund(tokenId);
        emit Staked(tokenId, amount);
    }

    /// @notice Starts the free 7-day unstake cooldown. Only one pending request at a time —
    ///         complete or the amount stops counting toward AUM immediately (removed from
    ///         `staked` on request, not on completion).
    function requestUnstake(uint256 tokenId, uint256 amount) external whenNotPaused onlyFundOwner(tokenId) {
        StakeInfo storage s = stakes[tokenId];
        if (s.pendingUnstake != 0) revert PendingUnstakeExists();
        if (s.staked < amount) revert InsufficientStake();

        s.staked -= uint128(amount);
        s.pendingUnstake = uint128(amount);
        s.cooldownEnd = uint64(block.timestamp) + uint64(UNSTAKE_COOLDOWN);

        rewardsDistributor.syncFund(tokenId);
        emit UnstakeRequested(tokenId, amount, s.cooldownEnd);
    }

    /// @notice Withdraws a completed cooldown unstake request.
    function completeUnstake(uint256 tokenId) external whenNotPaused nonReentrant onlyFundOwner(tokenId) {
        StakeInfo storage s = stakes[tokenId];
        if (s.pendingUnstake == 0) revert NoPendingUnstake();
        if (block.timestamp < s.cooldownEnd) revert CooldownNotElapsed();

        uint256 amount = s.pendingUnstake;
        s.pendingUnstake = 0;
        s.cooldownEnd = 0;

        gameToken.safeTransfer(msg.sender, amount);
        emit UnstakeCompleted(tokenId, amount);
    }

    /// @notice Instantly unstakes `amount`, skipping the cooldown, paying a 5% exit fee (burned —
    ///         see DECISIONS.md for why this is burned rather than routed to RewardsDistributor).
    function unstakeInstant(uint256 tokenId, uint256 amount) external whenNotPaused nonReentrant onlyFundOwner(tokenId) {
        StakeInfo storage s = stakes[tokenId];
        if (s.staked < amount) revert InsufficientStake();

        s.staked -= uint128(amount);
        uint256 fee = (amount * EXIT_FEE_BPS) / BPS_DENOMINATOR;
        uint256 payout = amount - fee;

        if (fee > 0) gameToken.burn(fee);
        gameToken.safeTransfer(msg.sender, payout);

        rewardsDistributor.syncFund(tokenId);
        emit UnstakeInstant(tokenId, payout, fee);
    }
}
