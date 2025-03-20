// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Tokens/Currus.sol";

contract DeployCurrus is Script {
    function run() external {
        address davToken = 0x78f8Aba822259d8B5E4E381bc536816874Aa5D86;
        address governance = 0xB511110f312a4C6C4a240b2fE94de55D600Df7a9;
        vm.startBroadcast();

        Currus currus = new Currus(davToken, "Currus", "Currus", governance);

        console.log("rievaollar deployed at:", address(currus));

        vm.stopBroadcast();
    }
}
