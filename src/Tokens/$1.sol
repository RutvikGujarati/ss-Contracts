// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Decentralized_Autonomous_Vaults_DAV_V1_1} from "../MainTokens/DavToken.sol";

contract $1 is ERC20, Ownable(msg.sender), ReentrancyGuard {
    using SafeERC20 for ERC20;

    Decentralized_Autonomous_Vaults_DAV_V1_1 public davToken;
    uint256 public immutable maxSupply;
    uint256 public REWARD_DECAY_START;
    uint256 public DECAY_INTERVAL = 10 days;
    uint256 public constant DECAY_STEP = 1; // 1% per interval
    uint256 private constant PRECISION = 1e18;
    uint256 private constant COOLDOWN_PERIOD = 24 hours;
    uint256 public totalAirdropMinted;
    uint256 public totalLiquidityMinted;
    mapping(address => uint256) public userBaseReward;
    mapping(address => uint256) public userRewardAmount;
    mapping(address => uint256) public lastDavMintTime;
    mapping(address => uint256) public lastDavHolding;
    mapping(address => uint256) public mintDecayPercentage;
    mapping(address => uint256) public cumulativeMintableHoldings;
    mapping(address => uint256) private lastTransferTimestamp;
    mapping(address => uint256) private lastGovernanceUpdate;
    mapping(address => uint256) private lastDAVUpdate;
    mapping(uint256  => uint256) private lastIntervalUpdate;

    address public governanceAddress;

    event RewardDistributed(address indexed user, uint256 amount);
    mapping(address => bool) public isAuthorized;

    modifier onlyGovernance() {
        require(
            isAuthorized[msg.sender],
            "1$: You are not authorized to perform this action"
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
            "1$: Invalid DAV token address"
        );
        require(
            Governance != address(0),
            "1$: Governance address cannot be zero"
        );

        davToken = Decentralized_Autonomous_Vaults_DAV_V1_1(
            payable(_davTokenAddress)
        );
        governanceAddress = Governance;
        maxSupply = 100000000 ether;
        REWARD_DECAY_START = block.timestamp;
        isAuthorized[Governance] = true;
    }

    function changeInterval(uint256 newInterval) external onlyGovernance {
        require(newInterval > 0, "1$: Interval must be greater than zero");
        require(
            newInterval != DECAY_INTERVAL,
            "1$: New interval must be different from the current"
        );
        require(
            block.timestamp >=
                lastIntervalUpdate[DECAY_INTERVAL] + COOLDOWN_PERIOD,
            "Governance update cooldown period not yet passed"
        );
        lastIntervalUpdate[newInterval] = block.timestamp;
        DECAY_INTERVAL = newInterval;
    }

    function changeDavToken(address newDav) external onlyGovernance {
        require(newDav != address(0), "1$: Invalid DAV token address");
        require(
            newDav != address(davToken),
            "1$: New DAV token must be different from the current"
        );
        require(
            block.timestamp >= lastDAVUpdate[address(davToken)] + COOLDOWN_PERIOD,
            "Governance update cooldown period not yet passed"
        );
        lastDAVUpdate[newDav] = block.timestamp;

        // Update the DAV token reference
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

        require(totalSupply() + amount <= maxSupply, "cap limit exceeded");

        _mint(governanceAddress, amount);
    }

    /**
     * @dev Distribute reward for a user's DAV holdings.
     */
    function distributeReward(address user) external nonReentrant {
        // **Checks**
        require(user != address(0), "1$: Invalid user address");
        uint256 currentDavHolding = davToken.getUserMintedAmount(user);
        require(msg.sender == user, "1$: Invalid sender");
        uint256 lastHolding = lastDavHolding[user];
        uint256 newDavMinted = currentDavHolding > lastHolding
            ? currentDavHolding - lastHolding
            : 0;
        require(newDavMinted > 0, "1$: No new DAV minted");

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

    /**
     * @notice Mints reward tokens for the user based on accumulated rewards.
     * @dev
     * - The reward amount is strictly derived from `distributeReward()`.
     * - A user can only mint what has been assigned to them in `userRewardAmount`.
     * - The total minting process follows a controlled supply mechanism.
     *
     * Tokenomics:
     * - The function mints only **10% of maxSupply** to users.
     * - An **additional 10%** is minted to the contract itself to support liquidity providing.
     * - The combined minting (user + contract) is capped at **20% of maxSupply**.
     *
     * Safety Checks:
     * - Ensures the user has rewards to mint (`userRewardAmount > 0`).
     * - Prevents minting if there are no new eligible holdings (`cumulativeMintableHoldings > 0`).
     * - Ensures total minting does not exceed **20% of maxSupply** per transaction.
     * - Guarantees total token supply does not exceed `maxSupply`.
     */
    function mintReward() external nonReentrant {
        // **Checks**
        uint256 reward = userRewardAmount[msg.sender];
        require(reward > 0, "1$: No reward to mint");

        uint256 mintableHoldings = cumulativeMintableHoldings[msg.sender];
        require(
            mintableHoldings > 0,
            "1$: No new holdings to calculate minting"
        );

        // Define the maximum mintable amount (20% of maxSupply)
        require(
            totalAirdropMinted + reward <= (maxSupply * 10) / 100,
            "Airdrop cap exceeded"
        );
        require(
            totalLiquidityMinted + reward <= (maxSupply * 10) / 100,
            "Liquidity cap exceeded"
        );

        // Ensure total supply does not exceed maxSupply after minting
        require(
            totalSupply() + (reward * 2) <= maxSupply,
            "1$: Max supply exceeded"
        );

        // **Effects**
        // Reset user reward and mintable holdings after minting
        userRewardAmount[msg.sender] = 0;
        cumulativeMintableHoldings[msg.sender] = 0;
        totalAirdropMinted += reward;
        totalLiquidityMinted += reward;
        // **Interactions**
        // Mint rewards to the user (10% of maxSupply over time)
        _mint(msg.sender, reward);

        // Deposit an equal amount into the DAV vault (10% of maxSupply over time)
        //Deposit minted token into the DAV vaults where pools are created to facilitate Ratio Swapping auctions.
        // This supports Ratio Swapping auctions and ensures market stability
        _mint(address(this), reward);
    }

    /**
     * @dev Calculate the base reward for a given DAV amount.
     */
    function calculateBaseReward(
        uint256 davAmount
    ) public view returns (uint256) {
        uint256 supply_p = maxSupply * 10;
        uint256 denominator = 5e9; // Equivalent to 5000000 * 1000
        uint256 precisionFactor = 1e17; // Scaling factor to maintain precision and calculation

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

    function getMax_supply() public view returns (uint256) {
        return maxSupply;
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

    /**
     * @dev Get the current decay percentage based on the block timestamp.
     */
    function getCurrentDecayPercentage() public view returns (uint256) {
        return getDecayPercentageAtTime(block.timestamp);
    }
    /* Governanace able to transfer tokens for providing liquidity to tokens */

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

    // updating Governanace if old is deprecated

    function updateGovernance(address newGov) external onlyGovernance {
        require(newGov != address(0), "Invalid address");
        require(
            block.timestamp >=
                lastGovernanceUpdate[governanceAddress] + COOLDOWN_PERIOD,
            "Governance update cooldown period not yet passed"
        );

        isAuthorized[governanceAddress] = false;
        governanceAddress = newGov;
        isAuthorized[newGov] = true;
        lastGovernanceUpdate[newGov] = block.timestamp;
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
