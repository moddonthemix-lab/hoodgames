// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IFundNFT
/// @notice ERC-721 identity token for a fund. Holds no gameplay state — GameEngine is the
///         source of truth; this contract only tracks ownership and mints/burns on its behalf.
interface IFundNFT {
    /// @notice Mints a new Fund NFT to `to`. Restricted to the GameEngine.
    function mint(address to) external returns (uint256 tokenId);

    /// @notice Burns a Fund NFT on liquidation. Restricted to the GameEngine.
    function burn(uint256 tokenId) external;

    function ownerOf(uint256 tokenId) external view returns (address);

    function exists(uint256 tokenId) external view returns (bool);
}
