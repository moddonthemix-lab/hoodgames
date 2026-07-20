// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IFundNFT} from "../../src/interfaces/IFundNFT.sol";

/// @notice Minimal IFundNFT double: just an owner mapping, settable directly by the test.
contract MockFundNFTForRewards is IFundNFT {
    mapping(uint256 => address) public ownerOf;

    function setOwner(uint256 tokenId, address account) external {
        ownerOf[tokenId] = account;
    }

    function mint(address) external pure returns (uint256) {
        revert("not implemented");
    }

    function burn(uint256) external pure {
        revert("not implemented");
    }

    function exists(uint256 tokenId) external view returns (bool) {
        return ownerOf[tokenId] != address(0);
    }
}
