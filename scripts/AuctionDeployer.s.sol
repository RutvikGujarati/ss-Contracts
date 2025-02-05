//SPDX-Licence-Identifier : MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {AuctionRatioSwapping} from "../src/AuctionSwap/FluxinSwap.sol";
contract AuctionSwapDeploy is Script {
    function run() external {
        address davToken = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;
        address StatToken = 0xa513E6E4b8f2a923D98304ec87F64353C4D5C853;
        address Fluxin = 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9;
        address governance = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

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

//fluxin Swap : 0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6