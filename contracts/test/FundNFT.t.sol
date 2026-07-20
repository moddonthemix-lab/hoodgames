// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {BaseTest} from "./BaseTest.sol";
import {FundNFT} from "../src/FundNFT.sol";

contract FundNFTTest is BaseTest {
    bytes32 constant S0 = keccak256("s0");
    bytes32 constant S1 = keccak256("s1");

    function testMintRevertsIfNotGameEngine() public {
        vm.expectRevert(FundNFT.NotGameEngine.selector);
        fundNFT.mint(alice);
    }

    function testBurnRevertsIfNotGameEngine() public {
        uint256 tokenId = _mintFund(alice, S0);
        vm.expectRevert(FundNFT.NotGameEngine.selector);
        fundNFT.burn(tokenId);
    }

    function testSetGameEngineRevertsIfAlreadySet() public {
        // BaseTest.setUp() already wired this.
        vm.prank(owner);
        vm.expectRevert(FundNFT.GameEngineAlreadySet.selector);
        fundNFT.setGameEngine(makeAddr("otherEngine"));
    }

    function testExists() public {
        uint256 tokenId = _mintFund(alice, S0);
        assertTrue(fundNFT.exists(tokenId));
        assertFalse(fundNFT.exists(tokenId + 1));
    }

    function testTokenURIRevertsForNonexistentToken() public {
        vm.expectRevert(FundNFT.TokenDoesNotExist.selector);
        fundNFT.tokenURI(999);
    }

    function testTokenURIReflectsLiveState() public {
        uint256 tokenId = _mintFund(alice, S0);
        string memory uriBefore = fundNFT.tokenURI(tokenId);

        vm.warp(block.timestamp + 30 hours);
        _rebalance(alice, tokenId, S0, S1); // changes score -> JSON metadata changes

        string memory uriAfter = fundNFT.tokenURI(tokenId);
        assertFalse(keccak256(bytes(uriBefore)) == keccak256(bytes(uriAfter)));
    }

    function testPauseBlocksMint() public {
        vm.prank(owner);
        fundNFT.pause();

        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        gameEngine.mintFund{value: MINT_FEE}(_commitment(S0));
    }
}
