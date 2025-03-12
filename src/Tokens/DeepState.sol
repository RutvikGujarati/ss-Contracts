// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title Deepstate Token
 * @notice ERC20 token with bonding curve pricing, dividend distribution, and treasury vesting
 */
contract Deepstate is ERC20 {
    using Address for address payable;

    uint256 public constant INITIAL_PRICE = 0.0000001 ether;
    uint256 public constant PRICE_INCREMENT = 0.00000001 ether;
    uint256 public constant DIVIDEND_FEE = 10; // 10%
    uint256 private constant MAGNITUDE = 2 ** 128;
    uint256 private constant DAILY_VESTING = 10109589; // 0.010109589% daily (3.69% annual)

    address public immutable treasury;
    uint256 public treasuryLocked;
    uint256 public lastVestingUpdate;
    bool public earlyAccessActive;

    uint256 public totalDividends;
    uint256 private profitPerShare;
    mapping(address => int256) private dividendCorrections;

    constructor(address _treasury) ERC20("Deepstate", "DEEP") {
        treasury = _treasury;
        earlyAccessActive = true;
        lastVestingUpdate = block.timestamp;
    }

    receive() external payable {
        require(msg.value > 0, "Invalid ETH amount");

        if (earlyAccessActive) {
            require(msg.sender == treasury, "Early access restricted");
            earlyAccessActive = false;
        }

        uint256 tax = (msg.value * DIVIDEND_FEE) / 100;
        uint256 investment = msg.value - tax;

        uint256 tokens = ethToTokens(investment);
        require(tokens > 0, "Insufficient ETH");

        _mint(msg.sender, tokens);
        _distributeDividends(tax);
    }

    function ethToTokens(uint256 ethAmount) public view returns (uint256) {
        uint256 price = INITIAL_PRICE +
            ((PRICE_INCREMENT * totalSupply()) / 10 ** decimals());
        return ethAmount / price;
    }

    function tokensToEth(uint256 tokenAmount) public view returns (uint256) {
        uint256 price = INITIAL_PRICE +
            ((PRICE_INCREMENT * totalSupply()) / 10 ** decimals());
        return (tokenAmount * price) / 10 ** decimals();
    }

    function sell(uint256 tokenAmount) external {
        require(balanceOf(msg.sender) >= tokenAmount, "Insufficient balance");

        uint256 ethValue = tokensToEth(tokenAmount);
        uint256 tax = (ethValue * DIVIDEND_FEE) / 100;
        uint256 payout = ethValue - tax;

        _burn(msg.sender, tokenAmount);
        _distributeDividends(tax);
        payable(msg.sender).transfer(payout);
    }

    function withdrawDividends() external {
        uint256 dividends = availableDividends(msg.sender);
        require(dividends > 0, "No dividends available");

        dividendCorrections[msg.sender] += int256(dividends * MAGNITUDE);
        payable(msg.sender).transfer(dividends);
    }

    function availableDividends(address account) public view returns (uint256) {
        return
            uint256(
                int256(profitPerShare * balanceOf(account)) -
                    dividendCorrections[account]
            ) / MAGNITUDE;
    }

    function _distributeDividends(uint256 amount) private {
        if (totalSupply() > 0) {
            profitPerShare += (amount * MAGNITUDE) / totalSupply();
            totalDividends += amount;
        }
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        dividendCorrections[sender] += int256(profitPerShare * amount);
        dividendCorrections[recipient] -= int256(profitPerShare * amount);
        super._transfer(sender, recipient, amount);
    }

    function _updateVesting() private {
        if (treasuryLocked == 0) return;

        uint256 elapsed = block.timestamp - lastVestingUpdate;
        uint256 daysPassed = elapsed / 1 days;

        if (daysPassed > 0) {
            uint256 vested = (treasuryLocked * DAILY_VESTING * daysPassed) /
                1e18;
            if (vested > treasuryLocked) {
                vested = treasuryLocked;
            }

            treasuryLocked -= vested;
            lastVestingUpdate += daysPassed * 1 days;
            uint256 ethValue = tokensToEth(vested);
            _distributeDividends(ethValue);
        }
    }
    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }
}
