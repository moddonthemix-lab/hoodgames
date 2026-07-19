// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// NOTE: requires forge-std, which is not yet installed in this environment (GitHub access here
// is scoped away from foundry-rs/forge-std — see README / session notes). Once you have forge
// available with full GitHub access, run:
//   forge install foundry-rs/forge-std --no-commit
// before running this script.
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {FundNFT} from "../src/FundNFT.sol";
import {GameToken} from "../src/GameToken.sol";
import {GameEngine} from "../src/GameEngine.sol";
import {RewardsDistributor} from "../src/RewardsDistributor.sol";
import {AUMStaking} from "../src/AUMStaking.sol";
import {Treasury} from "../src/Treasury.sol";
import {IFundNFT} from "../src/interfaces/IFundNFT.sol";
import {IGameToken} from "../src/interfaces/IGameToken.sol";
import {IRewardsDistributor} from "../src/interfaces/IRewardsDistributor.sol";
import {NetworkConfig} from "./config/NetworkConfig.sol";

/// @title Deploy
/// @notice Deploys and wires the full MARGIN contract suite in the correct order (see
///         DECISIONS.md / MARGIN_SPEC.md section 5 for the circular-dependency resolution:
///         FundNFT/GameEngine reference each other via a one-time setter, same for
///         RewardsDistributor/AUMStaking/Treasury).
/// @dev Nothing here deploys anywhere without an explicit `forge script ... --broadcast` run
///      with an operator-approved RPC target, per the project's ground rules. Run against
///      `local` (Anvil) first.
///
///      DOES NOT transfer ownership to a timelock. MARGIN_SPEC.md section 5 requires a
///      "Pausable + timelocked owner for launch phase" — before any testnet/mainnet deploy that
///      matters, deploy an OZ TimelockController (48h min delay per the original prompt) and
///      call `transferOwnership` on every contract deployed here, OR pass its address in as
///      `deployerOrTimelock` directly. Left as a manual post-deploy step / TODO for Phase 5
///      hardening rather than baked into this script, so local/testnet iteration isn't slowed
///      down by a 48h delay on every parameter tweak.
contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        NetworkConfig.Config memory net = NetworkConfig.getConfig(block.chainid);

        address lpRecipient = vm.envOr("LP_RECIPIENT", deployer);
        address devRecipient = vm.envOr("DEV_RECIPIENT", deployer);
        address airdropRecipient = vm.envOr("AIRDROP_RECIPIENT", deployer);
        address gameRewardsPoolHolder = vm.envOr("GAME_REWARDS_POOL_HOLDER", deployer);
        address devTreasury = vm.envOr("DEV_TREASURY", deployer);
        address lpLockRecipient = vm.envOr("LP_LOCK_RECIPIENT", address(0x000000000000000000000000000000000000dEaD));

        vm.startBroadcast(deployerKey);

        FundNFT fundNFT = new FundNFT(deployer);

        GameToken gameToken = new GameToken(
            deployer, devTreasury, lpRecipient, devRecipient, airdropRecipient, gameRewardsPoolHolder
        );

        GameEngine gameEngine = new GameEngine(deployer, IFundNFT(address(fundNFT)), IGameToken(address(gameToken)));
        fundNFT.setGameEngine(address(gameEngine));

        RewardsDistributor rewardsDistributor = new RewardsDistributor(deployer);
        gameEngine.setRewardsDistributor(IRewardsDistributor(address(rewardsDistributor)));
        rewardsDistributor.setGameEngine(address(gameEngine));
        rewardsDistributor.setFundNFT(address(fundNFT));

        AUMStaking aumStaking = new AUMStaking(
            deployer, IFundNFT(address(fundNFT)), IGameToken(address(gameToken)), IRewardsDistributor(address(rewardsDistributor))
        );
        rewardsDistributor.setAumStaking(address(aumStaking));

        Treasury treasury = new Treasury(
            deployer,
            IGameToken(address(gameToken)),
            IRewardsDistributor(address(rewardsDistributor)),
            net.uniswapRouter,
            lpLockRecipient
        );
        gameEngine.setTreasury(address(treasury));
        gameToken.setTreasury(address(treasury));

        // Exempt game contracts from GameToken's buy/sell tax so internal accounting transfers
        // (emissions, burns via allowance, staking, etc.) aren't taxed.
        gameToken.setTaxExempt(address(gameEngine), true);
        gameToken.setTaxExempt(address(aumStaking), true);
        gameToken.setTaxExempt(address(rewardsDistributor), true);

        // Forward the GameRewardsPool allocation (2% of supply, minted to gameRewardsPoolHolder
        // at TGE — see GameToken constructor NatSpec) into GameEngine, which pays it out as
        // per-epoch $MGN P&L emissions. Only works if gameRewardsPoolHolder == deployer (the
        // default); if you set GAME_REWARDS_POOL_HOLDER to a different address, that address
        // must send GameToken.TOTAL_SUPPLY * 2 / 100 to `gameEngine` itself.
        if (gameRewardsPoolHolder == deployer) {
            uint256 poolAmount = (gameToken.TOTAL_SUPPLY() * 2) / 100;
            gameToken.transfer(address(gameEngine), poolAmount);
        }

        vm.stopBroadcast();

        console2.log("FundNFT:", address(fundNFT));
        console2.log("GameToken:", address(gameToken));
        console2.log("GameEngine:", address(gameEngine));
        console2.log("RewardsDistributor:", address(rewardsDistributor));
        console2.log("AUMStaking:", address(aumStaking));
        console2.log("Treasury:", address(treasury));

        if (net.uniswapRouter == address(0)) {
            console2.log("WARNING: uniswapRouter is a TODO placeholder (address(0)) - Treasury.epochSweep will revert until set via Treasury.setRouter().");
        }
    }
}
