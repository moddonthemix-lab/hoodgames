// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IFundNFT} from "./interfaces/IFundNFT.sol";
import {IGameEngine} from "./interfaces/IGameEngine.sol";

/// @title FundNFT
/// @notice ERC-721 identity token for a MARGIN fund. Deliberately holds no gameplay state —
///         GameEngine is the single source of truth (see MARGIN_SPEC.md section 5 / DECISIONS.md
///         "storage layout" entry). This contract only tracks ownership, mints, burns, and
///         renders dynamic metadata by reading live state from GameEngine.
contract FundNFT is ERC721, Ownable, Pausable, IFundNFT {
    using Strings for uint256;

    /// @notice The GameEngine contract, the only address allowed to mint/burn. Set once by the
    ///         owner after both contracts are deployed (they reference each other), then locked.
    address public gameEngine;

    uint256 private _nextTokenId = 1;

    event GameEngineSet(address indexed gameEngine);

    error GameEngineAlreadySet();
    error NotGameEngine();
    error TokenDoesNotExist();
    error ZeroAddress();

    modifier onlyGameEngine() {
        if (msg.sender != gameEngine) revert NotGameEngine();
        _;
    }

    constructor(address initialOwner) ERC721("MARGIN Fund", "FUND") Ownable(initialOwner) {}

    /// @notice One-time wiring of the GameEngine address. Privileged: owner only, callable once.
    ///         Locked after the first call so a compromised owner key can never redirect
    ///         mint/burn authority to a different contract post-launch.
    function setGameEngine(address _gameEngine) external onlyOwner {
        if (gameEngine != address(0)) revert GameEngineAlreadySet();
        if (_gameEngine == address(0)) revert ZeroAddress();
        gameEngine = _gameEngine;
        emit GameEngineSet(_gameEngine);
    }

    /// @notice Privileged: owner only. Launch-phase safety switch on minting.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Privileged: owner only.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc IFundNFT
    function mint(address to) external onlyGameEngine whenNotPaused returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
    }

    /// @inheritdoc IFundNFT
    function burn(uint256 tokenId) external onlyGameEngine {
        _burn(tokenId);
    }

    /// @dev Explicit override needed: IFundNFT and ERC721 both declare `ownerOf`.
    function ownerOf(uint256 tokenId) public view override(ERC721, IFundNFT) returns (address) {
        return super.ownerOf(tokenId);
    }

    /// @inheritdoc IFundNFT
    function exists(uint256 tokenId) external view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    /// @notice Total funds ever minted (liquidated ones included — this is a lifetime count, not
    ///         a live "alive funds" count). Frontend-only convenience for the landing page's
    ///         global stats; token IDs are sequential starting at 1 so this is just the counter.
    function totalMinted() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        IGameEngine.FundView memory fund = IGameEngine(gameEngine).getFund(tokenId);

        string memory statusStr = fund.status == IGameEngine.FundStatus.Active
            ? "Active"
            : fund.status == IGameEngine.FundStatus.MarginCalled
                ? "MarginCalled"
                : "Liquidated";

        uint256 workers = uint256(fund.hackers) + fund.analysts + fund.brokers;

        // solhint-disable-next-line quotes
        bytes memory json = abi.encodePacked(
            '{"name":"MARGIN Fund #',
            tokenId.toString(),
            '","description":"An onchain fund on MARGIN. Rebalance every 72h or get margin called.",',
            '"attributes":[',
            '{"trait_type":"Status","value":"',
            statusStr,
            '"},',
            '{"trait_type":"Workers","value":',
            workers.toString(),
            "},",
            '{"trait_type":"Hackers","value":',
            uint256(fund.hackers).toString(),
            "},",
            '{"trait_type":"Analysts","value":',
            uint256(fund.analysts).toString(),
            "},",
            '{"trait_type":"Brokers","value":',
            uint256(fund.brokers).toString(),
            "},",
            '{"trait_type":"Computers","value":',
            uint256(fund.computers).toString(),
            "},",
            '{"trait_type":"Score","value":',
            uint256(fund.score).toString(),
            "}",
            "]}"
        );

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }
}
