//SPDX-Licence-Identifier : MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Ratio_Swapping_Auctions_V1_1} from "../src/AuctionSwap/OrxaSwap.sol";
contract AuctionSwapDeploy is Script {
    function run() external {
        address davToken = 0xCf7A569E5f90ae07402693288Bdd34fbA646d80a;
        address StatToken = 0x74946B123EcE457c2d72e2254EEe678d60C6f569;
        address Fluxin = 0xEEBBA46F588BB88c2e49A5B51e49f05A56dBA2C6;
        address governance = 0xB1bD9F3B5F64dE482485A41c84ea4a90DAc5F98e;

        vm.startBroadcast();

        Ratio_Swapping_Auctions_V1_1 swap = new Ratio_Swapping_Auctions_V1_1(
            StatToken,
            davToken,
            Fluxin,
            governance
        );
        console.log("Swap deployed at:", address(swap));
        vm.stopBroadcast();
    }
}
