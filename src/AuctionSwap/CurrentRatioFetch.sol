// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPair {
    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function token0() external view returns (address);

    function token1() external view returns (address);
}

contract TokenPriceFetcher2 {
    address public pairAddress = 0x361aFa3F5EF839bED6071c9F0c225b078eB8089a; // for fluxin
    address public fluxinToken = 0x6F01eEc1111748B66f735944b18b0EB2835aE201;
    address public pstateToken = 0x63CC0B2CA22b260c7FD68EBBaDEc2275689A3969;

    function getFluxinToPstateRatio() external view returns (uint256) {
        IPair pair = IPair(pairAddress);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        address token0 = pair.token0();
        address token1 = pair.token1();

        // Ensure FLUXIN/PSTATE ratio is returned
        if (token0 == fluxinToken && token1 == pstateToken) {
            return (uint256(reserve1) * 1e18) / uint256(reserve0); // FLUXIN → PSTATE
        } else if (token0 == pstateToken && token1 == fluxinToken) {
            return (uint256(reserve0) * 1e18) / uint256(reserve1); // FLUXIN → PSTATE
        } else {
            revert("Invalid pair, does not match FLUXIN/PSTATE");
        }
    }
}
