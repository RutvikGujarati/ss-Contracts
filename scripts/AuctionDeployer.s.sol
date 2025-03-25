//SPDX-Licence-Identifier : MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Ratio_Swapping_Auctions_V1_1} from "../src/AuctionSwap/ValirSwap.sol";
contract AuctionSwapDeploy is Script {
    function run() external {
        address davToken = 0x78f8Aba822259d8B5E4E381bc536816874Aa5D86;
        address StatToken = 0xc359f56c63A8117C83AbE84F4BB78d9eF124b567;
        address valir = 0x61fB10Ac14b5fe7499A6858A9cF0d80cc1d2fD75;
        address governance = 0xB511110f312a4C6C4a240b2fE94de55D600Df7a9;

        address pairAddress = 0x1d3796D78FfDca93B501Ff442Aba4123BB334Cd1;

        vm.startBroadcast();

        Ratio_Swapping_Auctions_V1_1 swap = new Ratio_Swapping_Auctions_V1_1(
            StatToken,
            davToken,
            valir,
            governance,
            pairAddress
        );
        console.log("Swap deployed at:", address(swap));
        vm.stopBroadcast();
    }
}
