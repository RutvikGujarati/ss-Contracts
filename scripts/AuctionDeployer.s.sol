//SPDX-Licence-Identifier : MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Ratio_Swapping_Auctions_V1_1} from "../src/AuctionSwap/OneDollarSwap.sol";
contract AuctionSwapDeploy is Script {
    function run() external {
        address davToken = 0x78f8Aba822259d8B5E4E381bc536816874Aa5D86;
        address StatToken = 0xc359f56c63A8117C83AbE84F4BB78d9eF124b567;
        address OneDollar = 0x4f665Ef2EF5336D26a6c06525DD812786E5614c6;
        address governance = 0xB511110f312a4C6C4a240b2fE94de55D600Df7a9;

        address pairAddress = 0x6916be7B7a36D8BC1C09EAE5487E92fF837626bB;  // for OneDollar
        vm.startBroadcast();

        Ratio_Swapping_Auctions_V1_1 swap = new Ratio_Swapping_Auctions_V1_1(
            StatToken,
            davToken,
            OneDollar,
            governance,
            pairAddress
        );
        console.log("Swap deployed at:", address(swap));
        vm.stopBroadcast();
    }
}
