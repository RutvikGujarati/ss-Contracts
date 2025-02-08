//SPDX-Licence-Identifier : MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {AuctionRatioSwapping} from "../src/AuctionSwap/XerionSwap.sol";
contract AuctionSwapDeploy is Script {
    function run() external {
        address davToken = 0x1a44c22FB260cB1fF082501299c588e9078346a2;
        address StatToken = 0x41b15BeA9cdfA72c9D715E59a255291337A72A60;
        address Fluxin = 0xd8043B2A2f7aCac495661F5149D3a10D9E6F433F;
        address governance = 0xB1bD9F3B5F64dE482485A41c84ea4a90DAc5F98e;

        vm.startBroadcast();

        AuctionRatioSwapping swap = new AuctionRatioSwapping(
            StatToken,
            davToken,
            Fluxin,
            governance
        );
        console.log("Swap deployed at:", address(swap));
        vm.stopBroadcast();
    }
}
