//SPDX-Licence-Identifier : MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Ratio_Swapping_Auctions_V1_1} from "../src/AuctionSwap/OrxaSwap.sol";
contract AuctionSwapDeploy is Script {
    function run() external {
        address davToken = 0x184311E6522Bec0Faa79c87e491717325416Ad1A;
        address StatToken = 0x7B5BEFD18836DF1E72a21B328D34cc35aA1743b5;
        address Fluxin = 0x38B34C2fD8c41E040636110f801Ab4CD2cA71E53;
        address governance = 0xB1bD9F3B5F64dE482485A41c84ea4a90DAc5F98e;

        address pairAddress = 0x361aFa3F5EF839bED6071c9F0c225b078eB8089a; // for orxa
        address orxaToken = 0x6F01eEc1111748B66f735944b18b0EB2835aE201;
        address pstateToken = 0x63CC0B2CA22b260c7FD68EBBaDEc2275689A3969;
        vm.startBroadcast();

        Ratio_Swapping_Auctions_V1_1 swap = new Ratio_Swapping_Auctions_V1_1(
            StatToken,
            davToken,
            Fluxin,
            governance,
            pstateToken,
            orxaToken,
            pairAddress
        );
        console.log("Swap deployed at:", address(swap));
        vm.stopBroadcast();
    }
}
