//SPDX-Licence-Identifier : MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Ratio_Swapping_Auctions_V1_1} from "../src/AuctionSwap/OrxaSwap.sol";
contract AuctionSwapDeploy is Script {
    function run() external {
        address davToken = 0xE781A1F1B7971cCB51d600461Fcde69605D9A164;
        address StatToken = 0x86e45e74F9BD80f6cD7bdf32F95138102a3f3076;
        address Fluxin = 0xf3409065D3E3a45ee477d6A7BBC9cF44D9BE4Aa7;
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
