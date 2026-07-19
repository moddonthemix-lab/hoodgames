// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IGameToken} from "./interfaces/IGameToken.sol";

/// @title GameToken ($MGN)
/// @notice Fixed-supply (10,000,000, fully minted at TGE — no mint()) tax token. 5% buy/sell tax
///         split 1% dev / 3% players (rewards pool, swept to RewardsDistributor as ETH) / 1% LP.
/// @dev Deliberately has NO pause/blacklist capability on transfers. Robinhood Chain is monitored
///      by Chainalysis KYT (MARGIN_SPEC.md section 1) and a pausable/blacklistable token is a
///      classic honeypot/rug red flag — see DECISIONS.md. The Pausable + timelocked-owner
///      requirement (MARGIN_SPEC.md section 5) is satisfied at GameEngine/RewardsDistributor/
///      AUMStaking instead, where it protects user funds rather than restricts free transfer.
contract GameToken is ERC20, ERC20Burnable, Ownable, IGameToken {
    uint256 public constant TOTAL_SUPPLY = 10_000_000 ether;

    uint16 public constant MAX_TAX_BPS = 500; // 5.00%, hard ceiling forever
    uint16 public constant DEV_SHARE_OF_TAX_BPS = 2000; // 1% of 5% = 20% of the tax
    uint16 public constant PLAYERS_SHARE_OF_TAX_BPS = 6000; // 3% of 5% = 60% of the tax
    uint16 public constant LP_SHARE_OF_TAX_BPS = 2000; // 1% of 5% = 20% of the tax
    uint16 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Current buy/sell tax rate in bps. Starts at MAX_TAX_BPS, may only be lowered.
    uint16 public taxBps = MAX_TAX_BPS;

    /// @notice Payout address for the dev share of tax. Rotatable by owner (routine ops address).
    address public devTreasury;

    /// @notice The Treasury.sol contract that sweeps accumulated players+LP token share and
    ///         converts it to ETH. Set once by owner, then locked — see FundNFT.setGameEngine
    ///         for the same pattern and rationale (prevents an owner key from redirecting tax flow).
    address public treasury;

    mapping(address => bool) public isTaxExempt;
    mapping(address => bool) public isAMMPair;

    uint256 public pendingPlayersShare;
    uint256 public pendingLPShare;

    event TaxBpsLowered(uint16 oldBps, uint16 newBps);
    event TaxExemptSet(address indexed account, bool exempt);
    event AMMPairSet(address indexed pair, bool isPair);
    event TreasurySet(address indexed treasury);
    event DevTreasurySet(address indexed devTreasury);
    event TaxSwept(address indexed to, uint256 playersAmount, uint256 lpAmount);

    error TaxCannotBeRaised();
    error TreasuryAlreadySet();
    error NotTreasury();
    error ZeroAddress();

    modifier onlyTreasury() {
        if (msg.sender != treasury) revert NotTreasury();
        _;
    }

    /// @param initialOwner Owner address (should be a timelock/multisig before mainnet).
    /// @param devTreasury_ Initial dev fee payout address.
    /// @param lpRecipient Receives 90% of supply, for Uniswap LP seeding.
    /// @param devRecipient Receives 3% of supply, dev allocation.
    /// @param airdropRecipient Receives 5% of supply (e.g. a merkle-claim contract).
    /// @param gameRewardsPoolRecipient Receives 2% of supply — funds GameEngine's per-epoch
    ///        $MGN P&L emissions (see DECISIONS.md "Emission rate" entry). Fixed supply, no mint,
    ///        so payouts are capped by this pool's balance, never inflationary.
    constructor(
        address initialOwner,
        address devTreasury_,
        address lpRecipient,
        address devRecipient,
        address airdropRecipient,
        address gameRewardsPoolRecipient
    ) ERC20("MARGIN", "MGN") Ownable(initialOwner) {
        if (devTreasury_ == address(0)) revert ZeroAddress();
        devTreasury = devTreasury_;

        _mint(lpRecipient, (TOTAL_SUPPLY * 90) / 100);
        _mint(devRecipient, (TOTAL_SUPPLY * 3) / 100);
        _mint(airdropRecipient, (TOTAL_SUPPLY * 5) / 100);
        _mint(gameRewardsPoolRecipient, (TOTAL_SUPPLY * 2) / 100);

        isTaxExempt[lpRecipient] = true;
        isTaxExempt[devRecipient] = true;
        isTaxExempt[airdropRecipient] = true;
        isTaxExempt[gameRewardsPoolRecipient] = true;
        isTaxExempt[initialOwner] = true;
        isTaxExempt[address(this)] = true;
    }

    /// @notice Privileged: owner only. May only lower the tax rate, never raise it.
    function setTaxBps(uint16 newBps) external onlyOwner {
        if (newBps > taxBps) revert TaxCannotBeRaised();
        emit TaxBpsLowered(taxBps, newBps);
        taxBps = newBps;
    }

    /// @notice Privileged: owner only. Exempts game contracts / operational addresses from tax
    ///         so internal accounting transfers aren't double-taxed.
    function setTaxExempt(address account, bool exempt) external onlyOwner {
        isTaxExempt[account] = exempt;
        emit TaxExemptSet(account, exempt);
    }

    /// @notice Privileged: owner only. Registers/deregisters a Uniswap pair address so buy/sell
    ///         tax applies. Manual (not auto-detected from factory) until the exact DEX interface
    ///         on Robinhood Chain is confirmed — see MARGIN_SPEC.md section 1 ground rules.
    function setAMMPair(address pair, bool isPair) external onlyOwner {
        isAMMPair[pair] = isPair;
        emit AMMPairSet(pair, isPair);
    }

    /// @notice Privileged: owner only, callable once. Locks in the Treasury contract that's
    ///         allowed to sweep the accumulated players+LP tax share.
    function setTreasury(address _treasury) external onlyOwner {
        if (treasury != address(0)) revert TreasuryAlreadySet();
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
        isTaxExempt[_treasury] = true;
        emit TreasurySet(_treasury);
    }

    /// @notice Privileged: owner only. Rotates the dev fee payout address.
    function setDevTreasury(address _devTreasury) external onlyOwner {
        if (_devTreasury == address(0)) revert ZeroAddress();
        devTreasury = _devTreasury;
        emit DevTreasurySet(_devTreasury);
    }

    /// @notice Sweeps accumulated players+LP tax share to Treasury for ETH conversion. Restricted
    ///         to the Treasury contract itself (pull, not push, called from its epoch sweep).
    function sweepPendingTax() external onlyTreasury returns (uint256 playersAmount, uint256 lpAmount) {
        playersAmount = pendingPlayersShare;
        lpAmount = pendingLPShare;
        pendingPlayersShare = 0;
        pendingLPShare = 0;
        if (playersAmount + lpAmount > 0) {
            _transfer(address(this), treasury, playersAmount + lpAmount);
        }
        emit TaxSwept(treasury, playersAmount, lpAmount);
    }

    // isTaxExempt(address) satisfying IGameToken is auto-generated by the public mapping above.

    /// @dev Explicit override needed: IGameToken and ERC20Burnable both declare `burn`.
    function burn(uint256 amount) public override(ERC20Burnable, IGameToken) {
        super.burn(amount);
    }

    /// @dev Explicit override needed: IGameToken and ERC20Burnable both declare `burnFrom`.
    function burnFrom(address account, uint256 amount) public override(ERC20Burnable, IGameToken) {
        super.burnFrom(account, amount);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20) {
        bool isBuyOrSell = isAMMPair[from] || isAMMPair[to];
        bool exempt = isTaxExempt[from] || isTaxExempt[to];
        bool isMintOrBurn = from == address(0) || to == address(0);

        if (!isBuyOrSell || exempt || isMintOrBurn || taxBps == 0) {
            super._update(from, to, value);
            return;
        }

        uint256 taxAmount = (value * taxBps) / BPS_DENOMINATOR;
        uint256 devAmount = (taxAmount * DEV_SHARE_OF_TAX_BPS) / BPS_DENOMINATOR;
        uint256 lpAmount = (taxAmount * LP_SHARE_OF_TAX_BPS) / BPS_DENOMINATOR;
        uint256 playersAmount = taxAmount - devAmount - lpAmount;

        pendingPlayersShare += playersAmount;
        pendingLPShare += lpAmount;

        super._update(from, devTreasury, devAmount);
        super._update(from, address(this), playersAmount + lpAmount);
        super._update(from, to, value - taxAmount);
    }
}
