// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPair {
    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function token0() external view returns (address);

    function token1() external view returns (address);
}

contract rp {
    address pairAddress;
    address orxaToken;
    address pstateToken;
    constructor(address _pair, address _orxa, address _pstate) {
        pairAddress = _pair;
        orxaToken = _orxa;
        pstateToken = _pstate;
    }
    function getRatioPrice() public view returns (uint256) {
        IPair pair = IPair(pairAddress);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        address token0 = pair.token0();
        address token1 = pair.token1();

        require(reserve0 > 0 && reserve1 > 0, "Invalid reserves"); // ✅ Prevents division by zero

        uint256 ratio;
        if (token0 == orxaToken && token1 == pstateToken) {
            ratio = (uint256(reserve1) * 1e18) / uint256(reserve0);
        } else if (token0 == pstateToken && token1 == orxaToken) {
            ratio = (uint256(reserve0) * 1e18) / uint256(reserve1);
        } else {
            revert("Invalid pair, does not match orxa/PSTATE");
        }

        return ratio < 1e18 ? 1e18 : ratio; // Ensure ratio is at least 1
    }
}
