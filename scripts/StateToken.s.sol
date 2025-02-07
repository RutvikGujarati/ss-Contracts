// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MainTokens/StateToken.sol";

contract DeployState is Script {
    function run() external {
        address deployer = 0x14093F94E3D9E59D1519A9ca6aA207f88005918c;
        address davToken = 0x36b6AeE4E4b68d4f48EC5d96512d325A7B07a79D;
        address governance = 0x3Bdbb84B90aBAf52814aAB54B9622408F2dCA483;

        vm.startBroadcast();

        STATE_Token_V1_0_Ratio_Swapping state = new STATE_Token_V1_0_Ratio_Swapping(davToken, "StateToken", "State", governance);

        console.log("state deployed at:", address(state));

        vm.stopBroadcast();
    }
}
//0xa513E6E4b8f2a923D98304ec87F64353C4D5C853
//testnet: 0xAd2FC6b683AFf4AF9fC1068355AA6B9A4b749781