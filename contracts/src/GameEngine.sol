// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFundNFT} from "./interfaces/IFundNFT.sol";
import {IGameToken} from "./interfaces/IGameToken.sol";
import {IGameEngine} from "./interfaces/IGameEngine.sol";
import {IRewardsDistributor} from "./interfaces/IRewardsDistributor.sol";
import {GameMath} from "./libraries/GameMath.sol";

/// @title GameEngine
/// @notice Core MARGIN game loop and sole source of truth for fund state (see MARGIN_SPEC.md
///         section 5). FundNFT is a thin ERC-721 shell that reads state from here.
/// @dev State-transition philosophy (MARGIN_SPEC.md: "all state transitions enforced by
///      timestamps, callable permissionlessly"): a fund's Active/MarginCalled status is NEVER
///      stored — it's derived on read from `lastRebalance` vs `block.timestamp` in `getStatus()`.
///      Only the terminal Liquidated state is a stored flag, since burning the NFT is an
///      irreversible action that must happen in an explicit transaction. This means there is no
///      "flip to margin-called" keeper call to forget — the deadline enforces itself.
contract GameEngine is Ownable, Pausable, ReentrancyGuard, IGameEngine {
    using Math for uint256;
    using SafeERC20 for IGameToken;

    struct Fund {
        uint32 traders;
        uint32 desks;
        uint64 lastRebalance;
        uint64 lastClaim;
        uint128 score; // Wad. Pure trader-growth score — AUM staking never touches this (see DECISIONS.md).
        uint128 yieldBalance;
        uint128 capitalBalance;
        bytes32 randomCommitment; // commit-reveal: keccak256(secret) for the NEXT reveal-consuming action
        bool liquidated;
    }

    // ---- Timing (MARGIN_SPEC.md section 2) ----
    uint256 public constant EPOCH_LENGTH = 72 hours;
    uint256 public constant MARGIN_CALL_GRACE = 72 hours;

    // ---- Costs & rates (DECISIONS.md "Phase 1 economic constants" — all tunable pre-launch) ----
    uint256 public constant REBALANCE_YIELD_COST = 3;
    uint256 public constant REBALANCE_TOKEN_BURN = 5 ether;
    uint256 public constant PAYROLL_PER_TRADER = 1;
    uint256 public constant DESK_SIZE = 5;
    uint256 public constant MINT_FEE = 0.001 ether;
    uint256 public constant LIQUIDATION_BOUNTY = 0.0005 ether;
    uint256 public constant TAKEOVER_STAKE = 20 ether;
    uint256 public constant TAKEOVER_STEAL_BPS = 1000; // 10% of defender's accrued unclaimed ETH
    uint256 public constant TAKEOVER_TRADER_LOSS_BPS = 500; // 5% chance defender loses 1 trader
    uint256 public constant TAKEOVER_IMMUNITY = 24 hours;
    uint256 public constant RECAP_PENALTY_TO_POOL_BPS = 7000;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant EMISSION_PER_TRADER = 0.5 ether; // $MGN, capped by this contract's own balance

    // Resource accrual: base rate (bootstraps a 0-trader fund) + per-trader rate, per EPOCH_LENGTH.
    // New (not in MARGIN_SPEC.md, which only specifies "passive accrual + active claim") — see
    // DECISIONS.md addendum. Chosen so CAPITAL leaves ~2/trader/epoch surplus after payroll
    // (enabling the min(surplusCapital/2, openDeskSeats) growth formula to produce net-positive
    // trader growth at steady state) and YIELD comfortably covers rebalance cost + desk savings.
    uint256 public constant BASE_YIELD_PER_EPOCH = 10;
    uint256 public constant YIELD_PER_TRADER_PER_EPOCH = 4;
    uint256 public constant BASE_CAPITAL_PER_EPOCH = 5;
    uint256 public constant CAPITAL_PER_TRADER_PER_EPOCH = 3;

    IFundNFT public immutable fundNFT;
    IGameToken public immutable gameToken;
    IRewardsDistributor public rewardsDistributor;
    address public treasury;

    mapping(uint256 => Fund) public funds;
    mapping(uint256 => uint64) public lastAttackedAt;
    uint256 public totalScore;

    event FundMinted(uint256 indexed tokenId, address indexed owner);
    event Rebalanced(uint256 indexed tokenId, uint256 newTraders, uint256 scoreAdded, uint256 tokenEmission);
    event DeskBuilt(uint256 indexed tokenId, uint256 deskNumber, uint256 cost);
    event ResourcesClaimed(uint256 indexed tokenId, uint256 yieldGained, uint256 capitalGained);
    event Recapitalized(uint256 indexed tokenId, uint256 cost);
    event FundLiquidated(uint256 indexed tokenId, address indexed caller, uint256 payout, uint256 bounty);
    event TakeoverExecuted(
        uint256 indexed attackerTokenId, uint256 indexed defenderTokenId, uint256 stolen, bool traderLost
    );

    error NotFundOwner();
    error AlreadyLiquidated();
    error NotActive();
    error NotMarginCalled();
    error TooLateForRecap();
    error NotYetLiquidationEligible();
    error BadReveal();
    error InsufficientYield();
    error InsufficientMsgValue();
    error AlreadySet();
    error ZeroAddress();
    error DefenderImmune();
    error SelfTakeover();
    error TransferFailed();
    error NotRewardsDistributor();

    modifier onlyFundOwner(uint256 tokenId) {
        if (msg.sender != fundNFT.ownerOf(tokenId)) revert NotFundOwner();
        _;
    }

    modifier onlyRewardsDistributor() {
        if (msg.sender != address(rewardsDistributor)) revert NotRewardsDistributor();
        _;
    }

    constructor(address initialOwner, IFundNFT _fundNFT, IGameToken _gameToken) Ownable(initialOwner) {
        fundNFT = _fundNFT;
        gameToken = _gameToken;
    }

    // ---- One-time wiring (mirrors FundNFT.setGameEngine — locked after first call, see its NatSpec) ----

    function setRewardsDistributor(IRewardsDistributor _rewardsDistributor) external onlyOwner {
        if (address(rewardsDistributor) != address(0)) revert AlreadySet();
        rewardsDistributor = _rewardsDistributor;
    }

    function setTreasury(address _treasury) external onlyOwner {
        if (treasury != address(0)) revert AlreadySet();
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
    }

    /// @notice Privileged: owner only. Emergency halt on all player actions incl. liquidate().
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ---- Views ----

    /// @notice Derives a fund's status from timestamps. See contract-level NatSpec.
    function getStatus(uint256 tokenId) public view returns (FundStatus) {
        Fund storage f = funds[tokenId];
        if (f.liquidated) return FundStatus.Liquidated;
        if (block.timestamp <= f.lastRebalance + EPOCH_LENGTH) return FundStatus.Active;
        return FundStatus.MarginCalled;
    }

    function isLiquidationEligible(uint256 tokenId) public view returns (bool) {
        Fund storage f = funds[tokenId];
        return !f.liquidated && block.timestamp > f.lastRebalance + EPOCH_LENGTH + MARGIN_CALL_GRACE;
    }

    /// @notice Frontend convenience: the ETH cost `recapitalize(tokenId)` would currently charge,
    ///         so the UI can show it before the user sends a value transaction.
    function recapCost(uint256 tokenId) external view returns (uint256) {
        return GameMath.computeRecapCost(funds[tokenId].traders);
    }

    /// @notice Frontend convenience: the YIELD cost `buildDesk(tokenId)` would currently charge.
    function nextDeskCost(uint256 tokenId) external view returns (uint256) {
        return GameMath.computeDeskCost(funds[tokenId].desks);
    }

    /// @inheritdoc IGameEngine
    function getFund(uint256 tokenId) external view returns (FundView memory) {
        Fund storage f = funds[tokenId];
        return FundView({
            traders: f.traders,
            desks: f.desks,
            lastRebalance: f.lastRebalance,
            marginCalledAt: f.lastRebalance + uint64(EPOCH_LENGTH),
            score: f.score,
            yieldBalance: f.yieldBalance,
            capitalBalance: f.capitalBalance,
            pendingTokenRewards: 0,
            status: getStatus(tokenId)
        });
    }

    /// @notice Pending YIELD/CAPITAL since last claim, for frontend display before calling claimResources().
    function pendingResources(uint256 tokenId) external view returns (uint256 pendingYield, uint256 pendingCapital) {
        Fund storage f = funds[tokenId];
        uint256 elapsed = block.timestamp - f.lastClaim;
        pendingYield = ((BASE_YIELD_PER_EPOCH + uint256(f.traders) * YIELD_PER_TRADER_PER_EPOCH) * elapsed) / EPOCH_LENGTH;
        pendingCapital =
            ((BASE_CAPITAL_PER_EPOCH + uint256(f.traders) * CAPITAL_PER_TRADER_PER_EPOCH) * elapsed) / EPOCH_LENGTH;
    }

    // ---- Actions ----

    /// @notice Mints a new fund. `initialCommitment` seeds the commit-reveal cycle consumed by
    ///         this fund's first rebalance() or takeover() call — see contract-level NatSpec on
    ///         the randomness approach and its documented limitations.
    function mintFund(bytes32 initialCommitment) external payable whenNotPaused nonReentrant returns (uint256 tokenId) {
        if (msg.value < MINT_FEE) revert InsufficientMsgValue();

        tokenId = fundNFT.mint(msg.sender);
        funds[tokenId] = Fund({
            traders: 0,
            desks: 0,
            lastRebalance: uint64(block.timestamp),
            lastClaim: uint64(block.timestamp),
            score: 0,
            yieldBalance: 0,
            capitalBalance: 0,
            randomCommitment: initialCommitment,
            liquidated: false
        });

        rewardsDistributor.depositRewards{value: msg.value}();
        rewardsDistributor.syncFund(tokenId);

        emit FundMinted(tokenId, msg.sender);
    }

    /// @notice Claims accrued passive YIELD/CAPITAL. Permissionless (keeper-friendly, harmless —
    ///         it can only ever credit the fund, never the caller).
    function claimResources(uint256 tokenId) external whenNotPaused {
        _accrueResources(tokenId);
    }

    function _accrueResources(uint256 tokenId) internal returns (uint256 yieldGained, uint256 capitalGained) {
        Fund storage f = funds[tokenId];
        uint256 elapsed = block.timestamp - f.lastClaim;
        if (elapsed == 0) return (0, 0);

        yieldGained = ((BASE_YIELD_PER_EPOCH + uint256(f.traders) * YIELD_PER_TRADER_PER_EPOCH) * elapsed) / EPOCH_LENGTH;
        capitalGained =
            ((BASE_CAPITAL_PER_EPOCH + uint256(f.traders) * CAPITAL_PER_TRADER_PER_EPOCH) * elapsed) / EPOCH_LENGTH;

        f.yieldBalance += uint128(yieldGained);
        f.capitalBalance += uint128(capitalGained);
        f.lastClaim = uint64(block.timestamp);

        emit ResourcesClaimed(tokenId, yieldGained, capitalGained);
    }

    /// @notice The core loop action. Must be called before the 72h deadline (`getStatus == Active`)
    ///         — once missed, use `recapitalize()` instead. Pays payroll, grows traders, adds
    ///         score, pays $MGN emissions, and re-arms the commit-reveal cycle.
    /// @param reveal Preimage such that keccak256(reveal) == the fund's stored commitment. Not
    ///        bound to tokenId: at mintFund() time the tokenId doesn't exist yet for the caller to
    ///        bind against, so verification is scoped only by each fund's own commitment storage slot.
    /// @param nextCommitment Commitment for the NEXT reveal-consuming call (rebalance or takeover).
    function rebalance(uint256 tokenId, bytes32 reveal, bytes32 nextCommitment)
        external
        whenNotPaused
        nonReentrant
        onlyFundOwner(tokenId)
    {
        Fund storage f = funds[tokenId];
        if (f.liquidated) revert AlreadyLiquidated();
        if (getStatus(tokenId) != FundStatus.Active) revert NotActive();
        if (keccak256(abi.encodePacked(reveal)) != f.randomCommitment) revert BadReveal();

        _accrueResources(tokenId);

        if (f.yieldBalance < REBALANCE_YIELD_COST) revert InsufficientYield();
        f.yieldBalance -= uint128(REBALANCE_YIELD_COST);
        gameToken.burnFrom(msg.sender, REBALANCE_TOKEN_BURN);

        // Payroll: 1 CAPITAL per trader. Shortfall -> traders quit 1:1 with the unpaid amount,
        // and score drops by their contribution (MARGIN_SPEC.md section 2).
        uint256 payrollCost = uint256(f.traders) * PAYROLL_PER_TRADER;
        if (f.capitalBalance < payrollCost) {
            uint256 deficit = payrollCost - f.capitalBalance;
            uint256 tradersLost = Math.min(f.traders, deficit);
            f.capitalBalance = 0;
            f.traders -= uint32(tradersLost);
            uint256 scoreLoss = Math.min(uint256(f.score), tradersLost * GameMath.SCORE_PER_TRADER_WAD);
            f.score -= uint128(scoreLoss);
            totalScore -= scoreLoss;
        } else {
            f.capitalBalance -= uint128(payrollCost);
        }

        // Growth: newTraders = min(surplusCapital / 2, openDeskSeats).
        uint256 openDeskSeats = uint256(f.desks) * DESK_SIZE > f.traders ? uint256(f.desks) * DESK_SIZE - f.traders : 0;
        uint256 newTraders = GameMath.computeNewTraders(f.capitalBalance, openDeskSeats);
        f.traders += uint32(newTraders);
        f.capitalBalance -= uint128(newTraders * 2);

        uint256 smallRandomWad = GameMath.scaleSmallRandom(uint256(keccak256(abi.encodePacked(reveal, tokenId))));
        uint256 scoreAdded = GameMath.computeScoreAdded(newTraders, smallRandomWad);
        f.score += uint128(scoreAdded);
        totalScore += scoreAdded;

        uint256 emissionDue = EMISSION_PER_TRADER * f.traders;
        uint256 available = gameToken.balanceOf(address(this));
        uint256 emission = Math.min(emissionDue, available);
        if (emission > 0) {
            gameToken.safeTransfer(fundNFT.ownerOf(tokenId), emission);
        }

        f.lastRebalance = uint64(block.timestamp);
        f.randomCommitment = nextCommitment;

        rewardsDistributor.syncFund(tokenId);

        emit Rebalanced(tokenId, newTraders, scoreAdded, emission);
    }

    /// @notice Builds the next desk (adds DESK_SIZE trader capacity). Cost escalates per GameMath.
    function buildDesk(uint256 tokenId) external whenNotPaused onlyFundOwner(tokenId) {
        Fund storage f = funds[tokenId];
        if (f.liquidated) revert AlreadyLiquidated();
        _accrueResources(tokenId);

        uint256 cost = GameMath.computeDeskCost(f.desks);
        if (f.yieldBalance < cost) revert InsufficientYield();
        f.yieldBalance -= uint128(cost);
        f.desks += 1;

        emit DeskBuilt(tokenId, f.desks, cost);
    }

    /// @notice Clears a margin call by paying an ETH cost that scales with trader count. A cut of
    ///         the payment is redistributed to surviving funds' reward pool (MARGIN_SPEC.md
    ///         section 3, Track 2 item 3); the rest funds the Treasury.
    function recapitalize(uint256 tokenId) external payable whenNotPaused nonReentrant onlyFundOwner(tokenId) {
        Fund storage f = funds[tokenId];
        if (f.liquidated) revert AlreadyLiquidated();
        if (getStatus(tokenId) != FundStatus.MarginCalled) revert NotMarginCalled();
        if (isLiquidationEligible(tokenId)) revert TooLateForRecap();

        uint256 cost = GameMath.computeRecapCost(f.traders);
        if (msg.value < cost) revert InsufficientMsgValue();

        uint256 toPool = (cost * RECAP_PENALTY_TO_POOL_BPS) / BPS_DENOMINATOR;
        uint256 toTreasury = cost - toPool;
        rewardsDistributor.depositRewards{value: toPool}();
        (bool ok,) = payable(treasury).call{value: toTreasury}("");
        if (!ok) revert TransferFailed();

        f.lastRebalance = uint64(block.timestamp);

        if (msg.value > cost) {
            (bool refundOk,) = payable(msg.sender).call{value: msg.value - cost}("");
            if (!refundOk) revert TransferFailed();
        }

        rewardsDistributor.syncFund(tokenId);

        emit Recapitalized(tokenId, cost);
    }

    /// @notice Liquidates a fund whose margin-call grace period has expired. Permissionless —
    ///         anyone may call this and earn LIQUIDATION_BOUNTY. Accrued ETH rewards are settled
    ///         to the fund owner's pull-payment balance in RewardsDistributor (never pushed
    ///         directly, so a hostile/non-receiving owner can never block liquidation).
    function liquidate(uint256 tokenId) external whenNotPaused nonReentrant {
        Fund storage f = funds[tokenId];
        if (f.liquidated) revert AlreadyLiquidated();
        if (!isLiquidationEligible(tokenId)) revert NotYetLiquidationEligible();

        f.liquidated = true;
        totalScore -= f.score;

        address owner_ = fundNFT.ownerOf(tokenId);
        uint256 payout = rewardsDistributor.settleOnLiquidation(tokenId, owner_, msg.sender, LIQUIDATION_BOUNTY);

        fundNFT.burn(tokenId);

        emit FundLiquidated(tokenId, msg.sender, payout, LIQUIDATION_BOUNTY);
    }

    /// @notice Attacks another fund, stealing a % of its unclaimed accrued ETH with a small chance
    ///         of costing the defender a trader. Consumes the attacker's current commit-reveal
    ///         slot (same mechanism as rebalance — see contract-level NatSpec) and re-arms it.
    function takeover(uint256 attackerTokenId, uint256 defenderTokenId, bytes32 reveal, bytes32 nextCommitment)
        external
        whenNotPaused
        nonReentrant
        onlyFundOwner(attackerTokenId)
    {
        if (attackerTokenId == defenderTokenId) revert SelfTakeover();
        Fund storage attacker = funds[attackerTokenId];
        Fund storage defender = funds[defenderTokenId];
        if (attacker.liquidated || defender.liquidated) revert AlreadyLiquidated();
        if (keccak256(abi.encodePacked(reveal)) != attacker.randomCommitment) revert BadReveal();
        if (block.timestamp < lastAttackedAt[defenderTokenId] + TAKEOVER_IMMUNITY) revert DefenderImmune();

        gameToken.burnFrom(msg.sender, TAKEOVER_STAKE);

        uint256 stolen = rewardsDistributor.seizeRewards(defenderTokenId, attackerTokenId, TAKEOVER_STEAL_BPS);

        uint256 roll = uint256(keccak256(abi.encodePacked(reveal, attackerTokenId, defenderTokenId))) % BPS_DENOMINATOR;
        bool traderLost = roll < TAKEOVER_TRADER_LOSS_BPS && defender.traders > 0;
        if (traderLost) {
            defender.traders -= 1;
            uint256 scoreLoss = Math.min(uint256(defender.score), GameMath.SCORE_PER_TRADER_WAD);
            defender.score -= uint128(scoreLoss);
            totalScore -= scoreLoss;
        }

        attacker.randomCommitment = nextCommitment;
        lastAttackedAt[defenderTokenId] = uint64(block.timestamp);

        rewardsDistributor.syncFund(attackerTokenId);
        rewardsDistributor.syncFund(defenderTokenId);

        emit TakeoverExecuted(attackerTokenId, defenderTokenId, stolen, traderLost);
    }

    /// @notice Resets a fund's stats to zero on full redemption. The NFT survives — only the
    ///         stats reset, matching Stoke Fire's "village resets to 0". Restricted to RewardsDistributor.
    function resetFundForRedemption(uint256 tokenId) external onlyRewardsDistributor {
        Fund storage f = funds[tokenId];
        totalScore -= f.score;
        f.traders = 0;
        f.desks = 0;
        f.score = 0;
        f.yieldBalance = 0;
        f.capitalBalance = 0;
        f.lastRebalance = uint64(block.timestamp);
        f.lastClaim = uint64(block.timestamp);
    }

    /// @notice Reduces a fund's score by `bps` (out of 10,000) on partial redemption. Restricted to RewardsDistributor.
    function applyScoreHaircut(uint256 tokenId, uint256 bps) external onlyRewardsDistributor {
        Fund storage f = funds[tokenId];
        uint256 loss = (uint256(f.score) * bps) / BPS_DENOMINATOR;
        f.score -= uint128(loss);
        totalScore -= loss;
    }
}
