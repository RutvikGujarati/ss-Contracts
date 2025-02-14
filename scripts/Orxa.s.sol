// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Tokens/Fluxin.sol";

contract DeployFluxin is Script {
    function run() external {
        //  address deployer = 0x14093F94E3D9E59D1519A9ca6aA207f88005918c;
        address davToken = 0x36b6AeE4E4b68d4f48EC5d96512d325A7B07a79D;
        address governance = 0x3Bdbb84B90aBAf52814aAB54B9622408F2dCA483;

        vm.startBroadcast();

        Fluxin fluxin = new Fluxin(davToken, "FluxinToken", "FLX", governance);

        console.log("Fluxin deployed at:", address(fluxin));

        vm.stopBroadcast();
    }
}
//0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
//testnet : 0xAD21D14432421a49a180a6De09dA2D6092436210