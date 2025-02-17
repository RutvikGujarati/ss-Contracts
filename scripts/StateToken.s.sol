// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MainTokens/StateToken.sol";

contract DeployState is Script {
    function run() external {
        address davToken = 0xCf7A569E5f90ae07402693288Bdd34fbA646d80a;
        address governance = 0xB1bD9F3B5F64dE482485A41c84ea4a90DAc5F98e;

        vm.startBroadcast();

        STATE_Token_V1_1_Ratio_Swapping state = new STATE_Token_V1_1_Ratio_Swapping(davToken, "pSTATE", "pSTATE", governance);

        console.log("state deployed at:", address(state));

        vm.stopBroadcast();
    }
}
