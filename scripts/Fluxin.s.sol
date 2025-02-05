// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Tokens/Fluxin.sol";

contract DeployFluxin is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        address davToken = vm.envAddress("DAV_TOKEN_ADDRESS");
        address governance = vm.envAddress("GOVERNANCE_ADDRESS");

        vm.startBroadcast();

        Fluxin fluxin = new Fluxin(davToken, "FluxinToken", "FLX", governance);

        console.log("Fluxin deployed at:", address(fluxin));

        vm.stopBroadcast();
    }
}
//0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9