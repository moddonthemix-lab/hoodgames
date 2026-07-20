// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IGameToken} from "./interfaces/IGameToken.sol";
import {IRewardsDistributor} from "./interfaces/IRewardsDistributor.sol";
import {IUniswapV2Router02Minimal} from "./interfaces/IUniswapV2Router02Minimal.sol";

/// @title Treasury
/// @notice Epoch sweep: pulls the accumulated players+LP $MGN tax share from GameToken, swaps the
///         players share to ETH and forwards it to RewardsDistributor, and re-deepens the Uniswap
///         LP position with the LP share (locked to `lpLockRecipient`, e.g. a burn address).
///         Also holds the 30% Treasury cut of recapitalization penalties (MARGIN_SPEC.md section 3
///         Track 2 item 3) as protocol revenue, withdrawable by the owner.
/// @dev Router interface is an UNCONFIRMED assumption — see IUniswapV2Router02Minimal.sol.
///      Slippage protection (`minEthOutForPlayers`/`minEthOutForLp`) is caller-supplied rather
///      than computed on-chain from an oracle: this keeps Phase 1 simple by pushing the
///      responsibility to the off-chain keeper script (scripts/), which can quote a live price.
///      This is a known Phase-1 simplification — see DECISIONS.md open items — a keeper that
///      always passes 0 would expose sweeps to sandwich attacks; the keeper script must not do that.
contract Treasury is Ownable, ReentrancyGuard {
    using SafeERC20 for IGameToken;

    IGameToken public immutable gameToken;
    IRewardsDistributor public immutable rewardsDistributor;

    /// @notice UNCONFIRMED — verify against Robinhood Chain's official DEX docs before deploy.
    address public router;
    /// @notice Recipient of LP tokens minted by epochSweep's auto-liquidity add. Recommended:
    ///         a burn address (e.g. 0x…dEaD) for a permanently locked, un-rug-pullable LP position.
    address public lpLockRecipient;
    uint256 public minSweepThreshold = 1 ether; // 1 $MGN; avoids sweeping dust for more gas than it's worth

    event RouterSet(address indexed router);
    event LpLockRecipientSet(address indexed recipient);
    event MinSweepThresholdSet(uint256 threshold);
    event EpochSwept(uint256 playersTokenAmount, uint256 ethToRewards, uint256 lpTokenAmount, uint256 lpTokensMinted);
    event TreasuryWithdrawn(address indexed to, uint256 amount);

    error ZeroAddress();
    error TransferFailed();

    constructor(
        address initialOwner,
        IGameToken _gameToken,
        IRewardsDistributor _rewardsDistributor,
        address _router,
        address _lpLockRecipient
    ) Ownable(initialOwner) {
        gameToken = _gameToken;
        rewardsDistributor = _rewardsDistributor;
        router = _router;
        lpLockRecipient = _lpLockRecipient;
    }

    receive() external payable {}

    /// @notice Privileged: owner only. Router address is a TODO placeholder until confirmed —
    ///         see contract-level NatSpec — so this stays adjustable rather than locked.
    function setRouter(address _router) external onlyOwner {
        if (_router == address(0)) revert ZeroAddress();
        router = _router;
        emit RouterSet(_router);
    }

    function setLpLockRecipient(address _lpLockRecipient) external onlyOwner {
        if (_lpLockRecipient == address(0)) revert ZeroAddress();
        lpLockRecipient = _lpLockRecipient;
        emit LpLockRecipientSet(_lpLockRecipient);
    }

    function setMinSweepThreshold(uint256 threshold) external onlyOwner {
        minSweepThreshold = threshold;
        emit MinSweepThresholdSet(threshold);
    }

    /// @notice Keeper-callable (scripts/epoch-keeper). Sweeps GameToken's accumulated tax share,
    ///         converts the players' share to ETH for RewardsDistributor, and re-deepens LP with
    ///         the LP share. `minEthOutForPlayers`/`minEthOutForLp` are slippage floors the caller
    ///         must compute off-chain — see contract-level NatSpec.
    function epochSweep(uint256 minEthOutForPlayers, uint256 minEthOutForLp) external nonReentrant {
        (uint256 playersAmount, uint256 lpAmount) = gameToken.sweepPendingTax();

        uint256 ethToRewards;
        if (playersAmount >= minSweepThreshold) {
            ethToRewards = _swapTokensForEth(playersAmount, minEthOutForPlayers, address(this));
            if (ethToRewards > 0) {
                rewardsDistributor.depositRewards{value: ethToRewards}();
            }
        }

        uint256 lpTokensMinted;
        if (lpAmount >= minSweepThreshold) {
            uint256 half = lpAmount / 2;
            uint256 ethForLp = _swapTokensForEth(half, minEthOutForLp, address(this));
            uint256 tokenForLp = lpAmount - half;
            if (ethForLp > 0 && tokenForLp > 0) {
                gameToken.forceApprove(router, tokenForLp);
                (,, lpTokensMinted) = IUniswapV2Router02Minimal(router).addLiquidityETH{value: ethForLp}(
                    address(gameToken), tokenForLp, 0, 0, lpLockRecipient, block.timestamp
                );
            }
        }

        emit EpochSwept(playersAmount, ethToRewards, lpAmount, lpTokensMinted);
    }

    function _swapTokensForEth(uint256 amountIn, uint256 minOut, address to) internal returns (uint256) {
        if (amountIn == 0) return 0;
        uint256 balanceBefore = to.balance;

        address[] memory path = new address[](2);
        path[0] = address(gameToken);
        path[1] = IUniswapV2Router02Minimal(router).WETH();

        gameToken.forceApprove(router, amountIn);
        IUniswapV2Router02Minimal(router).swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountIn, minOut, path, to, block.timestamp
        );

        return to.balance - balanceBefore;
    }

    /// @notice Privileged: owner only (should be the 48h-timelock per MARGIN_SPEC.md section 5).
    ///         Withdraws accumulated protocol revenue — the 30% Treasury cut of recapitalization
    ///         penalties (GameEngine.recapitalize). Not player funds; nothing here is owed to a
    ///         specific user, so no pull-payment pattern is needed.
    function withdrawTreasuryBalance(address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        (bool ok,) = payable(to).call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit TreasuryWithdrawn(to, amount);
    }
}
