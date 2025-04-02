//SPDX-Licence-Identifier : MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Ratio_Swapping_Auctions_V1_1} from "../src/AuctionSwap/SanitasSwap.sol";
contract AuctionSwapDeploy is Script {
    function run() external {
        address davToken = 0x78f8Aba822259d8B5E4E381bc536816874Aa5D86;
        address StatToken = 0xc359f56c63A8117C83AbE84F4BB78d9eF124b567;
        address sanitas = 0xbaB8540DeE05ba25CEc588CE5124aa50b1D7d425;
        address governance = 0xB511110f312a4C6C4a240b2fE94de55D600Df7a9;

        address pairAddress = 0x1A60E1CA8732634392eb89e68A6c50ea457872c6;

        vm.startBroadcast();

        Ratio_Swapping_Auctions_V1_1 swap = new Ratio_Swapping_Auctions_V1_1(
            StatToken,
            davToken,
            sanitas,
            governance,
            pairAddress
        );
        console.log("Swap deployed at:", address(swap));
        vm.stopBroadcast();
    }
}
