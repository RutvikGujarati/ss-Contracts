// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MainTokens/StateToken.sol";

contract DeployState is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        address davToken = vm.envAddress("DAV_TOKEN_ADDRESS");
        address governance = vm.envAddress("GOVERNANCE_ADDRESS");

        vm.startBroadcast();

        STATE_Token_V1_0_Ratio_Swapping state = new STATE_Token_V1_0_Ratio_Swapping(davToken, "StateToken", "State", governance);

        console.log("state deployed at:", address(state));

        vm.stopBroadcast();
    }
}
//0xa513E6E4b8f2a923D98304ec87F64353C4D5C853