// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MainTokens/StateToken.sol";

contract DeployState is Script {
    function run() external {
        address davToken = 0x61b54518A66871ad23cA56b25AcC24F28Acd7614;
        address governance = 0xB511110f312a4C6C4a240b2fE94de55D600Df7a9;

        vm.startBroadcast();

        STATE_Token_V1_1_Ratio_Swapping state = new STATE_Token_V1_1_Ratio_Swapping(davToken, "pSTATE", "pSTATE", governance);

        console.log("state deployed at:", address(state));

        vm.stopBroadcast();
    }
}
