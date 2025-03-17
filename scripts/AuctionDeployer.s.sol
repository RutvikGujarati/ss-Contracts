//SPDX-Licence-Identifier : MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Ratio_Swapping_Auctions_V1_1} from "../src/AuctionSwap/TenDollarSwap.sol";
contract AuctionSwapDeploy is Script {
    function run() external {
        address davToken = 0x78f8Aba822259d8B5E4E381bc536816874Aa5D86;
        address StatToken = 0xc359f56c63A8117C83AbE84F4BB78d9eF124b567;
        address tenDollar = 0x916ed6d34d2d26b2173237BB44e0c91bdbBD7222;
        address governance = 0xB511110f312a4C6C4a240b2fE94de55D600Df7a9;

        address pairAddress = 0x86E8330Efe0dFc20Ab8f63DcF95A6a8D66f60C1D;
        vm.startBroadcast();

        Ratio_Swapping_Auctions_V1_1 swap = new Ratio_Swapping_Auctions_V1_1(
            StatToken,
            davToken,
            tenDollar,
            governance,
            pairAddress
        );
        console.log("Swap deployed at:", address(swap));
        vm.stopBroadcast();
    }
}
	