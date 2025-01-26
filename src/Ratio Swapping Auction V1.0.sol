// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./STATE DEX/Fluxin.sol";

contract AuctionRatioSwapping {
    address public admin;
    uint256 public auctionInterval = 45 minutes;
    uint256 public auctionDuration = 20 minutes;
    uint256 public burnWindowDuration = 20 minutes;
    uint256 public inputAmountRate = 1;
    Fluxin public fluxin;
    address fluxinAddress;
    address private constant BURN_ADDRESS =
        0x0000000000000000000000000000000000000000;

    bool public reverseSwapEnabled = true; // Initially enabled
    address stateToken;
    modifier onlyGovernance() {
        require(
            msg.sender == governanceAddress,
            "Swapping: You are not authorized to perform this action"
        );
        _;
    }

    struct Vault {
        uint256 totalDeposited;
        uint256 totalAuctioned;
    }
    struct AuctionInfo {
        uint256 cycle;
        uint256 currentRatio;
        uint256 ratioTarget;
        uint256 reverseCurrentRatio;
        uint256 reverseRatioTarget;
    }

    struct Auction {
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        address fluxinAddress;
        address stateToken;
    }

    struct UserSwapInfo {
        bool hasSwapped; // Whether the user has swapped in this cycle for this pair
        uint256 cycle; // The auction cycle for the token pair
    }
    struct BurnInfo {
        address user;
        uint256 remainingamount;
        uint256 bountyAMount;
        uint256 time;
    }
    // Struct to store reverse swap settings for a pair
    struct ReverseSwapSettings {
        bool isEnabled; // Whether reverse swap is enabled for the pair
        uint256 startTime; // Start time for reverse swap
        uint256 endTime; // End time for reverse swap
    }

    mapping(address => Vault) public vaults;
    mapping(address => BurnInfo) public burnInfo;
    mapping(address => mapping(address => uint256)) public RatioTarget;
    mapping(address => mapping(address => uint256)) public CurrentRatio;
    mapping(address => mapping(address => bool)) public approvals;
    mapping(address => mapping(address => uint256)) public lastBurnTime;
    mapping(address => mapping(address => mapping(address => mapping(uint256 => UserSwapInfo))))
        public userSwapTotalInfo;
    mapping(address => mapping(address => ReverseSwapSettings))
        public reverseSwapSettings;
    uint256 public burnRate = 1; // Default burn rate in thousandths (0.001)
    mapping(address => mapping(address => uint256)) public lastBurnCycle; // Track last burn cycle per token pair
    mapping(address => uint256) public maxSupply; // Max supply per token

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

    function setCurrentRatioTarget(uint256 ratioTarget) public onlyAdmin {
        CurrentRatio[fluxinAddress][stateToken] = ratioTarget;
        CurrentRatio[stateToken][fluxinAddress] = ratioTarget;
        RatioTarget[fluxinAddress][stateToken] = ratioTarget + 1;
        RatioTarget[stateToken][fluxinAddress] = ratioTarget + 1;
    }

    function depositTokens(
        address token,
        uint256 amount,
        uint256 _RatioTarget
    ) external onlyGovernance {
        vaults[token].totalDeposited += amount;

        IERC20(token).transferFrom(msg.sender, address(this), amount);
        setCurrentRatioTarget(_RatioTarget);
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
        lastBurnCycle[fluxinAddress][stateToken] = newCycle - 1; // Set last burn to the previous cycle
        lastBurnCycle[stateToken][fluxinAddress] = newCycle - 1;

        emit AuctionStarted(
            currentTime,
            currentTime + auctionDuration,
            fluxinAddress,
            stateToken
        );
    }

    function calculateAmountOut(uint256 amountIn)
        public
        view
        returns (uint256)
    {
        require(CurrentRatio[fluxinAddress][stateToken] > 0, "Ratio not set");
        // Assuming ratio is in 1e18 precision
        return (amountIn * (CurrentRatio[fluxinAddress][stateToken] * 2));
    }

    // Get current auction cycle number for a pair
    function getCurrentAuctionCycle() public view returns (uint256) {
        AuctionCycle memory cycle = auctionCycles[fluxinAddress][stateToken];
        if (!cycle.isInitialized) return 0;

        uint256 timeSinceStart = block.timestamp - cycle.firstAuctionStart;
        uint256 fullCycleLength = auctionDuration + auctionInterval;
        return timeSinceStart / fullCycleLength;
    }

    function checkIfReverseSwap() internal view returns (bool) {
        ReverseSwapSettings memory settings = reverseSwapSettings[
            fluxinAddress
        ][stateToken];
        uint256 currentTime = block.timestamp;

        // Check if the current time is within the reverse swap time range
        if (
            currentTime >= settings.startTime && currentTime <= settings.endTime
        ) {
            // Check if the ratio condition for reverse swap is met
            return (CurrentRatio[stateToken][fluxinAddress] <
                RatioTarget[stateToken][fluxinAddress] ||
                CurrentRatio[fluxinAddress][stateToken] <
                RatioTarget[fluxinAddress][stateToken]);
        }

        return false; // Default to no reverse swap if conditions are not met
    }

    function swapTokens(address user, uint256 extraFee) external payable {
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

        // Reverse swap check
        bool reverseSwap = checkIfReverseSwap();

        // Adjust token addresses if reverse swap is enabled
        address inputToken = fluxinAddress;
        address outputToken = stateToken;

        if (reverseSwap) {
            require(reverseSwapEnabled, "Reverse swaps are disabled");
            (inputToken, outputToken) = (outputToken, inputToken);
        }

        uint256 amountIn = getOnepercentOfUserBalance();
        require(
            amountIn > 0,
            "Not enough balance in user wallet of input token"
        );

        uint256 amountOut = calculateAmountOut(amountIn);
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

        // Transfer tokens
        IERC20(inputToken).transferFrom(spender, address(this), amountIn);
        IERC20(outputToken).transfer(spender, amountOut);

        require(
            msg.value >= extraFee,
            "Insufficient Ether to cover the extra fee"
        );

        // Transfer the extra fee to the governance address
        payable(governanceAddress).transfer(extraFee);
        emit TokensSwapped(
            spender,
            inputToken,
            outputToken,
            amountIn,
            amountOut
        );
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
            lastBurnCycle[fluxinAddress][stateToken] < currentCycle,
            "Burn already occurred for this cycle"
        );

        uint256 burnAmount = (fluxin.balanceOf(address(this)) * burnRate) /
            1000;

        // Mark this cycle as burned
        lastBurnCycle[fluxinAddress][stateToken] = currentCycle;
        lastBurnTime[fluxinAddress][stateToken] = currentTime;

        // Reward user with 1% of burn amount
        uint256 reward = burnAmount / 100;
        fluxin.transfer(msg.sender, reward);

        // Burn the remaining tokens
        uint256 remainingBurnAmount = burnAmount - reward;
        burnInfo[msg.sender].remainingamount = remainingBurnAmount;
        burnInfo[msg.sender].bountyAMount = reward;
        fluxin.transfer(BURN_ADDRESS, remainingBurnAmount);

        emit TokensBurned(
            msg.sender,
            fluxinAddress,
            remainingBurnAmount,
            reward
        );
    }

    function getBurnCycleInfo()
        external
        view
        returns (
            uint256 currentCycle,
            uint256 nextBurnStartTime,
            uint256 nextBurnEndTime,
            bool isBurnWindowActive
        )
    {
        AuctionCycle storage cycle = auctionCycles[fluxinAddress][stateToken];
        require(cycle.isInitialized, "Auction not initialized for this pair");

        // Get the current auction cycle
        currentCycle = getCurrentAuctionCycle();

        // Calculate the auction end time for the current cycle
        uint256 auctionStartTime = cycle.firstAuctionStart +
            (currentCycle - 1) *
            auctionDuration;
        uint256 auctionEndTime = auctionStartTime + auctionDuration;

        // Determine the next burn start and end time
        nextBurnStartTime = auctionEndTime; // Burn starts immediately after auction ends
        nextBurnEndTime = auctionEndTime + burnWindowDuration; // Burn window duration

        // Check if the current time falls within the burn window
        uint256 currentTime = block.timestamp;
        isBurnWindowActive = (currentTime >= nextBurnStartTime &&
            currentTime <= nextBurnEndTime);

        return (
            currentCycle,
            nextBurnStartTime,
            nextBurnEndTime,
            isBurnWindowActive
        );
    }

    function setRatioTarget(uint256 ratioTarget) external onlyAdmin {
        require(ratioTarget > 0, "Target ratio must be greater than zero");

        RatioTarget[fluxinAddress][stateToken] = ratioTarget;
        RatioTarget[stateToken][fluxinAddress] = ratioTarget;
    }

    function withdrawToken(address tokenAddress, uint256 amount)
        public
        onlyAdmin
    {
        require(tokenAddress.code.length > 0, "Token must be a contract");

        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, "not enough tokens available in contract");
        bool success = token.transfer(governanceAddress, amount);
        require(success, "Transfer failed");
    }

    function setAuctionDuration(uint256 _auctionDuration) external onlyAdmin {
        auctionDuration = _auctionDuration;
    }

    function setBurnDuration(uint256 _auctionDuration) external onlyAdmin {
        burnWindowDuration = _auctionDuration;
    }

    function setReverseSwapTimeRangeForPair(
        uint256 _startTime,
        uint256 _endTime
    ) external onlyAdmin {
        require(_startTime < _endTime, "Start time must be before end time");
        reverseSwapSettings[fluxinAddress][stateToken].startTime = _startTime;
        reverseSwapSettings[fluxinAddress][stateToken].endTime = _endTime;

        // Ensure reverse mapping is consistent
        reverseSwapSettings[stateToken][fluxinAddress].startTime = _startTime;
        reverseSwapSettings[stateToken][fluxinAddress].endTime = _endTime;
    }

    function setInputAmountRate(uint256 rate) public onlyAdmin {
        inputAmountRate = rate;
    }

    function setReverseSwap(bool _swap) public onlyAdmin {
        reverseSwapEnabled = _swap;
    }

    function getOnepercentOfUserBalance() public view returns (uint256) {
        uint256 davbalance = dav.balanceOf(msg.sender);
        if (davbalance == 0) {
            return 0;
        }
        uint256 balance = fluxin.balanceOf(msg.sender);
        uint256 onePercent = (balance * inputAmountRate) / 100;
        return onePercent;
    }

    function setBurnRate(uint256 _burnRate) external onlyAdmin {
        require(_burnRate > 0, "Burn rate must be greater than 0");
        burnRate = _burnRate;
    }

    function setMaxSupply(address token, uint256 _maxSupply)
        external
        onlyAdmin
    {
        maxSupply[token] = _maxSupply;
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
