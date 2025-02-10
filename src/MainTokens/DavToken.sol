// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Decentralized_Autonomous_Vaults_DAV_V1_0 is
    ERC20,
    Ownable(msg.sender),
    ReentrancyGuard
{
    uint256 public constant MAX_SUPPLY = 5000000 ether; // 5 Million DAV Tokens
    uint256 public constant TOKEN_COST = 250000 ether; // 250,000 PLS per DAV

    uint256 public mintedSupply; // Total Minted DAV Tokens
    address public liquidityWallet;
    address public developmentWallet;
    uint256 public liquidityFunds;
    uint256 public developmentFunds;
    uint256 public deployTime;
    uint256 public davIncrement = 1;
    uint256 public maxPeriod = 2000 days;
    uint256 public maxDAV = 20;
    uint256 public timer = 1 hours;
    uint256 public totalLiquidityAllocated;
    uint256 public totalDevelopmentAllocated;
    address[] public davHolders;

    event TokensMinted(
        address indexed user,
        uint256 davAmount,
        uint256 stateAmount
    );
    event FundsWithdrawn(string fundType, uint256 amount, uint256 timestamp);
    event RewardsClaimed(address indexed user, uint256 amount);

    mapping(address => uint256) public lastMintTimestamp;
    mapping(address => bool) private isDAVHolder;
    mapping(address => uint256) public holderRewards;
    address private governanceAddress;
    address private pendingGovernance;

    constructor(
        address _liquidityWallet,
        address _developmentWallet,
        address Governance,
        string memory tokenName,
        string memory TokenSymbol
    ) ERC20(tokenName, TokenSymbol) {
        require(
            _liquidityWallet != address(0) && _developmentWallet != address(0),
            "Wallet addresses cannot be zero"
        );
        liquidityWallet = _liquidityWallet;
        developmentWallet = _developmentWallet;
        governanceAddress = Governance;
        deployTime = block.timestamp;
    }

    modifier onlyGovernance() {
        require(
            msg.sender == governanceAddress,
            "Caller is not authorized (Governance)"
        );
        _;
    }

    modifier whenTransfersAllowed() {
        require(!transfersPaused, "Transfers are currently paused");
        _;
    }

    bool public transfersPaused = true;

    function pauseTransfers() external onlyGovernance {
        transfersPaused = true;
    }

    function resumeTransfers() external onlyGovernance {
        transfersPaused = false;
    }

    function transfer(
        address recipient,
        uint256 amount
    ) public override whenTransfersAllowed returns (bool) {
        return super.transfer(recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override whenTransfersAllowed returns (bool) {
        return super.transferFrom(sender, recipient, amount);
    }

    function viewLastMintTimeStamp(address user) public view returns (uint256) {
        return lastMintTimestamp[user];
    }

    uint256 public davHoldersCount;

    function mintDAV(uint256 amount) external payable nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(mintedSupply + amount <= MAX_SUPPLY, "Max supply reached");

        uint256 cost = (amount * TOKEN_COST) / 1 ether;
        require(msg.value == cost, "Incorrect PLS amount sent");

        mintedSupply += amount;
        lastMintTimestamp[msg.sender] = block.timestamp;

        uint256 holderShare = (msg.value * 10) / 100; // 10% of msg.value
        uint256 remainingFunds = msg.value - holderShare; // 90% remaining

        uint256 liquidityShare = (remainingFunds * 95) / 100;
        uint256 developmentShare = remainingFunds - liquidityShare;

        liquidityFunds += liquidityShare;
        developmentFunds += developmentShare;
        // Add the user to the davHolders list if they are not already a holder
        if (!isDAVHolder[msg.sender]) {
            isDAVHolder[msg.sender] = true;
            davHolders.push(msg.sender);
        }

        // Distribute 10% among all DAV holders
        if (davHolders.length > 0 && holderShare > 0) {
            uint256 sharePerHolder = holderShare / davHolders.length;
            for (uint256 i = 0; i < davHolders.length; i++) {
                holderRewards[davHolders[i]] += sharePerHolder;
            }
        }
        _mint(msg.sender, amount);

        emit TokensMinted(msg.sender, amount, msg.value);
    }

    function claimRewards() external nonReentrant {
        uint256 reward = holderRewards[msg.sender];
        require(reward > 0, "No rewards to claim");

        holderRewards[msg.sender] = 0; // Reset before sending to prevent reentrancy

        (bool success, ) = payable(msg.sender).call{value: reward}("");
        require(success, "Transfer failed");

        emit RewardsClaimed(msg.sender, reward);
    }

    function getDAVHolderAt(uint256 index) external view returns (address) {
        require(index < davHolders.length, "Index out of bounds");
        return davHolders[index];
    }

    function getDAVHoldersCount() external view returns (uint256) {
        return davHolders.length;
    }

    function withdrawLiquidityFunds() external onlyGovernance nonReentrant {
        require(liquidityFunds > 0, "No liquidity funds available");

        uint256 amount = liquidityFunds;
        liquidityFunds = 0;

        (bool successLiquidity, ) = liquidityWallet.call{value: amount}("");
        require(successLiquidity, "Liquidity transfer failed");

        totalLiquidityAllocated += amount;
        emit FundsWithdrawn("Liquidity", amount, block.timestamp);
    }

    function withdrawDevelopmentFunds() external onlyGovernance nonReentrant {
        require(developmentFunds > 0, "No development funds available");

        uint256 amount = developmentFunds;
        developmentFunds = 0;

        (bool successDevelopment, ) = developmentWallet.call{value: amount}("");
        require(successDevelopment, "Development transfer failed");

        totalDevelopmentAllocated += amount;
        emit FundsWithdrawn("Development", amount, block.timestamp);
    }

    function getRequiredDAVAmount() public view returns (uint256) {
        uint256 elapsedTime = block.timestamp - deployTime;
        uint256 periods = elapsedTime / (100 days);
        uint256 davAmount = (periods + 1) * davIncrement;
        return davAmount >= maxDAV ? maxDAV : davAmount;
    }

    function getDAVHoldings(address user) public view returns (uint256) {
        return balanceOf(user);
    }

    function getUserHoldingPercentage(
        address user
    ) public view returns (uint256) {
        uint256 userBalance = balanceOf(user);
        uint256 totalSupply = totalSupply();
        if (totalSupply == 0) {
            return 0;
        }
        return (userBalance * 1e18) / totalSupply; // Return percentage as a scaled value (1e18 = 100%).
    }

    receive() external payable nonReentrant {}
}
