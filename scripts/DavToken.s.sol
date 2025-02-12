// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Decentralized_Autonomous_Vaults_DAV_V1_1} from "../src/MainTokens/DavToken.sol";

contract ScriptDAV is Script {
    function run() external {
        vm.startBroadcast();

        address liquidity = 0x3Bdbb84B90aBAf52814aAB54B9622408F2dCA483;
        address DAVWallet = 0x3Bdbb84B90aBAf52814aAB54B9622408F2dCA483;
        address Governanace = 0x3Bdbb84B90aBAf52814aAB54B9622408F2dCA483;

        Decentralized_Autonomous_Vaults_DAV_V1_1 dav = new Decentralized_Autonomous_Vaults_DAV_V1_1(
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
//testnet : 0x36b6AeE4E4b68d4f48EC5d96512d325A7B07a79D