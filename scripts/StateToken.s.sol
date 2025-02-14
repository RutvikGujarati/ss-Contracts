// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MainTokens/StateToken.sol";

contract DeployState is Script {
    function run() external {
        address davToken = 0xE781A1F1B7971cCB51d600461Fcde69605D9A164;
        address governance = 0xB1bD9F3B5F64dE482485A41c84ea4a90DAc5F98e;

        vm.startBroadcast();

        STATE_Token_V1_1_Ratio_Swapping state = new STATE_Token_V1_1_Ratio_Swapping(davToken, "pSTATE", "pSTATE", governance);

        console.log("state deployed at:", address(state));

        vm.stopBroadcast();
    }
}
//0xa513E6E4b8f2a923D98304ec87F64353C4D5C853
//testnet: 0xAd2FC6b683AFf4AF9fC1068355AA6B9A4b749781