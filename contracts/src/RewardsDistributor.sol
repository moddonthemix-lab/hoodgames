// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IRewardsDistributor} from "./interfaces/IRewardsDistributor.sol";
import {IGameEngine} from "./interfaces/IGameEngine.sol";
import {IAUMStaking} from "./interfaces/IAUMStaking.sol";
import {IFundNFT} from "./interfaces/IFundNFT.sol";

/// @title RewardsDistributor
/// @notice The ETH rewards pool. Index-based pro-rata accumulator (MasterChef/Synthetix-style
///         `rewardPerWeightedScore`, O(1) per fund, no loops over players) keyed by Fund NFT
///         tokenId so accrued rewards travel with the NFT on transfer. Weighting is
///         `score * aumMultiplier` — see GameEngine/GameMath and DECISIONS.md "AUM multiplier
///         scope" for why AUM never touches the raw leaderboard score.
/// @dev Pull-payment throughout: claim/claimPartial/liquidation settlement all credit
///      `withdrawable[account]` rather than pushing ETH, so a hostile or non-receiving recipient
///      can never block another user's action (e.g. liquidate() must always succeed).
contract RewardsDistributor is Ownable, Pausable, ReentrancyGuard, IRewardsDistributor {
    uint256 public constant WAD = 1e18;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Partial redemption: payout 50% of accrued, forfeit the rest to the pool, 50% score
    ///         haircut, 24h cooldown before the next partial/full redemption. DECISIONS.md defaults.
    uint256 public constant PARTIAL_PAYOUT_BPS = 5000;
    uint256 public constant PARTIAL_SCORE_HAIRCUT_BPS = 5000;
    uint256 public constant PARTIAL_REDEMPTION_COOLDOWN = 24 hours;

    address public gameEngine;
    address public aumStaking;
    address public fundNFT;

    uint256 public rewardPerWeightedScoreStored;
    uint256 public totalWeightedScore;
    /// @notice ETH received while totalWeightedScore == 0 (no funds minted yet) — rolled forward
    ///         and applied on the next deposit once there's a weighting to distribute against,
    ///         so bootstrap-phase deposits are never silently stranded.
    uint256 public undistributedRewards;

    mapping(uint256 => uint256) public weightedScore;
    mapping(uint256 => uint256) public userRewardPerWeightedScorePaid;
    mapping(uint256 => uint256) public rewards;
    mapping(uint256 => uint64) public partialRedemptionCooldownEnd;
    mapping(address => uint256) public withdrawable;

    event RewardsDeposited(uint256 amount);
    event FundSynced(uint256 indexed tokenId, uint256 weightedScore);
    event Claimed(uint256 indexed tokenId, address indexed to, uint256 amount, bool isPartial);
    event LiquidationSettled(
        uint256 indexed tokenId, address indexed fundOwner, uint256 amount, address bountyRecipient, uint256 bountyAmount, bool bountyPaid
    );
    event RewardsSeized(uint256 indexed fromTokenId, uint256 indexed toTokenId, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);

    error AlreadySet();
    error ZeroAddress();
    error NotGameEngine();
    error NotFundOwner();
    error CooldownActive();
    error NothingToWithdraw();
    error TransferFailed();

    modifier onlyGameEngine() {
        if (msg.sender != gameEngine) revert NotGameEngine();
        _;
    }

    constructor(address initialOwner) Ownable(initialOwner) {}

    // ---- One-time wiring (see FundNFT.setGameEngine for the pattern and rationale) ----

    function setGameEngine(address _gameEngine) external onlyOwner {
        if (gameEngine != address(0)) revert AlreadySet();
        if (_gameEngine == address(0)) revert ZeroAddress();
        gameEngine = _gameEngine;
    }

    function setAumStaking(address _aumStaking) external onlyOwner {
        if (aumStaking != address(0)) revert AlreadySet();
        if (_aumStaking == address(0)) revert ZeroAddress();
        aumStaking = _aumStaking;
    }

    function setFundNFT(address _fundNFT) external onlyOwner {
        if (fundNFT != address(0)) revert AlreadySet();
        if (_fundNFT == address(0)) revert ZeroAddress();
        fundNFT = _fundNFT;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ---- Views ----

    function earned(uint256 tokenId) public view returns (uint256) {
        return rewards[tokenId]
            + (weightedScore[tokenId] * (rewardPerWeightedScoreStored - userRewardPerWeightedScorePaid[tokenId])) / WAD;
    }

    // ---- Core accumulator ----

    function _settle(uint256 tokenId) internal {
        rewards[tokenId] = earned(tokenId);
        userRewardPerWeightedScorePaid[tokenId] = rewardPerWeightedScoreStored;
    }

    function _reweight(uint256 tokenId) internal {
        uint256 rawScore = IGameEngine(gameEngine).getFund(tokenId).score;
        uint256 multiplier = aumStaking == address(0) ? WAD : IAUMStaking(aumStaking).aumMultiplier(tokenId);
        uint256 newWeighted = (rawScore * multiplier) / WAD;
        totalWeightedScore = totalWeightedScore - weightedScore[tokenId] + newWeighted;
        weightedScore[tokenId] = newWeighted;
        emit FundSynced(tokenId, newWeighted);
    }

    function _depositInternal(uint256 amount) internal {
        uint256 pool = amount + undistributedRewards;
        if (totalWeightedScore > 0 && pool > 0) {
            rewardPerWeightedScoreStored += (pool * WAD) / totalWeightedScore;
            undistributedRewards = 0;
        } else {
            undistributedRewards += amount;
        }
        emit RewardsDeposited(amount);
    }

    /// @inheritdoc IRewardsDistributor
    function syncFund(uint256 tokenId) external {
        _settle(tokenId);
        _reweight(tokenId);
    }

    /// @inheritdoc IRewardsDistributor
    function depositRewards() external payable {
        _depositInternal(msg.value);
    }

    // ---- Redemption ----

    /// @notice Full redemption: claims 100% of accrued ETH (to a pull-payment balance) and resets
    ///         the fund's stats to zero via GameEngine. The Fund NFT is NOT burned.
    function claim(uint256 tokenId) external whenNotPaused nonReentrant {
        if (msg.sender != IFundNFT(fundNFT).ownerOf(tokenId)) revert NotFundOwner();

        _settle(tokenId);
        uint256 amount = rewards[tokenId];
        rewards[tokenId] = 0;
        totalWeightedScore -= weightedScore[tokenId];
        weightedScore[tokenId] = 0;

        IGameEngine(gameEngine).resetFundForRedemption(tokenId);

        withdrawable[msg.sender] += amount;
        emit Claimed(tokenId, msg.sender, amount, false);
    }

    /// @notice Partial redemption: pays out 50% of accrued ETH now, forfeits the rest back to the
    ///         pool, applies a 50% score haircut (via GameEngine — fund keeps playing, doesn't
    ///         reset), and starts a 24h cooldown. An alternative to claim()'s all-or-nothing reset.
    function claimPartial(uint256 tokenId) external whenNotPaused nonReentrant {
        if (msg.sender != IFundNFT(fundNFT).ownerOf(tokenId)) revert NotFundOwner();
        if (block.timestamp < partialRedemptionCooldownEnd[tokenId]) revert CooldownActive();

        _settle(tokenId);
        uint256 total = rewards[tokenId];
        uint256 payout = (total * PARTIAL_PAYOUT_BPS) / BPS_DENOMINATOR;
        uint256 forfeited = total - payout;
        rewards[tokenId] = 0;

        if (forfeited > 0) {
            _depositInternal(forfeited);
        }

        IGameEngine(gameEngine).applyScoreHaircut(tokenId, PARTIAL_SCORE_HAIRCUT_BPS);
        _reweight(tokenId);

        partialRedemptionCooldownEnd[tokenId] = uint64(block.timestamp) + uint64(PARTIAL_REDEMPTION_COOLDOWN);

        withdrawable[msg.sender] += payout;
        emit Claimed(tokenId, msg.sender, payout, true);
    }

    /// @inheritdoc IRewardsDistributor
    function settleOnLiquidation(uint256 tokenId, address fundOwner, address bountyRecipient, uint256 bountyAmount)
        external
        onlyGameEngine
        returns (uint256 totalAccrued)
    {
        _settle(tokenId);
        totalAccrued = rewards[tokenId];
        rewards[tokenId] = 0;
        totalWeightedScore -= weightedScore[tokenId];
        weightedScore[tokenId] = 0;

        withdrawable[fundOwner] += totalAccrued;

        bool bountyPaid;
        if (bountyAmount > 0 && address(this).balance >= bountyAmount) {
            (bountyPaid,) = payable(bountyRecipient).call{value: bountyAmount}("");
            // Best-effort: liquidation must never be blockable by a bounty recipient that can't
            // receive ETH. On failure the bounty ETH simply remains in the pool.
        }

        emit LiquidationSettled(tokenId, fundOwner, totalAccrued, bountyRecipient, bountyAmount, bountyPaid);
    }

    /// @inheritdoc IRewardsDistributor
    function seizeRewards(uint256 fromTokenId, uint256 toTokenId, uint256 bps)
        external
        onlyGameEngine
        returns (uint256 amount)
    {
        _settle(fromTokenId);
        _settle(toTokenId);
        amount = (rewards[fromTokenId] * bps) / BPS_DENOMINATOR;
        rewards[fromTokenId] -= amount;
        rewards[toTokenId] += amount;
        emit RewardsSeized(fromTokenId, toTokenId, amount);
    }

    /// @inheritdoc IRewardsDistributor
    function withdraw() external nonReentrant {
        uint256 amount = withdrawable[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        withdrawable[msg.sender] = 0;
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit Withdrawn(msg.sender, amount);
    }
}
