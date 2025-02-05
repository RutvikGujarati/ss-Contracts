// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import  {Xerion} from "../Tokens/Xerion.sol";
import {Decentralized_Autonomous_Vaults_DAV_V1_0} from  "../MainTokens/DavToken.sol";

contract AuctionRatioSwapping {
    address public admin;
    uint256 public auctionInterval = 2 hours;
    uint256 public auctionDuration = 1 hours;
    uint256 public burnWindowDuration = 1 hours;
    uint256 public inputAmountRate = 1;
    Xerion public xerion;
    uint256 public percentage = 1;
    address xerionAddress;
    address private constant BURN_ADDRESS =
        0x0000000000000000000000000000000000000369;

    address stateToken;
    modifier onlyGovernance() {
        require(
            msg.sender == governanceAddress,
            "Swapping: You are not authorized to perform this action"
        );
        _;
    }
    uint256 public TotalBurnedStates;
    uint256 public TotalTokensBurned;
    uint256 public totalBounty;

    uint256 bufferFee = 2100;
    struct Vault {
        uint256 totalDeposited;
        uint256 totalAuctioned;
    }

    struct Auction {
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        address xerionAddress;
        address stateToken;
    }

    struct UserSwapInfo {
        bool hasSwapped;
        bool hasReverseSwap;
        uint256 cycle;
    }
    struct BurnInfo {
        address user;
        uint256 remainingamount;
        uint256 bountyAMount;
        uint256 time;
    }
    mapping(address => Vault) public vaults;
    mapping(address => BurnInfo) public burnInfo;
    mapping(address => mapping(address => uint256)) public RatioTarget;
    mapping(address => mapping(address => bool)) public approvals;
    mapping(address => mapping(address => uint256)) public lastBurnTime;
    mapping(address => mapping(address => mapping(address => mapping(uint256 => UserSwapInfo))))
        public userSwapTotalInfo;
    uint256 public burnRate = 100000; // Default burn rate in thousandths (0.001)
    mapping(address => mapping(address => uint256)) public lastBurnCycle; // Track last burn cycle per token pair
    mapping(address => uint256) public maxSupply; // Max supply per token
    mapping(address => mapping(uint256 => bool)) public burnOccurredInCycle;

    event TokensBurned(
        address indexed user,
        address indexed token,
        uint256 burnedAmount,
        uint256 rewardAmount
    );

    event AuctionStarted(
        uint256 startTime,
        uint256 endTime,
        address xerionAddress,
        address stateToken
    );

    event TokensDeposited(address indexed token, uint256 amount);
    event AuctionStarted(
        uint256 startTime,
        uint256 endTime,
        address xerionAddress,
        address stateToken,
        uint256 collectionPercentage
    );
    event TokensSwapped(
        address indexed user,
        address indexed xerionAddress,
        address indexed stateToken,
        uint256 amountIn,
        uint256 amountOut
    );
    event TokensBurned(address indexed token, uint256 amountBurned);
    event AuctionIntervalUpdated(uint256 newInterval);

    modifier onlyAdmin() {
        require(
            msg.sender == governanceAddress,
            "Only admin can perform this action"
        );
        _;
    }

    Decentralized_Autonomous_Vaults_DAV_V1_0 public dav;

    constructor(
        address state,
        address davToken,
        address _xerion,
        address _gov
    ) {
        governanceAddress = _gov;
        xerion = Xerion(_xerion);
        xerionAddress = _xerion;
        stateToken = state;
        dav = Decentralized_Autonomous_Vaults_DAV_V1_0(payable(davToken));
    }

    address public governanceAddress;

    function depositTokens(address token, uint256 amount)
        external
        onlyGovernance
    {
        vaults[token].totalDeposited += amount;

        IERC20(token).transferFrom(msg.sender, address(this), amount);
        emit TokensDeposited(token, amount);
    }

    function setAuctionInterval(uint256 _newInterval) external onlyAdmin {
        require(_newInterval > 0, "Interval must be greater than 0");
        auctionInterval = _newInterval;
        emit AuctionIntervalUpdated(_newInterval);
    }

    struct AuctionCycle {
        uint256 firstAuctionStart; // Timestamp when the first auction started
        bool isInitialized; // Whether this pair has been initialized
    }
    mapping(address => mapping(address => AuctionCycle)) public auctionCycles;

    function isAuctionActive() public view returns (bool) {
        AuctionCycle memory cycle = auctionCycles[xerionAddress][stateToken];

        if (!cycle.isInitialized) {
            return false;
        }

        uint256 currentTime = block.timestamp;
        uint256 timeSinceStart = currentTime - cycle.firstAuctionStart;
        uint256 fullCycleLength = auctionDuration + auctionInterval;

        // If we're in a cycle, find where we are in it
        if (timeSinceStart > 0) {
            uint256 currentCyclePosition = timeSinceStart % fullCycleLength;
            return currentCyclePosition < auctionDuration;
        }

        return false;
    }

    function getNextAuctionStart() public view returns (uint256) {
        AuctionCycle memory cycle = auctionCycles[xerionAddress][stateToken];

        if (!cycle.isInitialized) {
            return 0;
        }

        uint256 currentTime = block.timestamp;
        uint256 timeSinceStart = currentTime - cycle.firstAuctionStart;
        uint256 fullCycleLength = auctionDuration + auctionInterval;

        uint256 currentCycleNumber = timeSinceStart / fullCycleLength;
        uint256 nextCycleStart = cycle.firstAuctionStart +
            (currentCycleNumber + 1) *
            fullCycleLength;

        return nextCycleStart;
    }

    function startAuction() public onlyAdmin {
        require(
            xerionAddress != address(0) && stateToken != address(0),
            "Invalid token addresses"
        );

        uint256 currentTime = block.timestamp;

        AuctionCycle storage cycle = auctionCycles[xerionAddress][stateToken];

        // Check if the auction for the specified pair is already initialized
        if (cycle.isInitialized) {
            uint256 auctionEndTime = cycle.firstAuctionStart + auctionDuration;

            // Ensure no auction is currently running for this pair
            require(
                currentTime >= auctionEndTime,
                "Auction already in progress, wait until it ends"
            );
        }

        cycle.firstAuctionStart = currentTime;
        cycle.isInitialized = true;

        auctionCycles[stateToken][xerionAddress] = AuctionCycle({
            firstAuctionStart: currentTime,
            isInitialized: true
        });

        uint256 newCycle = (currentTime - cycle.firstAuctionStart) /
            auctionDuration +
            1;
        lastBurnCycle[xerionAddress][stateToken] = newCycle - 1;
        lastBurnCycle[stateToken][xerionAddress] = newCycle - 1;
        emit AuctionStarted(
            currentTime,
            currentTime + auctionDuration,
            xerionAddress,
            stateToken
        );
    }

    function getCurrentAuctionCycle() public view returns (uint256) {
        AuctionCycle memory cycle = auctionCycles[xerionAddress][stateToken];
        if (!cycle.isInitialized) return 0;

        uint256 timeSinceStart = block.timestamp - cycle.firstAuctionStart;
        uint256 fullCycleLength = auctionDuration + auctionInterval;
        return timeSinceStart / fullCycleLength;
    }

    function isReverseSwapEnabled(uint256 currentRatio)
        public
        view
        returns (bool)      
    {
        if (currentRatio >= RatioTarget[xerionAddress][stateToken]) {
            return true;
        }
        return false;
    }

    function swapTokens(address user, uint256 ratio) external payable {
        require(stateToken != address(0), "State token cannot be null");
        require(
            dav.balanceOf(msg.sender) >= dav.getRequiredDAVAmount(),
            "required enough dav to paritcipate"
        );
        uint256 extraGas = getCurrentgas();
        uint256 currentAuctionCycle = getCurrentAuctionCycle();

        // Ensure the user has not swapped for this token pair in the current auction cycle
        UserSwapInfo storage userSwapInfo = userSwapTotalInfo[user][
            xerionAddress
        ][stateToken][currentAuctionCycle];

        if (isReverseSwapEnabled(ratio) == true) {
            require(
                !userSwapInfo.hasReverseSwap,
                "User already swapped in reverse auction for this cycle"
            );
        } else {
            require(
                !userSwapInfo.hasSwapped,
                "User already swapped in normal auction for this cycle"
            );
        }

        require(msg.sender != address(0), "Sender cannot be null");
        require(isAuctionActive(), "No active auction for this pair");

        address spender = msg.sender;
        if (msg.sender != tx.origin) {
            require(approvals[tx.origin][msg.sender], "Caller not approved");
            spender = tx.origin;
        }

        address inputToken = xerionAddress;
        address outputToken = stateToken;
        uint256 amountIn = getOnepercentOfUserBalance();
        uint256 amountOut = getOutPutAmount(ratio);

        if (isReverseSwapEnabled(ratio) == true) {
            require(
                isReverseSwapEnabled(ratio) == true,
                "Reverse swaps are disabled"
            );

            (inputToken, outputToken) = (outputToken, inputToken);

            (amountIn, amountOut) = getSwapAmounts(amountIn, amountOut);
        }

        require(
            amountIn > 0,
            "Not enough balance in user wallet of input token"
        );

        require(amountOut > 0, "Output amount must be greater than zero");

        Vault storage vaultOut = vaults[outputToken];
        require(
            vaultOut.totalDeposited >= vaultOut.totalAuctioned + amountOut,
            "Insufficient tokens in vault for the output token"
        );

        // Mark the user's swap for the current cycle

        userSwapInfo.cycle = currentAuctionCycle;

        vaultOut.totalAuctioned += amountOut;

        if (isReverseSwapEnabled(ratio) == true) {
            userSwapInfo.hasReverseSwap = true;

            IERC20(inputToken).transferFrom(spender, BURN_ADDRESS, amountIn);
            TotalBurnedStates += amountIn;
            IERC20(outputToken).transfer(spender, amountOut);
        } else {
            userSwapInfo.hasSwapped = true;
            IERC20(inputToken).transferFrom(spender, address(this), amountIn);
            IERC20(outputToken).transfer(spender, amountOut);
        }

        emit TokensSwapped(
            spender,
            inputToken,
            outputToken,
            amountIn,
            amountOut
        );

        require(
            msg.value >= extraGas,
            "Insufficient Ether to cover the extra fee"
        );

        // Transfer the extra fee to the governance address
        (bool success, ) = governanceAddress.call{value: extraGas}("");
        require(success, "Transfer to governance address failed");
    }

    function getSwapAmounts(uint256 _amountIn, uint256 _amountOut)
        public
        pure
        returns (uint256 newAmountIn, uint256 newAmountOut)
    {
        uint256 tempAmountOut = _amountIn * 2;

        newAmountIn = _amountOut;

        newAmountOut = tempAmountOut;

        return (newAmountIn, newAmountOut);
    }

    function burnTokens() external {
        AuctionCycle storage cycle = auctionCycles[xerionAddress][stateToken];
        require(cycle.isInitialized, "Auction not initialized for this pair");

        uint256 currentTime = block.timestamp;

        // Check if the auction is inactive before proceeding
        require(!isAuctionActive(), "Auction still active");

        uint256 fullCycleLength = auctionDuration + auctionInterval;
        uint256 timeSinceStart = currentTime - cycle.firstAuctionStart;
        uint256 currentCycle = (timeSinceStart / fullCycleLength) + 1;
        uint256 auctionEndTime = cycle.firstAuctionStart +
            currentCycle *
            fullCycleLength -
            auctionInterval;

        // Ensure we're within the burn window (after auction but before interval ends)
        require(
            currentTime >= auctionEndTime &&
                currentTime < auctionEndTime + burnWindowDuration,
            "Burn window has passed or not started"
        );

        // Prevent burn if it has already occurred in this cycle
        require(
            !burnOccurredInCycle[xerionAddress][currentCycle],
            "Burn already occurred for this cycle"
        );

        uint256 burnAmount = (xerion.balanceOf(address(this)) * 1) / burnRate;

        burnOccurredInCycle[xerionAddress][currentCycle] = true;
        lastBurnCycle[xerionAddress][stateToken] = currentCycle;
        lastBurnTime[xerionAddress][stateToken] = currentTime;

        // Reward user with 1% of burn amount
        uint256 reward = burnAmount / 100;
        totalBounty += reward;
        xerion.transfer(msg.sender, reward);

        // Burn the remaining tokens
        uint256 remainingBurnAmount = burnAmount - reward;
        TotalTokensBurned += remainingBurnAmount;
        xerion.transfer(BURN_ADDRESS, remainingBurnAmount);

        emit TokensBurned(
            msg.sender,
            xerionAddress,
            remainingBurnAmount,
            reward
        );
    }

    function setBuffer(uint256 amount) public {
        bufferFee = amount;
    }

    function getCurrentgas() public view returns (uint256) {
        return bufferFee;
    }

    function getBurnOccured() public view returns (bool) {
        AuctionCycle storage cycle = auctionCycles[xerionAddress][stateToken];
        if (!cycle.isInitialized) {
            return false;
        }
        uint256 currentTime = block.timestamp;

        uint256 fullCycleLength = auctionDuration + auctionInterval;
        uint256 timeSinceStart = currentTime - cycle.firstAuctionStart;
        uint256 currentCycle = (timeSinceStart / fullCycleLength) + 1;

        return burnOccurredInCycle[xerionAddress][currentCycle];
    }

    function isBurnCycleActive() external view returns (bool) {
        AuctionCycle storage cycle = auctionCycles[xerionAddress][stateToken];
        if (!cycle.isInitialized) {
            return false;
        }
        uint256 currentTime = block.timestamp;

        uint256 fullCycleLength = auctionDuration + auctionInterval;
        uint256 timeSinceStart = currentTime - cycle.firstAuctionStart;
        uint256 currentCycle = (timeSinceStart / fullCycleLength) + 1;
        uint256 auctionEndTime = cycle.firstAuctionStart +
            currentCycle *
            fullCycleLength -
            auctionInterval;

        if (
            currentTime >= auctionEndTime &&
            currentTime < auctionEndTime + burnWindowDuration
        ) {
            return true;
        } else {
            return false;
        }
    }

    function getTimeLeftInBurnCycle() public view returns (uint256) {
        AuctionCycle storage cycle = auctionCycles[xerionAddress][stateToken];
        if (!cycle.isInitialized) {
            return 0;
        }

        uint256 currentTime = block.timestamp;

        uint256 fullCycleLength = auctionDuration + auctionInterval;
        uint256 timeSinceStart = currentTime - cycle.firstAuctionStart;
        uint256 currentCycle = (timeSinceStart / fullCycleLength) + 1;
        uint256 auctionEndTime = cycle.firstAuctionStart +
            currentCycle *
            fullCycleLength -
            auctionInterval;

        // Check if we are in the burn window
        if (
            currentTime >= auctionEndTime &&
            currentTime < auctionEndTime + burnWindowDuration
        ) {
            return (auctionEndTime + burnWindowDuration) - currentTime;
        }

        // If the burn cycle is not active, return 0
        return 0;
    }

    function setRatioTarget(uint256 ratioTarget) external onlyAdmin {
        require(ratioTarget > 0, "Target ratio must be greater than zero");

        RatioTarget[xerionAddress][stateToken] = ratioTarget;
        RatioTarget[stateToken][xerionAddress] = ratioTarget;
    }

    function setAuctionDuration(uint256 _auctionDuration) external onlyAdmin {
        auctionDuration = _auctionDuration;
    }

    function setBurnDuration(uint256 _auctionDuration) external onlyAdmin {
        burnWindowDuration = _auctionDuration;
    }

    function setInputAmountRate(uint256 rate) public onlyAdmin {
        inputAmountRate = rate;
    }

    function getUserHasSwapped(address user) public view returns (bool) {
        uint256 getCycle = getCurrentAuctionCycle();
        return
            userSwapTotalInfo[user][xerionAddress][stateToken][getCycle]
                .hasSwapped;
    }

    function getUserHasReverseSwapped(address user) public view returns (bool) {
        uint256 getCycle = getCurrentAuctionCycle();
        return
            userSwapTotalInfo[user][xerionAddress][stateToken][getCycle]
                .hasReverseSwap;
    }

    function getRatioTarget() public view returns (uint256) {
        return RatioTarget[xerionAddress][stateToken];
    }

    function setInAmountPercentage(uint256 amount) public onlyAdmin {
        percentage = amount;
    }

    function getOnepercentOfUserBalance() public view returns (uint256) {
        uint256 davbalance = dav.balanceOf(msg.sender);
        if (davbalance == 0) {
            return 0;
        }
        uint256 firstCal = (xerion.getMax_supply() * percentage) / 100 ether;
        uint256 secondCalWithDavMax = (firstCal / 5000000) * davbalance;
        return secondCalWithDavMax;
    }

    function getOutPutAmount(uint256 currentRatio)
        public
        view
        returns (uint256)
    {
        uint256 davbalance = dav.balanceOf(msg.sender);
        if (davbalance == 0) {
            return 0;
        }
        uint256 getOnePercent = getOnepercentOfUserBalance();
        uint256 multiplications = (getOnePercent * currentRatio) * 2;
        return multiplications;
    }

    function setBurnRate(uint256 _burnRate) external onlyAdmin {
        require(_burnRate > 0, "Burn rate must be greater than 0");
        burnRate = _burnRate;
    }

    function getTotalStateBurned() public view returns (uint256) {
        return TotalBurnedStates;
    }

    function getTotalBountyCollected() public view returns (uint256) {
        return totalBounty;
    }

    function getTotalTokensBurned() public view returns (uint256) {
        return TotalTokensBurned;
    }

    function getTimeLeftInAuction() public view returns (uint256) {
        if (!isAuctionActive()) {
            return 0; // Auction is not active
        }

        AuctionCycle storage cycle = auctionCycles[xerionAddress][stateToken];
        uint256 currentTime = block.timestamp;

        uint256 timeSinceStart = currentTime - cycle.firstAuctionStart;
        uint256 fullCycleLength = auctionDuration + auctionInterval;

        uint256 currentCyclePosition = timeSinceStart % fullCycleLength;

        if (currentCyclePosition < auctionDuration) {
            return auctionDuration - currentCyclePosition;
        }

        return 0;
    }
}
