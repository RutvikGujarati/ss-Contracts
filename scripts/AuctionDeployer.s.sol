//SPDX-Licence-Identifier : MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Ratio_Swapping_Auctions_V1_1} from "../src/AuctionSwap/DomusSwap.sol";
contract AuctionSwapDeploy is Script {
    function run() external {
        address davToken = 0x78f8Aba822259d8B5E4E381bc536816874Aa5D86;
        address StatToken = 0xc359f56c63A8117C83AbE84F4BB78d9eF124b567;
        address Domus = 0x82627374E1fe45A6918f21e52B4776E3B8c6420b;
        address governance = 0xB511110f312a4C6C4a240b2fE94de55D600Df7a9;

        address pairAddress = 0x7019eE4173420EE652eDC9A26bFfC91469C753db;
        vm.startBroadcast();

        Ratio_Swapping_Auctions_V1_1 swap = new Ratio_Swapping_Auctions_V1_1(
            StatToken,
            davToken,
            Domus,
            governance,
            pairAddress
        );
        console.log("Swap deployed at:", address(swap));
        vm.stopBroadcast();
    }
}
