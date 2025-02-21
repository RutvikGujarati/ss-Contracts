// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Decentralized_Autonomous_Vaults_DAV_V1_1} from "./DavToken.sol";

contract STATE_Token_V1_1_Ratio_Swapping is
    ERC20,
    Ownable(msg.sender),
    ReentrancyGuard
{
    using SafeERC20 for ERC20;

    Decentralized_Autonomous_Vaults_DAV_V1_1 public davToken;
    uint256 public MAX_SUPPLY = 999000000000000 ether;
    uint256 public REWARD_DECAY_START;
    uint256 public DECAY_INTERVAL = 10 days;
    uint256 public constant DECAY_STEP = 1; // 1% per interval
    uint256 private constant PRECISION = 1e18;
    uint256 private constant COOLDOWN_PERIOD = 24 hours;
    uint256 ExtraMintAllowed;
    uint256 public constant multiplier = 10000000;
    mapping(address => uint256) public userBaseReward;
    mapping(address => uint256) public userRewardAmount;
    mapping(address => uint256) public lastDavMintTime;
    mapping(address => uint256) public lastDavHolding;
    mapping(address => uint256) public mintDecayPercentage;
    mapping(address => uint256) public cumulativeMintableHoldings;
    mapping(address => uint256) private lastTransferTimestamp;
    address public governanceAddress;

    event RewardDistributed(address indexed user, uint256 amount);
    mapping(address => bool) public isAuthorized;

    modifier onlyGovernance() {
        require(
            isAuthorized[msg.sender],
            "StateToken: You are not authorized to perform this action"
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
            "StateToken: Invalid DAV token address"
        );
        require(
            Governance != address(0),
            "StateToken: Governance address cannot be zero"
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
        require(
            newMaxSupply > 0,
            "StateToken: Max supply must be greater than zero"
        );
        MAX_SUPPLY = newMaxSupply;
    }

    function changeInterval(uint256 newInterval) external onlyGovernance {
        require(
            newInterval > 0,
            "StateToken: Interval must be greater than zero"
        );
        require(
            newInterval != DECAY_INTERVAL,
            "StateToken: New interval must be different from the current"
        );
        DECAY_INTERVAL = newInterval;
    }

    function changeDavToken(address newDav) external onlyGovernance {
        require(newDav != address(0), "StateToken: Invalid DAV token address");
        require(
            newDav != address(davToken),
            "StateToken: New DAV token must be different from the current"
        );
        davToken = Decentralized_Autonomous_Vaults_DAV_V1_1(payable(newDav));
    }

    /**
     * @dev Calculate decayed reward based on decay percentage.
     */
    function calculateDecayedReward(
        uint256 baseReward,
        uint256 decayPercent
    ) public pure returns (uint256) {
        if (decayPercent >= 100) {
            return 0;
        }
        uint256 decayFactor = 100 * PRECISION - (decayPercent * PRECISION);
        return (baseReward * decayFactor) / (100 * PRECISION);
    }

    function mintAdditionalTOkens(
        uint256 amount
    ) public onlyGovernance nonReentrant {
        require(amount > 0, "mint amount must be greater than zero");
        require(governanceAddress != address(0), "address should not be zero");
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds MAX_SUPPLY");
        _mint(governanceAddress, amount);
    }

    /**
     * @dev Distribute reward for a user's DAV holdings.
     */
    function distributeReward(address user) external nonReentrant {
        // **Checks**
        require(user != address(0), "StateToken: Invalid user address");
        uint256 currentDavHolding = davToken.getUserMintedAmount(user);
        require(msg.sender == user, "Unauthorized");

        uint256 lastHolding = lastDavHolding[user];
        uint256 newDavMinted = currentDavHolding > lastHolding
            ? currentDavHolding - lastHolding
            : 0;
        require(newDavMinted > 0, "StateToken: No new DAV minted");

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
        require(reward > 0, "StateToken: No reward to mint");

        uint256 mintableHoldings = cumulativeMintableHoldings[msg.sender];
        require(
            mintableHoldings > 0,
            "StateToken: No new holdings to calculate minting"
        );

        uint256 amountToMint = mintableHoldings * multiplier;

        require(
            totalSupply() + reward + amountToMint <= MAX_SUPPLY,
            "StateToken: Max supply exceeded"
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
    function calculateBaseReward(
        uint256 davAmount
    ) public view returns (uint256) {
        uint256 supply_p = MAX_SUPPLY * 10;
        uint256 denominator = 5e9; // Equivalent to 5000000 * 1000
        uint256 precisionFactor = 1e18; // Scaling factor to maintain precision

        uint256 baseReward;

        if (davAmount > type(uint256).max / supply_p) {
            // If `davAmount * supply_p` risks overflow, scale first before division
            baseReward =
                ((davAmount * precisionFactor) / denominator) *
                (supply_p / precisionFactor);
        } else {
            // Maintain precision while avoiding overflow
            baseReward =
                (davAmount * supply_p) /
                (denominator * precisionFactor);
        }

        return baseReward;
    }

    /**
     * @dev Get the decay percentage at a specific timestamp.
     */
    function getDecayPercentageAtTime(
        uint256 timestamp
    ) public view returns (uint256) {
        if (timestamp < REWARD_DECAY_START) return 0;

        uint256 elapsed = timestamp - REWARD_DECAY_START;
        uint256 decayIntervals = elapsed / DECAY_INTERVAL;
        uint256 totalDecayPercentage = decayIntervals * DECAY_STEP;

        return totalDecayPercentage > 100 ? 100 : totalDecayPercentage;
    }

    //updating Governanace if old is deprecated
    function updateGovernance(address newGov) external onlyGovernance {
        require(newGov != address(0), "Invalid address");
        isAuthorized[governanceAddress] = false;
        governanceAddress = newGov;
        isAuthorized[newGov] = true;
    }
    /**
     * @dev Get the current decay percentage based on the block timestamp.
     */
    function getCurrentDecayPercentage() public view returns (uint256) {
        return getDecayPercentageAtTime(block.timestamp);
    }

    /* Governanace able to transfer tokens for providing liquidity */

    function transferToken(
        uint256 amount
    ) external onlyGovernance nonReentrant {
        require(amount > 0, "Transfer amount must be greater than zero");
        require(
            balanceOf(address(this)) >= amount,
            "Insufficient contract balance"
        );
        require(governanceAddress != address(0), "Invalid governance address");
        require(
            amount <= balanceOf(address(this)) / 10,
            "Transfer amount exceeds 10% of contract balance"
        );
        require(
            block.timestamp >=
                lastTransferTimestamp[msg.sender] + COOLDOWN_PERIOD,
            "Transfer cooldown period not yet passed"
        );

        lastTransferTimestamp[msg.sender] = block.timestamp;
        ERC20(address(this)).safeTransfer(governanceAddress, amount);
    }

    /**
     * @dev View reward details for a user.
     */
    function viewRewardDetails(
        address user
    )
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
