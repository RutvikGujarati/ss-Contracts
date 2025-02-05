// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Decentralized_Autonomous_Vaults_DAV_V1_0} from "../src/MainTokens/DavToken.sol";

contract ScriptDAV is Script {
    function run() external {
        vm.startBroadcast();

        address liquidity = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        address DAVWallet = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        address Governanace = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

        Decentralized_Autonomous_Vaults_DAV_V1_0 dav = new Decentralized_Autonomous_Vaults_DAV_V1_0(
                liquidity,
                DAVWallet,
                Governanace,
                "DAV",
                "DAV"
            );

        console.log("Contract deployed at:", address(dav));

        vm.stopBroadcast();
    }
}
//dav : 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0