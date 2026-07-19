// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal UniswapV2Router02-shaped interface — only the functions Treasury needs.
/// @dev ASSUMPTION, NOT CONFIRMED: MARGIN_SPEC.md section 1 says Robinhood Chain has "a
///      dedicated AMM on-chain" without specifying V2 vs V3 vs a custom fork. This interface
///      matches the widely-compatible UniswapV2Router02 shape as the most common default. Before
///      deploying, verify the actual router interface from Robinhood Chain's official developer
///      docs (see script/config/NetworkConfig.sol TODOs) and adjust Treasury.sol if it's V3
///      (different interface entirely — exactInputSingle style) or a custom AMM.
interface IUniswapV2Router02Minimal {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    function WETH() external pure returns (address);
}
