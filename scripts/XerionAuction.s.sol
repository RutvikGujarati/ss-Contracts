//SPDX-Licence-Identifier : MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {AuctionRatioSwapping} from "../src/AuctionSwap/XerionSwap.sol";
contract AuctionSwapDeploy is Script {
    function run() external {
        address davToken = 0x9BeDBBEF7482D62A51468665914623eB12247b08;
        address StatToken = 0x54f6bf8D07240c4b353d70CB6D15Fa47745dB3c2;
        address Fluxin = 0x98825D67bE17aaec25Ef1279b0AFAc1e96a309a0;
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
