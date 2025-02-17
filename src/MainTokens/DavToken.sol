// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Decentralized_Autonomous_Vaults_DAV_V1_1 is
    ERC20,
    Ownable(msg.sender),
    ReentrancyGuard
{
    uint256 public constant MAX_SUPPLY = 5000000 ether; // 5 Million DAV Tokens
    uint256 public constant TOKEN_COST = 5000 ether;

    uint256 public mintedSupply; // Total Minted DAV Tokens
    /* liquidity and development wallets*/
    address public liquidityWallet;
    address public developmentWallet;
    /* liquidity and development funds stroing*/
    uint256 public liquidityFunds;
    uint256 public developmentFunds;

    uint256 public deployTime;
    uint256 public davIncrement = 1;
    uint256 public maxDAV = 10;
    /* liquidity and development wallets withdrawal amount*/
    uint256 public totalLiquidityAllocated;
    uint256 public totalDevelopmentAllocated;
    address[] public davHolders;
    uint256 public davHoldersCount;
    // follows for do not allow dav token transafers
    bool public transfersPaused = true;
    string public TransactionHash;
    event TokensMinted(
        address indexed user,
        uint256 davAmount,
        uint256 stateAmount
    );
    event FundsWithdrawn(string fundType, uint256 amount, uint256 timestamp);
    event RewardsClaimed(address indexed user, uint256 amount);
    event HolderAdded(address indexed holder);

    /* lastMingTimestamp will use in tokens for getting users mint time */
    mapping(address => uint256) public lastMintTimestamp;
    mapping(address => bool) private isDAVHolder;
    mapping(address => uint256) public holderRewards;
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
        deployTime = block.timestamp;
    }
    // only Governance
    modifier onlyGovernance() {
        require(
            msg.sender == governanceAddress,
            "Caller is not authorized (Governance)"
        );
        _;
    }
    /**
	 @notice Transfer not allowing of Dav tokens logic
	* @dev Ensures that user can not transfer DAV tokens to other wallet or somewhere else.
	**/
    modifier whenTransfersAllowed() {
        require(!transfersPaused, "Transfers are currently paused");
        _;
    }

    function pauseTransfers() external onlyGovernance {
        transfersPaused = true;
    }

    function resumeTransfers() external onlyGovernance {
        transfersPaused = false;
    }
    //Transferring DAV tokens is not allowed after minting

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

    function totalDavhelpByHolders()
        internal
        view
        
        returns (uint256 totalHeldByHolders)
    {
        // First loop: Calculate total balance of all DAV holders
        for (uint256 i = 0; i < davHolders.length; i++) {
            totalHeldByHolders += balanceOf(davHolders[i]);
        }
        return totalHeldByHolders;
    }

    function distributeLEVY(uint256 holderShare) internal nonReentrant {
        uint256 totalHeldByHolders = totalDavhelpByHolders();
        if (totalHeldByHolders > 0) {
            for (uint256 i = 0; i < davHolders.length; i++) {
                address holder = davHolders[i];
                uint256 holderBalance = balanceOf(holder);
                uint256 holderReward = (holderBalance * holderShare) /
                    totalHeldByHolders;
                holderRewards[holder] += holderReward;
            }
        }
    }

    /**
     * @notice Allows users to mint DAV tokens by sending PLS.
     * @dev Ensures whole-number minting, checks supply limits, and distributes funds accordingly.
     * @param amount The number of DAV tokens to mint (must be in whole numbers of 1 DAV = 1 ether).
     */
    function mintDAV(uint256 amount) external payable nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(amount % 1 ether == 0, "Amount must be a whole number");

        require(mintedSupply + amount <= MAX_SUPPLY, "Max supply reached");

        uint256 cost = (amount * TOKEN_COST) / 1 ether;
        require(msg.value == cost, "Incorrect PLS amount sent");

        mintedSupply += amount;
        lastMintTimestamp[msg.sender] = block.timestamp;

        uint256 holderShare = 0; // Initialize to zero

        // ✅ Only calculate holderShare if there are DAV holders
        if (davHolders.length > 0) {
            holderShare = (msg.value * 10) / 100;
        }

        uint256 remainingFunds = msg.value - holderShare; // Ensure no ETH is stuck

        uint256 liquidityShare = (remainingFunds * 95) / 100;
        uint256 developmentShare = remainingFunds - liquidityShare;

        liquidityFunds += liquidityShare;
        developmentFunds += developmentShare;

        if (!isDAVHolder[msg.sender]) {
            isDAVHolder[msg.sender] = true;
            davHolders.push(msg.sender);
            emit HolderAdded(msg.sender);
        }

        // ✅ Distribute only if holders exist
        if (holderShare > 0) {
            distributeLEVY(holderShare);
        }

        _mint(msg.sender, amount);
        emit TokensMinted(msg.sender, amount, msg.value);
    }

    /**
     * @notice Allows users to claim their 10% of native currency (PLS).
     */
    function claimRewards() external nonReentrant {
        uint256 reward = holderRewards[msg.sender];
        require(reward > 0, "No rewards to claim");

        holderRewards[msg.sender] = 0; // Reset before sending to prevent reentrancy

        (bool success, ) = payable(msg.sender).call{value: reward}("");
        require(success, "Transfer failed");

        emit RewardsClaimed(msg.sender, reward);
    }

    /**
     * @notice Withdraws all available liquidity funds to the designated liquidity wallet.
     * @dev Can only be called by governance and prevents reentrancy attacks.
     * Ensures there are funds available before processing the transfer.
     * Uses low-level `.call` for sending funds and checks for success.
     */
    function withdrawLiquidityFunds() external onlyGovernance nonReentrant {
        require(liquidityFunds > 0, "No liquidity funds available"); // Ensure there are funds to withdraw

        uint256 amount = liquidityFunds; // Store the amount to be withdrawn
        liquidityFunds = 0; // Reset liquidityFunds to prevent reentrancy vulnerabilities

        // Transfer the liquidity funds to the designated liquidity wallet
        (bool successLiquidity, ) = liquidityWallet.call{value: amount}("");
        require(successLiquidity, "Liquidity transfer failed");

        totalLiquidityAllocated += amount; // Track total allocated liquidity funds
        emit FundsWithdrawn("Liquidity", amount, block.timestamp);
    }

    /**
     * @notice Withdraws all available development funds to the designated development wallet.
     * @dev Can only be called by governance and prevents reentrancy attacks.
     * Ensures there are funds available before processing the transfer.
     * Uses low-level `.call` for sending funds and checks for success.
     */
    function withdrawDevelopmentFunds() external onlyGovernance nonReentrant {
        require(developmentFunds > 0, "No development funds available"); // Ensure there are funds to withdraw

        uint256 amount = developmentFunds; // Store the amount to be withdrawn
        developmentFunds = 0; // Reset developmentFunds to prevent reentrancy vulnerabilities

        // Transfer the development funds to the designated development wallet
        (bool successDevelopment, ) = developmentWallet.call{value: amount}("");
        require(successDevelopment, "Development transfer failed");

        totalDevelopmentAllocated += amount; // Track total allocated development funds
        emit FundsWithdrawn("Development", amount, block.timestamp);
    }

    // this will use in tokens for ensuring enough dav token presents at the time
    function getRequiredDAVAmount() public view returns (uint256) {
        uint256 elapsedTime = block.timestamp - deployTime;
        uint256 periods = elapsedTime / (100 days); // on mainnet it will be 100 days
        uint256 davAmount = (periods + 1) * davIncrement;
        return davAmount >= maxDAV ? maxDAV : davAmount;
    }

    function getDAVHoldings(address user) public view returns (uint256) {
        return balanceOf(user);
    }
    function getDAVHolderAt(uint256 index) external view returns (address) {
        require(index < davHolders.length, "Index out of bounds");
        return davHolders[index];
    }

    function getDAVHoldersCount() external view returns (uint256) {
        return davHolders.length;
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

    receive() external payable nonReentrant {
        revert("Direct ETH transfers not allowed");
    }
}
