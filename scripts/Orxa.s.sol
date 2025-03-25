// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Tokens/Valir.sol";

contract DeployValir is Script {
    function run() external {
        address davToken = 0x78f8Aba822259d8B5E4E381bc536816874Aa5D86;
        address governance = 0xB511110f312a4C6C4a240b2fE94de55D600Df7a9;
        vm.startBroadcast();

        Valir valir = new Valir(davToken, "Valir", "Valir", governance);

        console.log("rievaollar deployed at:", address(valir));

        vm.stopBroadcast();
    }
}
