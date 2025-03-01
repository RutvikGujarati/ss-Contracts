// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ratioPrice} from "../src/tokens/ratioPrice.sol";

contract scriptratioPrice is Script {
    function run() external {
        vm.startBroadcast();
        // address pairAddress = 0x361aFa3F5EF839bED6071c9F0c225b078eB8089a; // for orxa
        // address orxaToken = 0x6F01eEc1111748B66f735944b18b0EB2835aE201;
        // address pstateToken = 0x63CC0B2CA22b260c7FD68EBBaDEc2275689A3969;

        ratioPrice ratio = new ratioPrice();

        console.log("contract deployed at", address(ratio));
        vm.stopBroadcast();
    }
}
