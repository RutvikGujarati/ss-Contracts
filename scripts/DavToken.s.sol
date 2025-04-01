// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Decentralized_Autonomous_Vaults_DAV_V1_1} from "../src/MainTokens/sDavToken.sol";

contract ScriptDAV is Script {
    function run() external {
        vm.startBroadcast();

        address liquidity = 0xB511110f312a4C6C4a240b2fE94de55D600Df7a9;
        address DAVWallet = 0x3902BedF016a9c5fdEFDfB035D85Cb92140ACE95;
        address Governanace = 0xB511110f312a4C6C4a240b2fE94de55D600Df7a9;

        Decentralized_Autonomous_Vaults_DAV_V1_1 dav = new Decentralized_Autonomous_Vaults_DAV_V1_1(
                liquidity,
                DAVWallet,
                Governanace,
                "sDAV",
                "sDAV"
            );

        console.log("Contract deployed at:", address(dav));

        vm.stopBroadcast();
    }
}
