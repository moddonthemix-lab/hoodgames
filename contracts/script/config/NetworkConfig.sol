// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title NetworkConfig
/// @notice Network-specific external addresses. EVERY Robinhood Chain address below is a TODO
///         placeholder (address(0)) — filled in with address(0) on purpose so a deploy script
///         using this config fails loudly (see `PlaceholderAddressNotSet`) instead of silently
///         deploying broken wiring to a real network.
///
/// Where to get the real values (per MARGIN_SPEC.md section 1 ground rules — do not guess):
///   - RPC URLs, chain metadata: Robinhood Chain's official developer documentation portal.
///     Look for a "Network Info" / "RPC Endpoints" / "Connect to Robinhood Chain" page.
///   - Uniswap router/factory/WETH addresses: the same developer docs, under a "DEX" /
///     "Uniswap Deployment" / "Contract Addresses" section — confirm whether it's a V2-shaped
///     router (as assumed by IUniswapV2Router02Minimal.sol) or V3/custom (different interface,
///     would need Treasury.sol's swap logic rewritten).
///   - Chainlink feed addresses: Robinhood Chain docs' "Oracles" / "Chainlink" section, or
///     https://docs.chain.link/data-feeds/price-feeds/addresses filtered to Robinhood Chain once
///     Chainlink lists it.
///   - Stock Token contract addresses (NVDA/AAPL/TSLA etc., used ONLY by the frontend's
///     user-signed Uniswap swap step — MARGIN_SPEC.md section 4, contracts never touch these):
///     Robinhood Chain docs' "Stock Tokens" / "Tokenized Equities" section.
library NetworkConfig {
    struct Config {
        uint256 chainId;
        address uniswapRouter;
        address uniswapFactory;
        address weth;
        address chainlinkEthUsdFeed;
    }

    uint256 internal constant ROBINHOOD_CHAIN_ID = 4663;
    /// @dev Fallback per ground rules: "Arbitrum Sepolia if RH testnet unavailable".
    uint256 internal constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;
    uint256 internal constant LOCAL_CHAIN_ID = 31337;

    error UnknownChainId(uint256 chainId);
    error PlaceholderAddressNotSet(string what);

    function getConfig(uint256 chainId) internal pure returns (Config memory config) {
        if (chainId == ROBINHOOD_CHAIN_ID) {
            config = Config({
                chainId: ROBINHOOD_CHAIN_ID,
                uniswapRouter: address(0), // TODO
                uniswapFactory: address(0), // TODO
                weth: address(0), // TODO
                chainlinkEthUsdFeed: address(0) // TODO, optional for Phase 1
            });
        } else if (chainId == ARBITRUM_SEPOLIA_CHAIN_ID) {
            config = Config({
                chainId: ARBITRUM_SEPOLIA_CHAIN_ID,
                uniswapRouter: address(0), // TODO if this fallback path is used
                uniswapFactory: address(0), // TODO
                weth: address(0), // TODO
                chainlinkEthUsdFeed: address(0)
            });
        } else if (chainId == LOCAL_CHAIN_ID) {
            // Local Anvil: the deploy script should deploy a mock router/WETH itself, or the
            // node should be a fork of a network that already has real Uniswap deployed.
            config = Config({
                chainId: LOCAL_CHAIN_ID,
                uniswapRouter: address(0),
                uniswapFactory: address(0),
                weth: address(0),
                chainlinkEthUsdFeed: address(0)
            });
        } else {
            revert UnknownChainId(chainId);
        }
    }

    /// @notice Reverts if `addr` is the placeholder zero address, naming what's missing.
    function requireSet(address addr, string memory what) internal pure {
        if (addr == address(0)) revert PlaceholderAddressNotSet(what);
    }
}
