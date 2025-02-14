// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Decentralized_Autonomous_Vaults_DAV_V1_1} from "../MainTokens/DavToken.sol";

contract Orxa is ERC20, Ownable(msg.sender), ReentrancyGuard {
    using SafeERC20 for ERC20;

    Decentralized_Autonomous_Vaults_DAV_V1_1 public davToken;
    uint256 public MAX_SUPPLY = 1000000000000 ether;
    uint256 public REWARD_DECAY_START;
    uint256 public DECAY_INTERVAL = 5 days;
    uint256 public constant DECAY_STEP = 1; // 1% per interval
    uint256 private constant PRECISION = 1e18;

    mapping(address => uint256) public userBaseReward;
    mapping(address => uint256) public userRewardAmount;
    mapping(address => uint256) public lastDavMintTime;
    mapping(address => uint256) public lastDavHolding;
    mapping(address => uint256) public mintDecayPercentage;
    mapping(address => uint256) public cumulativeMintableHoldings;
    address public governanceAddress;

    event RewardDistributed(address indexed user, uint256 amount);
    mapping(address => bool) public isAuthorized;

    modifier onlyGovernance() {
        require(
            isAuthorized[msg.sender],
            "Orxa: You are not authorized to perform this action"
        );
        _;
    }

    constructor(
        address _davTokenAddress,
        string memory name,
        string memory symbol,
        address Governance
    ) ERC20(name, symbol) {
        require(
            _davTokenAddress != address(0),
            "Orxa: Invalid DAV token address"
        );
        require(
            Governance != address(0),
            "Orxa: Governance address cannot be zero"
        );

        davToken = Decentralized_Autonomous_Vaults_DAV_V1_1(
            payable(_davTokenAddress)
        );
        governanceAddress = Governance;
        REWARD_DECAY_START = block.timestamp;
        isAuthorized[Governance] = true;
    }

    /**
     * @dev Change MAX_SUPPLY, restricted to governance.
     */
    function changeMAXSupply(uint256 newMaxSupply) external onlyGovernance {
        require(newMaxSupply > 0, "Orxa: Max supply exceeds limit");
        MAX_SUPPLY = newMaxSupply;
    }

    function changeTimeStamp(uint256 newTimeStamp) external onlyGovernance {
        require(
            newTimeStamp > block.timestamp,
            "Orxa: New timestamp must be in the future"
        );
        require(
            newTimeStamp != REWARD_DECAY_START,
            "Orxa: New timestamp must be different from the current"
        );
        REWARD_DECAY_START = newTimeStamp;
    }

    function changeInterval(uint256 newInterval) external onlyGovernance {
        require(newInterval > 0, "Orxa: Interval must be greater than zero");
        require(
            newInterval != DECAY_INTERVAL,
            "Orxa: New interval must be different from the current"
        );
        DECAY_INTERVAL = newInterval;
    }

    function changeDavToken(address newDav) external onlyGovernance {
        require(newDav != address(0), "Orxa: Invalid DAV token address");
        require(
            newDav != address(davToken),
            "Orxa: New DAV token must be different from the current"
        );

        // Update the DAV token reference
        davToken = Decentralized_Autonomous_Vaults_DAV_V1_1(payable(newDav));
    }

    /**
     * @dev Calculate decayed reward based on decay percentage.
     */
    function calculateDecayedReward(uint256 baseReward, uint256 decayPercent)
        public
        pure
        returns (uint256)
    {
        if (decayPercent >= 100) {
            return 0;
        }
        uint256 decayFactor = 100 * PRECISION - (decayPercent * PRECISION);
        return (baseReward * decayFactor) / (100 * PRECISION);
    }

    function mintAdditionalTOkens(uint256 amount)
        public
        onlyGovernance
        nonReentrant
    {
        require(amount > 0, "mint amount must be greater than zero");
        require(governanceAddress != address(0), "address should not be zero");
        _mint(governanceAddress, amount);
    }

    /**
     * @dev Distribute reward for a user's DAV holdings.
     */
    function distributeReward(address user) external nonReentrant {
        // **Checks**
        require(user != address(0), "Orxa: Invalid user address");

        uint256 currentDavHolding = davToken.balanceOf(user);
        uint256 lastHolding = lastDavHolding[user];
        uint256 newDavMinted = currentDavHolding > lastHolding
            ? currentDavHolding - lastHolding
            : 0;
        require(newDavMinted > 0, "Orxa: No new DAV minted");

        uint256 mintTimestamp = davToken.viewLastMintTimeStamp(user);

        // **Effects**
        uint256 decayAtMint = getDecayPercentageAtTime(mintTimestamp);
        uint256 baseReward = calculateBaseReward(newDavMinted);
        uint256 decayedReward = calculateDecayedReward(baseReward, decayAtMint);

        userBaseReward[user] = baseReward;
        userRewardAmount[user] += decayedReward;
        cumulativeMintableHoldings[user] += newDavMinted;

        lastDavHolding[user] = currentDavHolding;
        lastDavMintTime[user] = mintTimestamp;
        mintDecayPercentage[user] = decayAtMint;

        emit RewardDistributed(user, decayedReward);
        // **No Interactions**
    }

    function mintReward() external nonReentrant {
        // **Checks**
        uint256 reward = userRewardAmount[msg.sender];
        require(reward > 0, "Orxa: No reward to mint");

        uint256 mintableHoldings = cumulativeMintableHoldings[msg.sender];
        require(
            mintableHoldings > 0,
            "Orxa: No new holdings to calculate minting"
        );

        uint256 amountToMint = ((150000000 * 1e18) * mintableHoldings) /
            (10**decimals());
        require(
            totalSupply() + reward + amountToMint <= MAX_SUPPLY,
            "Orxa: Max supply exceeded"
        );

        // **Effects**
        userRewardAmount[msg.sender] = 0;
        cumulativeMintableHoldings[msg.sender] = 0;

        // **Interactions**
        _mint(msg.sender, reward);
        _mint(address(this), amountToMint);
    }

    /**
     * @dev Calculate the base reward for a given DAV amount.
     */
    function calculateBaseReward(uint256 davAmount)
        public
        view
        returns (uint256)
    {
        // Multiply first to retain precision, then divide
        return (davAmount * (MAX_SUPPLY * 10)) / (5000000 * 1000 * 1e17);
    }
    function getMax_supply()public view returns(uint256){
        return MAX_SUPPLY;
    }
    /**
     * @dev Get the decay percentage at a specific timestamp.
     */
    function getDecayPercentageAtTime(uint256 timestamp)
        public
        view
        returns (uint256)
    {
        if (timestamp < REWARD_DECAY_START) return 0;

        uint256 elapsed = timestamp - REWARD_DECAY_START;
        uint256 decayIntervals = elapsed / DECAY_INTERVAL;
        uint256 totalDecayPercentage = decayIntervals * DECAY_STEP;

        return totalDecayPercentage > 100 ? 100 : totalDecayPercentage;
    }

    /**
     * @dev Get the current decay percentage based on the block timestamp.
     */
    function getCurrentDecayPercentage() public view returns (uint256) {
        return getDecayPercentageAtTime(block.timestamp);
    }

    function transferToken(uint256 amount)
        external
        onlyGovernance
        nonReentrant
    {
        require(amount > 0, "Transfer amount must be greater than zero");
        require(
            balanceOf(address(this)) >= amount,
            "Insufficient contract balance"
        );
        require(governanceAddress != address(0), "Invalid governance address");

        ERC20(address(this)).safeTransfer(governanceAddress, amount);
    }

    /**
     * @dev View reward details for a user.
     */
    function viewRewardDetails(address user)
        external
        view
        returns (
            uint256 baseReward,
            uint256 currentReward,
            uint256 lastMintTimestamp,
            uint256 decayAtMint
        )
    {
        baseReward = userBaseReward[user];
        currentReward = userRewardAmount[user];
        lastMintTimestamp = lastDavMintTime[user];
        decayAtMint = mintDecayPercentage[user];
    }
}
