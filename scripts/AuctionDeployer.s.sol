//SPDX-Licence-Identifier : MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Ratio_Swapping_Auctions_V1_1} from "../src/AuctionSwap/OrxaSwap.sol";
contract AuctionSwapDeploy is Script {
    function run() external {
        address davToken = 0x78f8Aba822259d8B5E4E381bc536816874Aa5D86;
        address StatToken = 0xc359f56c63A8117C83AbE84F4BB78d9eF124b567;
        address orxa = 0xfe4EC02E6Fe069d90D4a721313f22d6461ec5A06;
        address governance = 0xB511110f312a4C6C4a240b2fE94de55D600Df7a9;
		
        address pairAddress = 0x79405385904b48112e90dbc4849B00eED4202BB8; // for orxa
        address orxaToken = 0xfe4EC02E6Fe069d90D4a721313f22d6461ec5A06;
        address pstateToken = 0xc359f56c63A8117C83AbE84F4BB78d9eF124b567;
        vm.startBroadcast();

        Ratio_Swapping_Auctions_V1_1 swap = new Ratio_Swapping_Auctions_V1_1(
            StatToken,
            davToken,
            orxa,
            governance,
            pstateToken,
            orxaToken,
            pairAddress
        );
        console.log("Swap deployed at:", address(swap));
        vm.stopBroadcast();
    }
}
