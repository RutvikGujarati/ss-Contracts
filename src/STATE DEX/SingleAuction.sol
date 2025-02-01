// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Fluxin.sol";

contract AuctionRatioSwapping {
    address public admin;
    uint256 public auctionInterval = 2 hours;
    uint256 public auctionDuration = 1 hours;
    uint256 public burnWindowDuration = 1 hours;
    uint256 public inputAmountRate = 1;
    Fluxin public fluxin;
    uint256 public percentage = 1;
    address fluxinAddress;
    address private constant BURN_ADDRESS =
        0x0000000000000000000000000000000000000369;

    bool public reverseSwapEnabled = false;
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
    struct Vault {
        uint256 totalDeposited;
        uint256 totalAuctioned;
    }

    struct Auction {
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        address fluxinAddress;
        address stateToken;
    }

    struct UserSwapInfo {
        bool hasSwapped;
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
    uint256 public burnRate = 1000; // Default burn rate in thousandths (0.001)
    mapping(address => mapping(address => uint256)) public lastBurnCycle; // Track last burn cycle per token pair
    mapping(address => uint256) public maxSupply; // Max supply per token
    mapping(address => mapping(address => mapping(uint256 => bool)))
        public burnOccurredInCycle;

    event TokensBurned(
        address indexed user,
        address indexed token,
        uint256 burnedAmount,
        uint256 rewardAmount
    );

    event AuctionStarted(
        uint256 startTime,
        uint256 endTime,
        address fluxinAddress,
        address stateToken
    );

    event TokensDeposited(address indexed token, uint256 amount);
    event AuctionStarted(
        uint256 startTime,
        uint256 endTime,
        address fluxinAddress,
        address stateToken,
        uint256 collectionPercentage
    );
    event TokensSwapped(
        address indexed user,
        address indexed fluxinAddress,
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

    IERC20 public dav;

    constructor(
        address state,
        address davToken,
        address _fluxin,
        address _gov
    ) {
        governanceAddress = _gov;
        fluxin = Fluxin(_fluxin);
        fluxinAddress = _fluxin;
        stateToken = state;
        dav = IERC20(payable(davToken));
    }

    address public governanceAddress;

    function depositTokens(
        address token,
        uint256 amount
    ) external onlyGovernance {
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
        AuctionCycle memory cycle = auctionCycles[fluxinAddress][stateToken];

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

    // Function to get the next auction start time for a pair
    function getNextAuctionStart() public view returns (uint256) {
        AuctionCycle memory cycle = auctionCycles[fluxinAddress][stateToken];

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
            fluxinAddress != address(0) && stateToken != address(0),
            "Invalid token addresses"
        );

        uint256 currentTime = block.timestamp;

        AuctionCycle storage cycle = auctionCycles[fluxinAddress][stateToken];

        // Check if the auction for the specified pair is already initialized
        if (cycle.isInitialized) {
            uint256 auctionEndTime = cycle.firstAuctionStart + auctionDuration;

            // Ensure no auction is currently running for this pair
            require(
                currentTime >= auctionEndTime,
                "Auction already in progress, wait until it ends"
            );
        }

        // Initialize and start the auction for the specified pair
        cycle.firstAuctionStart = currentTime;
        cycle.isInitialized = true;

        // Initialize reverse pair
        auctionCycles[stateToken][fluxinAddress] = AuctionCycle({
            firstAuctionStart: currentTime,
            isInitialized: true
        });

        // Reset burn tracking for the new auction cycle
        uint256 newCycle = (currentTime - cycle.firstAuctionStart) /
            auctionDuration +
            1;
        lastBurnCycle[fluxinAddress][stateToken] = newCycle - 1;
        lastBurnCycle[stateToken][fluxinAddress] = newCycle - 1;

        emit AuctionStarted(
            currentTime,
            currentTime + auctionDuration,
            fluxinAddress,
            stateToken
        );
    }

    // Get current auction cycle number for a pair
    function getCurrentAuctionCycle() public view returns (uint256) {
        AuctionCycle memory cycle = auctionCycles[fluxinAddress][stateToken];
        if (!cycle.isInitialized) return 0;

        uint256 timeSinceStart = block.timestamp - cycle.firstAuctionStart;
        uint256 fullCycleLength = auctionDuration + auctionInterval;
        return timeSinceStart / fullCycleLength;
    }

    function swapTokens(
        address user,
        uint256 amountOut,
        uint256 extraGas
    ) external payable {
        require(stateToken != address(0), "State token cannot be null");

        // Get current auction cycle
        uint256 currentAuctionCycle = getCurrentAuctionCycle();

        // Ensure the user has not swapped for this token pair in the current auction cycle
        UserSwapInfo storage userSwapInfo = userSwapTotalInfo[user][
            fluxinAddress
        ][stateToken][currentAuctionCycle];
        require(
            !userSwapInfo.hasSwapped,
            "User already swapped in this auction cycle for this pair"
        );

        require(msg.sender != address(0), "Sender cannot be null");
        require(isAuctionActive(), "No active auction for this pair");

        address spender = msg.sender;
        if (msg.sender != tx.origin) {
            require(approvals[tx.origin][msg.sender], "Caller not approved");
            spender = tx.origin;
        }

        // Adjust token addresses and amounts if reverse swap is enabled
        address inputToken = fluxinAddress;
        address outputToken = stateToken;
        uint256 amountIn = getOnepercentOfUserBalance(); // Default amountIn

        if (reverseSwapEnabled) {
            require(reverseSwapEnabled, "Reverse swaps are disabled");

            // Swap input and output tokens
            (inputToken, outputToken) = (outputToken, inputToken);

            // Use the new logic for swapping amounts
            (amountIn, amountOut) = getSwapAmounts(amountIn, amountOut); // Get new amounts based on swap logic
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
        userSwapInfo.hasSwapped = true;
        userSwapInfo.cycle = currentAuctionCycle;

        vaultOut.totalAuctioned += amountOut;

        if (reverseSwapEnabled) {
            IERC20(inputToken).transferFrom(spender, BURN_ADDRESS, amountIn);
            TotalBurnedStates += amountIn;
            IERC20(outputToken).transfer(spender, amountOut);
        } else {
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

    function getSwapAmounts(
        uint256 _amountIn,
        uint256 _amountOut
    ) public pure returns (uint256 newAmountIn, uint256 newAmountOut) {
        uint256 tempAmountOut = _amountIn * 2;

        newAmountIn = _amountOut;

        newAmountOut = tempAmountOut;

        return (newAmountIn, newAmountOut);
    }

    function burnTokens() external {
        AuctionCycle storage cycle = auctionCycles[fluxinAddress][stateToken];
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

        // Allow burn only once per cycle
        require(
            !burnOccurredInCycle[msg.sender][fluxinAddress][currentCycle],
            "Burn already occurred for this cycle"
        );

        uint256 burnAmount = (fluxin.balanceOf(address(this)) * 1) / burnRate;

        // Mark this cycle as burned
        burnOccurredInCycle[msg.sender][fluxinAddress][currentCycle] = true;
        lastBurnCycle[fluxinAddress][stateToken] = currentCycle;
        lastBurnTime[fluxinAddress][stateToken] = currentTime;

        // Reward user with 1% of burn amount
        uint256 reward = burnAmount / 100;
        fluxin.transfer(msg.sender, reward);

        // Burn the remaining tokens
        uint256 remainingBurnAmount = burnAmount - reward;
		TotalTokensBurned +=remainingBurnAmount;
		totalBounty += reward;
        fluxin.transfer(msg.sender, reward);
        fluxin.transfer(BURN_ADDRESS, remainingBurnAmount);

        emit TokensBurned(
            msg.sender,
            fluxinAddress,
            remainingBurnAmount,
            reward
        );
    }

    function getBurnOccured() public view returns (bool) {
        // Get the current auction cycle
        AuctionCycle storage cycle = auctionCycles[fluxinAddress][stateToken];
        require(cycle.isInitialized, "Auction not initialized for this pair");

        uint256 currentTime = block.timestamp;

        uint256 fullCycleLength = auctionDuration + auctionInterval;
        uint256 timeSinceStart = currentTime - cycle.firstAuctionStart;
        uint256 currentCycle = (timeSinceStart / fullCycleLength) + 1;

        // Return whether the burn has occurred in the current cycle
        return burnOccurredInCycle[msg.sender][fluxinAddress][currentCycle];
    }

    function isBurnCycleActive() external view returns (bool) {
        AuctionCycle storage cycle = auctionCycles[fluxinAddress][stateToken];
        require(cycle.isInitialized, "Auction not initialized for this pair");

        uint256 currentTime = block.timestamp;

        uint256 fullCycleLength = auctionDuration + auctionInterval;
        uint256 timeSinceStart = currentTime - cycle.firstAuctionStart;
        uint256 currentCycle = (timeSinceStart / fullCycleLength) + 1;
        uint256 auctionEndTime = cycle.firstAuctionStart +
            currentCycle *
            fullCycleLength -
            auctionInterval;

        // Check if the current time is within the burn window
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
        AuctionCycle storage cycle = auctionCycles[fluxinAddress][stateToken];
        require(cycle.isInitialized, "Auction not initialized for this pair");

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

        RatioTarget[fluxinAddress][stateToken] = ratioTarget;
        RatioTarget[stateToken][fluxinAddress] = ratioTarget;
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

    function setReverseSwap(bool _swap) public onlyAdmin {
        reverseSwapEnabled = _swap;
    }

    function getUserHasSwapped() public view returns (bool) {
        uint256 getCycle = getCurrentAuctionCycle();
        return
            userSwapTotalInfo[msg.sender][fluxinAddress][stateToken][getCycle]
                .hasSwapped;
    }

    function getRatioTarget() public view returns (uint256) {
        return RatioTarget[fluxinAddress][stateToken];
    }

    function getOnepercentOfUserBalance() public view returns (uint256) {
        uint256 davbalance = dav.balanceOf(msg.sender);
        if (davbalance == 0) {
            return 0;
        }
        uint256 firstCal = (1000000000000 * percentage) / 100;
        uint256 secondCalWithDavMax = (firstCal / 5000000) * davbalance;
        return secondCalWithDavMax;
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

        AuctionCycle storage cycle = auctionCycles[fluxinAddress][stateToken];
        uint256 currentTime = block.timestamp;

        uint256 timeSinceStart = currentTime - cycle.firstAuctionStart;
        uint256 fullCycleLength = auctionDuration + auctionInterval;

        // Calculate the current auction cycle position
        uint256 currentCyclePosition = timeSinceStart % fullCycleLength;

        // Calculate and return the remaining time if within auction duration
        if (currentCyclePosition < auctionDuration) {
            return auctionDuration - currentCyclePosition;
        }

        return 0; // No time left in the auction
    }
}
