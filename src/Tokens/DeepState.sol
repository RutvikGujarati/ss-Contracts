// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Deepstate {
    /* ==============================
        EVENTS 
    ============================== */
    event TokenPurchase(
        address indexed buyer,
        uint256 ethInjected,
        uint256 tokensMinted
    );
    event TokenSale(
        address indexed seller,
        uint256 tokensBurned,
        uint256 ethReceived
    );
    event TreasuryVesting(
        uint256 vestedTokens,
        uint256 ethValue,
        uint256 timestamp
    );

    /* ==============================
        CONSTANTS 
    ============================== */
    uint8 private constant DIVIDEND_FEE = 10; // 10% transaction tax
    uint256 private constant MAGNITUDE = 2 ** 64;
    uint256 private constant INITIAL_TOKEN_PRICE = 0.0000001 ether;
    uint256 private constant PRICE_INCREMENT = 0.00000001 ether;
    uint256 private constant TREASURY_CAP = 1 ether; // Max 1 ETH initial purchase
    uint256 private constant VESTING_RATE = 101095890000000; // 0.010109589% daily (3.69% annual)

    /* ==============================
        STATE VARIABLES 
    ============================== */
    address public treasuryWallet;
    uint256 private treasuryLocked;
    uint256 private lastVestingUpdate;
    bool public earlyAccessActive = true;

    string public name = "Deep";
    string public symbol = "DEEP";
    uint256 private tokenSupply;
    uint256 private profitPerShare;
    mapping(address => uint256) private tokenBalance;
    mapping(address => int256) private payouts;

    /* ==============================
        CONSTRUCTOR 
    ============================== */
    constructor(address _treasury) {
        treasuryWallet = _treasury;
        lastVestingUpdate = block.timestamp;
    }

    /* ==============================
        MODIFIERS 
    ============================== */
    modifier onlyTokenHolders() {
        require(myTokens() > 0, "Must hold tokens to perform this action");
        _;
    }

    modifier onlyProfitHolders() {
        require(myDividends() > 0, "Must have dividends available");
        _;
    }

    modifier duringEarlyAccess() {
        require(earlyAccessActive, "Early access phase ended");
        _;
    }

    /* ==============================
        PRIMARY FUNCTIONS 
    ============================== */
    function buy() public payable {
        if (earlyAccessActive) {
            require(
                msg.sender == treasuryWallet,
                "Early access restricted to treasury"
            );
            require(msg.value <= TREASURY_CAP, "Exceeds treasury allocation");
            earlyAccessActive = false;
        }
        purchaseTokens(msg.value);
    }

    function sell(uint256 _tokens) external onlyTokenHolders {
        updateVesting();
        require(_tokens <= tokenBalance[msg.sender], "Insufficient balance");

        uint256 ethValue = tokensToEthereum(_tokens);
        uint256 fee = ethValue / DIVIDEND_FEE;
        uint256 taxedValue = ethValue - fee;

        tokenSupply -= _tokens;
        tokenBalance[msg.sender] -= _tokens;

        profitPerShare += (fee * MAGNITUDE) / tokenSupply;
        payable(msg.sender).transfer(taxedValue);

        emit TokenSale(msg.sender, _tokens, taxedValue);
    }

    function withdraw() external onlyProfitHolders {
        updateVesting();
        uint256 dividends = myDividends();
        payouts[msg.sender] += int256(dividends * MAGNITUDE);
        payable(msg.sender).transfer(dividends);
    }

    /* ==============================
        TREASURY FUNCTIONS 
    ============================== */
    function updateVesting() internal {
        uint256 elapsed = block.timestamp - lastVestingUpdate;
        if (elapsed < 1 days || treasuryLocked == 0) return;

        uint256 daysPassed = elapsed / 1 days;
        uint256 vested = (treasuryLocked * VESTING_RATE * daysPassed) / 1e18;
        vested = vested > treasuryLocked ? treasuryLocked : vested;

        uint256 ethEquivalent = tokensToEthereum(vested);
        uint256 fee = ethEquivalent / DIVIDEND_FEE;
        uint256 dividend = ethEquivalent - fee;

        treasuryLocked -= vested;
        lastVestingUpdate += daysPassed * 1 days;

        profitPerShare += (dividend * MAGNITUDE) / tokenSupply;
        emit TreasuryVesting(vested, dividend, block.timestamp);
    }

    /* ==============================
        VIEW FUNCTIONS 
    ============================== */
    function myTokens() public view returns (uint256) {
        return tokenBalance[msg.sender];
    }

    function myDividends() public view returns (uint256) {
        int256 value = int256(profitPerShare * tokenBalance[msg.sender]) -
            payouts[msg.sender];
        return value < 0 ? 0 : uint256(value) / MAGNITUDE;
    }

    function treasuryLockedBalance() public view returns (uint256) {
        return treasuryLocked;
    }

    /* ==============================
        INTERNAL LOGIC 
    ============================== */
    function purchaseTokens(uint256 _eth) internal {
        updateVesting();

        uint256 fee = _eth / DIVIDEND_FEE;
        uint256 investment = _eth - fee;
        uint256 tokens = ethereumToTokens(investment);

        if (msg.sender == treasuryWallet && !earlyAccessActive) {
            treasuryLocked += tokens;
        }

        tokenSupply += tokens;
        tokenBalance[msg.sender] += tokens;

        profitPerShare += (fee * MAGNITUDE) / tokenSupply;
        emit TokenPurchase(msg.sender, _eth, tokens);
    }

    function ethereumToTokens(uint256 _eth) internal pure returns (uint256) {
        return _eth / INITIAL_TOKEN_PRICE;
    }

    function tokensToEthereum(uint256 _tokens) internal pure returns (uint256) {
        return _tokens * INITIAL_TOKEN_PRICE;
    }
    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }
}
