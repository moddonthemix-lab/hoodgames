// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IGameToken
/// @notice $MGN — the farmable game token. 5% buy/sell tax (1% dev / 3% players / 1% LP),
///         burn sinks for game actions, tax-exempt game contracts.
interface IGameToken is IERC20 {
    /// @notice Burns `amount` from `account`, spending `msg.sender`'s allowance. Used by
    ///         GameEngine/AUMStaking for rebalance/desk/takeover/exit-fee burn sinks.
    function burnFrom(address account, uint256 amount) external;

    /// @notice Burns `amount` from the caller's own balance (ERC20Burnable). Used by AUMStaking's
    ///         instant-unstake exit fee, which the contract burns from its own held stake.
    function burn(uint256 amount) external;

    function isTaxExempt(address account) external view returns (bool);

    /// @notice Sweeps accumulated players+LP tax share to the caller. Restricted to the
    ///         Treasury contract on the concrete implementation — see GameToken.sol.
    function sweepPendingTax() external returns (uint256 playersAmount, uint256 lpAmount);
}
