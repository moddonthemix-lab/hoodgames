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
/// @dev State-transition philosophy: a fund's Active/MarginCalled status is NEVER stored — it's
///      derived on read from `lastRebalance` vs `block.timestamp`. Only the terminal Liquidated
///      state is a stored flag. The deadline enforces itself; there is no keeper "flip" to forget.
///
///      Resource model (Stoke-Fire-aligned, see DECISIONS.md):
///        - YIELD  (≈ Stoke Fire's Wood): spent to rebalance. Actively gathered via gatherYield().
///        - CAPITAL (≈ Stoke Fire's Food): spent on worker payroll at rebalance. Via gatherCapital().
///      Both gathers are cooldown-gated (GATHER_COOLDOWN) and give a fixed amount per call, boosted
///      by Brokers — there is no passive drip, you must actively gather (like Chop Wood / Gather Food).
///
///      Rebalance is the once-per-cycle heartbeat: it costs YIELD + CAPITAL, adds score (Analyst-
///      driven), and grants +1 Computer (capacity). A MIN_REBALANCE_INTERVAL floor stops it being
///      spammed to farm computers/score. Computers are ONLY gained via rebalance (no separate build).
///
///      Workers are three hireable Roles: Hacker (takeover offense/defense), Analyst (score/P&L),
///      Broker (boosts gather amounts). Hired directly for $MGN; must fit open Computer seats.
contract GameEngine is Ownable, Pausable, ReentrancyGuard, IGameEngine {
    using Math for uint256;
    using SafeERC20 for IGameToken;

    struct Fund {
        uint32 hackers;
        uint32 analysts;
        uint32 brokers;
        uint32 computers;
        uint64 lastRebalance;
        uint64 yieldCooldownEnd;
        uint64 capitalCooldownEnd;
        uint128 score; // Wad. Accumulated P&L — AUM staking never touches this.
        uint128 yieldBalance;
        uint128 capitalBalance;
        bytes32 randomCommitment; // commit-reveal: keccak256(secret) for the NEXT reveal-consuming action
        bool liquidated;
    }

    // ---- Timing ----
    uint256 public constant EPOCH_LENGTH = 72 hours;
    uint256 public constant MARGIN_CALL_GRACE = 72 hours;
    /// @notice Anti-spam floor between rebalances (each rebalance grants a Computer + score, so
    ///         without this a well-resourced fund could farm both). Invisible in normal ~3-day play.
    uint256 public constant MIN_REBALANCE_INTERVAL = 12 hours;

    // ---- Gathering (active, cooldown-gated — the "Chop Wood / Gather Food" of MARGIN) ----
    uint256 public constant GATHER_COOLDOWN = 1 hours;
    uint256 public constant YIELD_PER_GATHER = 10;
    uint256 public constant CAPITAL_PER_GATHER = 10;
    uint256 public constant BROKER_GATHER_BONUS = 2; // per broker, added to each gather of both resources

    // ---- Rebalance costs / rewards ----
    uint256 public constant REBALANCE_YIELD_COST = 3;
    uint256 public constant REBALANCE_BASE_CAPITAL = 3;
    uint256 public constant PAYROLL_PER_WORKER = 1; // CAPITAL per worker, on top of the base
    uint256 public constant COMPUTERS_PER_REBALANCE = 1;
    uint256 public constant WORKERS_PER_COMPUTER = 5;
    uint256 public constant ANALYST_SCORE_WAD = 1.2e18;
    uint256 public constant AUX_SCORE_WAD = 0.3e18; // hackers/brokers still score a little
    uint256 public constant EMISSION_PER_WORKER = 0.5 ether; // $MGN farmed per worker per rebalance, capped by balance

    // ---- Fees / misc ----
    uint256 public constant MINT_FEE = 0.001 ether;
    uint256 public constant LIQUIDATION_BOUNTY = 0.0005 ether;
    uint256 public constant RECAP_PENALTY_TO_POOL_BPS = 7000;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ---- Hiring costs ($MGN, burned) — Hacker cheap, Analyst mid, Broker premium ----
    uint256 public constant HIRE_COST_HACKER = 10 ether;
    uint256 public constant HIRE_COST_ANALYST = 15 ether;
    uint256 public constant HIRE_COST_BROKER = 20 ether;

    // ---- Takeover ----
    uint256 public constant TAKEOVER_STAKE = 20 ether;
    uint256 public constant TAKEOVER_IMMUNITY = 24 hours;
    /// @notice A fund must be established before it can attack: at least this many computers AND
    ///         at least one worker hired.
    uint256 public constant TAKEOVER_MIN_COMPUTERS = 4;
    uint256 public constant TAKEOVER_BASE_STEAL_BPS = 1000; // 10% floor
    uint256 public constant TAKEOVER_HACKER_STEAL_BPS = 100; // +1% per attacker hacker
    uint256 public constant TAKEOVER_MAX_STEAL_BPS = 3000; // hard cap 30%
    uint256 public constant TAKEOVER_HACKER_DEFENSE_BPS = 100; // defender hacker cuts steal 1% each
    uint256 public constant TAKEOVER_WORKER_LOSS_BPS = 500; // 5% chance defender loses a worker

    IFundNFT public immutable fundNFT;
    IGameToken public immutable gameToken;
    IRewardsDistributor public rewardsDistributor;
    address public treasury;

    mapping(uint256 => Fund) public funds;
    mapping(uint256 => uint64) public lastAttackedAt;
    uint256 public totalScore;

    event FundMinted(uint256 indexed tokenId, address indexed owner);
    event RewardsDistributorSet(address indexed rewardsDistributor);
    event TreasurySet(address indexed treasury);
    event Rebalanced(
        uint256 indexed tokenId, uint256 scoreAdded, uint256 computersGained, uint256 workersLaidOff, uint256 tokenEmission
    );
    event Gathered(uint256 indexed tokenId, bool isYield, uint256 amount);
    event Hired(uint256 indexed tokenId, Role role, uint256 count, uint256 cost);
    event Recapitalized(uint256 indexed tokenId, uint256 cost);
    event FundLiquidated(uint256 indexed tokenId, address indexed caller, uint256 payout, uint256 bounty);
    event TakeoverExecuted(
        uint256 indexed attackerTokenId, uint256 indexed defenderTokenId, uint256 stolen, bool workerLost
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
    error NoOpenSeats();
    error ZeroCount();
    error GatherOnCooldown();
    error RebalanceTooSoon();
    error TakeoverLockedNeedComputers();
    error TakeoverLockedNeedWorker();

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

    // ---- One-time wiring (locked after first call) ----

    function setRewardsDistributor(IRewardsDistributor _rewardsDistributor) external onlyOwner {
        if (address(rewardsDistributor) != address(0)) revert AlreadySet();
        if (address(_rewardsDistributor) == address(0)) revert ZeroAddress();
        rewardsDistributor = _rewardsDistributor;
        emit RewardsDistributorSet(address(_rewardsDistributor));
    }

    function setTreasury(address _treasury) external onlyOwner {
        if (treasury != address(0)) revert AlreadySet();
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ---- Views ----

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

    function totalWorkers(uint256 tokenId) public view returns (uint256) {
        Fund storage f = funds[tokenId];
        return uint256(f.hackers) + f.analysts + f.brokers;
    }

    function getFund(uint256 tokenId) external view returns (FundView memory) {
        Fund storage f = funds[tokenId];
        return FundView({
            hackers: f.hackers,
            analysts: f.analysts,
            brokers: f.brokers,
            computers: f.computers,
            lastRebalance: f.lastRebalance,
            marginCalledAt: f.lastRebalance + uint64(EPOCH_LENGTH),
            yieldCooldownEnd: f.yieldCooldownEnd,
            capitalCooldownEnd: f.capitalCooldownEnd,
            score: f.score,
            yieldBalance: f.yieldBalance,
            capitalBalance: f.capitalBalance,
            status: getStatus(tokenId)
        });
    }

    /// @notice YIELD a gatherYield() call would grant right now (base + broker bonus).
    function gatherYieldAmount(uint256 tokenId) public view returns (uint256) {
        return YIELD_PER_GATHER + uint256(funds[tokenId].brokers) * BROKER_GATHER_BONUS;
    }

    /// @notice CAPITAL a gatherCapital() call would grant right now.
    function gatherCapitalAmount(uint256 tokenId) public view returns (uint256) {
        return CAPITAL_PER_GATHER + uint256(funds[tokenId].brokers) * BROKER_GATHER_BONUS;
    }

    /// @notice CAPITAL the next rebalance's payroll would cost (base + per worker).
    function rebalanceCapitalCost(uint256 tokenId) public view returns (uint256) {
        return REBALANCE_BASE_CAPITAL + totalWorkers(tokenId) * PAYROLL_PER_WORKER;
    }

    function hireCost(Role role, uint256 count) public pure returns (uint256) {
        return count * _roleUnitCost(role);
    }

    function recapCost(uint256 tokenId) external view returns (uint256) {
        return GameMath.computeRecapCost(totalWorkers(tokenId));
    }

    /// @notice Whether `tokenId` currently meets the takeover-attacker requirements.
    function canAttack(uint256 tokenId) public view returns (bool) {
        return funds[tokenId].computers >= TAKEOVER_MIN_COMPUTERS && totalWorkers(tokenId) > 0;
    }

    // ---- Internal helpers ----

    function _roleUnitCost(Role role) internal pure returns (uint256) {
        if (role == Role.Hacker) return HIRE_COST_HACKER;
        if (role == Role.Analyst) return HIRE_COST_ANALYST;
        return HIRE_COST_BROKER;
    }

    /// @dev Lays off `count` workers, Hacker-first then Analyst then Broker. O(1).
    function _layOff(Fund storage f, uint256 count) internal {
        uint256 fromHackers = Math.min(count, f.hackers);
        f.hackers -= uint32(fromHackers);
        count -= fromHackers;
        if (count == 0) return;
        uint256 fromAnalysts = Math.min(count, f.analysts);
        f.analysts -= uint32(fromAnalysts);
        count -= fromAnalysts;
        if (count == 0) return;
        f.brokers -= uint32(Math.min(count, f.brokers));
    }

    // ---- Actions ----

    function mintFund(bytes32 initialCommitment) external payable whenNotPaused nonReentrant returns (uint256 tokenId) {
        if (msg.value < MINT_FEE) revert InsufficientMsgValue();

        tokenId = fundNFT.mint(msg.sender);
        Fund storage f = funds[tokenId];
        f.lastRebalance = uint64(block.timestamp);
        f.randomCommitment = initialCommitment;

        rewardsDistributor.depositRewards{value: msg.value}();
        rewardsDistributor.syncFund(tokenId);

        emit FundMinted(tokenId, msg.sender);
    }

    /// @notice Gathers YIELD. Cooldown-gated. Permissionless-safe (owner-gated to avoid griefing
    ///         another fund's cooldown, though it would only help them).
    function gatherYield(uint256 tokenId) external whenNotPaused onlyFundOwner(tokenId) {
        Fund storage f = funds[tokenId];
        if (f.liquidated) revert AlreadyLiquidated();
        if (block.timestamp < f.yieldCooldownEnd) revert GatherOnCooldown();
        uint256 amount = gatherYieldAmount(tokenId);
        f.yieldBalance += uint128(amount);
        f.yieldCooldownEnd = uint64(block.timestamp) + uint64(GATHER_COOLDOWN);
        emit Gathered(tokenId, true, amount);
    }

    /// @notice Gathers CAPITAL. Cooldown-gated.
    function gatherCapital(uint256 tokenId) external whenNotPaused onlyFundOwner(tokenId) {
        Fund storage f = funds[tokenId];
        if (f.liquidated) revert AlreadyLiquidated();
        if (block.timestamp < f.capitalCooldownEnd) revert GatherOnCooldown();
        uint256 amount = gatherCapitalAmount(tokenId);
        f.capitalBalance += uint128(amount);
        f.capitalCooldownEnd = uint64(block.timestamp) + uint64(GATHER_COOLDOWN);
        emit Gathered(tokenId, false, amount);
    }

    /// @notice Hires `count` workers of `role`, burning $MGN. Must have open Computer seats.
    function hire(uint256 tokenId, Role role, uint256 count)
        external
        whenNotPaused
        nonReentrant
        onlyFundOwner(tokenId)
    {
        if (count == 0) revert ZeroCount();
        Fund storage f = funds[tokenId];
        if (f.liquidated) revert AlreadyLiquidated();

        uint256 seats = uint256(f.computers) * WORKERS_PER_COMPUTER;
        if (totalWorkers(tokenId) + count > seats) revert NoOpenSeats();

        uint256 cost = count * _roleUnitCost(role);
        gameToken.burnFrom(msg.sender, cost);

        if (role == Role.Hacker) f.hackers += uint32(count);
        else if (role == Role.Analyst) f.analysts += uint32(count);
        else f.brokers += uint32(count);

        emit Hired(tokenId, role, count, cost);
    }

    /// @notice The once-per-cycle heartbeat. Costs YIELD + CAPITAL (capital = base + per-worker
    ///         payroll; shortfall lays off workers Hacker-first), adds score (Analyst-driven),
    ///         grants +COMPUTERS_PER_REBALANCE Computer(s), pays $MGN emissions, re-arms commit-reveal.
    ///         Must be Active and at least MIN_REBALANCE_INTERVAL since the last rebalance.
    function rebalance(uint256 tokenId, bytes32 reveal, bytes32 nextCommitment)
        external
        whenNotPaused
        nonReentrant
        onlyFundOwner(tokenId)
    {
        Fund storage f = funds[tokenId];
        if (f.liquidated) revert AlreadyLiquidated();
        if (getStatus(tokenId) != FundStatus.Active) revert NotActive();
        if (block.timestamp < uint256(f.lastRebalance) + MIN_REBALANCE_INTERVAL) revert RebalanceTooSoon();
        if (keccak256(abi.encodePacked(reveal)) != f.randomCommitment) revert BadReveal();

        // YIELD cost (hard requirement — can't rebalance without it).
        if (f.yieldBalance < REBALANCE_YIELD_COST) revert InsufficientYield();
        f.yieldBalance -= uint128(REBALANCE_YIELD_COST);

        // CAPITAL payroll: base + 1 per worker. Shortfall -> lay off workers 1:1 (Hacker-first).
        uint256 workers = totalWorkers(tokenId);
        uint256 payrollCost = REBALANCE_BASE_CAPITAL + workers * PAYROLL_PER_WORKER;
        uint256 laidOff;
        if (f.capitalBalance < payrollCost) {
            uint256 deficit = payrollCost - f.capitalBalance;
            laidOff = Math.min(workers, deficit);
            f.capitalBalance = 0;
            _layOff(f, laidOff);
        } else {
            f.capitalBalance -= uint128(payrollCost);
        }

        // Grant a Computer (capacity growth) — this is the only source of computers.
        f.computers += uint32(COMPUTERS_PER_REBALANCE);

        // Score = P&L from the surviving team (analysts are the engine).
        uint256 survivors = totalWorkers(tokenId);
        uint256 survivingAnalysts = f.analysts;
        uint256 auxWorkers = survivors - survivingAnalysts;
        uint256 smallRandomWad = GameMath.scaleSmallRandom(uint256(keccak256(abi.encodePacked(reveal, tokenId))));
        uint256 scoreAdded = survivingAnalysts * ANALYST_SCORE_WAD + auxWorkers * AUX_SCORE_WAD + smallRandomWad;
        f.score += uint128(scoreAdded);
        totalScore += scoreAdded;

        uint256 emission = Math.min(EMISSION_PER_WORKER * survivors, gameToken.balanceOf(address(this)));
        if (emission > 0) {
            gameToken.safeTransfer(fundNFT.ownerOf(tokenId), emission);
        }

        f.lastRebalance = uint64(block.timestamp);
        f.randomCommitment = nextCommitment;

        rewardsDistributor.syncFund(tokenId);

        emit Rebalanced(tokenId, scoreAdded, COMPUTERS_PER_REBALANCE, laidOff, emission);
    }

    function recapitalize(uint256 tokenId) external payable whenNotPaused nonReentrant onlyFundOwner(tokenId) {
        Fund storage f = funds[tokenId];
        if (f.liquidated) revert AlreadyLiquidated();
        if (getStatus(tokenId) != FundStatus.MarginCalled) revert NotMarginCalled();
        if (isLiquidationEligible(tokenId)) revert TooLateForRecap();

        uint256 cost = GameMath.computeRecapCost(totalWorkers(tokenId));
        if (msg.value < cost) revert InsufficientMsgValue();

        f.lastRebalance = uint64(block.timestamp);

        uint256 toPool = (cost * RECAP_PENALTY_TO_POOL_BPS) / BPS_DENOMINATOR;
        uint256 toTreasury = cost - toPool;
        rewardsDistributor.depositRewards{value: toPool}();
        (bool ok,) = payable(treasury).call{value: toTreasury}("");
        if (!ok) revert TransferFailed();

        if (msg.value > cost) {
            (bool refundOk,) = payable(msg.sender).call{value: msg.value - cost}("");
            if (!refundOk) revert TransferFailed();
        }

        rewardsDistributor.syncFund(tokenId);

        emit Recapitalized(tokenId, cost);
    }

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

    /// @notice Attacks another fund. Requires the ATTACKER to be established (>= 4 computers AND
    ///         >= 1 worker). Steal % scales with attacker hackers, reduced by defender hackers.
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
        if (attacker.computers < TAKEOVER_MIN_COMPUTERS) revert TakeoverLockedNeedComputers();
        if (totalWorkers(attackerTokenId) == 0) revert TakeoverLockedNeedWorker();
        if (keccak256(abi.encodePacked(reveal)) != attacker.randomCommitment) revert BadReveal();
        if (block.timestamp < lastAttackedAt[defenderTokenId] + TAKEOVER_IMMUNITY) revert DefenderImmune();

        gameToken.burnFrom(msg.sender, TAKEOVER_STAKE);

        uint256 stealBps = TAKEOVER_BASE_STEAL_BPS + uint256(attacker.hackers) * TAKEOVER_HACKER_STEAL_BPS;
        if (stealBps > TAKEOVER_MAX_STEAL_BPS) stealBps = TAKEOVER_MAX_STEAL_BPS;
        uint256 defense = uint256(defender.hackers) * TAKEOVER_HACKER_DEFENSE_BPS;
        stealBps = defense >= stealBps ? 0 : stealBps - defense;

        uint256 stolen = stealBps == 0 ? 0 : rewardsDistributor.seizeRewards(defenderTokenId, attackerTokenId, stealBps);

        uint256 roll = uint256(keccak256(abi.encodePacked(reveal, attackerTokenId, defenderTokenId))) % BPS_DENOMINATOR;
        bool workerLost = roll < TAKEOVER_WORKER_LOSS_BPS && totalWorkers(defenderTokenId) > 0;
        if (workerLost) {
            _layOff(defender, 1);
        }

        attacker.randomCommitment = nextCommitment;
        lastAttackedAt[defenderTokenId] = uint64(block.timestamp);

        rewardsDistributor.syncFund(attackerTokenId);
        rewardsDistributor.syncFund(defenderTokenId);

        emit TakeoverExecuted(attackerTokenId, defenderTokenId, stolen, workerLost);
    }

    /// @notice Resets a fund's stats to zero on full redemption. NFT survives. Restricted to RewardsDistributor.
    function resetFundForRedemption(uint256 tokenId) external onlyRewardsDistributor {
        Fund storage f = funds[tokenId];
        totalScore -= f.score;
        f.hackers = 0;
        f.analysts = 0;
        f.brokers = 0;
        f.computers = 0;
        f.score = 0;
        f.yieldBalance = 0;
        f.capitalBalance = 0;
        f.lastRebalance = uint64(block.timestamp);
        f.yieldCooldownEnd = 0;
        f.capitalCooldownEnd = 0;
    }

    /// @notice Reduces a fund's score by `bps` (out of 10,000). Restricted to RewardsDistributor.
    function applyScoreHaircut(uint256 tokenId, uint256 bps) external onlyRewardsDistributor {
        Fund storage f = funds[tokenId];
        uint256 loss = (uint256(f.score) * bps) / BPS_DENOMINATOR;
        f.score -= uint128(loss);
        totalScore -= loss;
    }
}
