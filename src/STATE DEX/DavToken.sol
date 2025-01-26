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
    uint256 public constant TOKEN_COST = 200000 ether; // 200,000 PLS per DAV

    uint256 public mintedSupply; // Total Minted DAV Tokens
    address public liquidityWallet; // Liquidity Wallet
    address public developmentWallet; // Development Wallet
    uint256 public liquidityFunds;
    uint256 public developmentFunds;

    uint256 public totalLiquidityAllocated;
    uint256 public totalDevelopmentAllocated;
    address[] public davHolders; // Array to store all DAV holders

    event TokensMinted(
        address indexed user,
        uint256 davAmount,
        uint256 stateAmount
    );
    event FundsWithdrawn(string fundType, uint256 amount, uint256 timestamp);

    mapping(address => uint256) public lastMintTimestamp; // Track the last mint timestamp for each user
    mapping(address => bool) private isDAVHolder; // Replacing davHolders array with mapping

    address private governanceAddress;

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

        uint256 cost = (amount / 1 ether) * TOKEN_COST;
        require(msg.value == cost, "Incorrect PLS amount sent");

        mintedSupply += amount;
        lastMintTimestamp[msg.sender] = block.timestamp;

        uint256 liquidityShare = (msg.value * 95) / 100;
        uint256 developmentShare = msg.value - liquidityShare;

        liquidityFunds += liquidityShare;
        developmentFunds += developmentShare;

        _mint(msg.sender, amount);

        // Add the user to the davHolders list if they are not already a holder
        if (!isDAVHolder[msg.sender]) {
            isDAVHolder[msg.sender] = true;
            davHolders.push(msg.sender);
        }

        emit TokensMinted(msg.sender, amount, msg.value);
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

    function balacneETH() public view returns (uint256) {
        return address(this).balance;
    }

    receive() external payable nonReentrant {}
}
