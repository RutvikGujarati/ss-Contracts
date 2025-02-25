// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Tokens/Orxa.sol";

contract DeployOrxa is Script {
    function run() external {
        address davToken = 0x61b54518A66871ad23cA56b25AcC24F28Acd7614;
        address governance = 0xB511110f312a4C6C4a240b2fE94de55D600Df7a9;
        vm.startBroadcast();

        Orxa orxa = new Orxa(davToken, "Orxa", "Orxa", governance);

        console.log("Orxa deployed at:", address(orxa));

        vm.stopBroadcast();
    }
}