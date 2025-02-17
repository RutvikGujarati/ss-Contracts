// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Decentralized_Autonomous_Vaults_DAV_V1_1} from "../src/MainTokens/DavToken.sol";

contract ScriptDAV is Script {
    function run() external {
        vm.startBroadcast();

        address liquidity = 0xB1bD9F3B5F64dE482485A41c84ea4a90DAc5F98e;
        address DAVWallet = 0xB1bD9F3B5F64dE482485A41c84ea4a90DAc5F98e;
        address Governanace = 0xB1bD9F3B5F64dE482485A41c84ea4a90DAc5F98e;

        Decentralized_Autonomous_Vaults_DAV_V1_1 dav = new Decentralized_Autonomous_Vaults_DAV_V1_1(
                liquidity,
                DAVWallet,
                Governanace,
                "pDAV",
                "pDAV"
            );

        console.log("Contract deployed at:", address(dav));

        vm.stopBroadcast();
    }
}
