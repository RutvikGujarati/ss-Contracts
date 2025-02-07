//SPDX-Licence-Identifier : MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {AuctionRatioSwapping} from "../src/AuctionSwap/FluxinSwap.sol";
contract AuctionSwapDeploy is Script {
    function run() external {
        address davToken = 0x1a44c22FB260cB1fF082501299c588e9078346a2;
        address StatToken = 0x41b15BeA9cdfA72c9D715E59a255291337A72A60;
        address Fluxin = 0xbD4828Bb883D591fe6b18c269Da01388f5CE8700;
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

//fluxin Swap : 0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6

//testnet: 0x97757d5CDC5BF16f5358D69F51277B44Ef32F85c

//0x706be3785701d282C57D261DdC4Cc152282c9873