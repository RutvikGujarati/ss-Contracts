// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Decentralized_Autonomous_Vaults_DAV_V1_1} from "../MainTokens/DavToken.sol";
import {Orxa} from "../Tokens/Orxa.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IPair {
    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function token0() external view returns (address);

    function token1() external view returns (address);
}
contract Ratio_Swapping_Auctions_V1_1 is Ownable(msg.sender), ReentrancyGuard {
    using SafeERC20 for IERC20;
    Decentralized_Autonomous_Vaults_DAV_V1_1 public dav;
    uint256 public auctionInterval = 1 hours;
    uint256 public auctionDuration = 1 hours;
    uint256 public reverseDuration = 1 hours;
    Orxa public orxa;
    uint256 public percentage = 1;
    address public orxaAddress;
    address private constant BURN_ADDRESS =
        0x0000000000000000000000000000000000000369;

    address public stateToken;
    address public pairAddress; // for orxa
    address public orxaToken;
    address public pstateToken;
    address public governanceAddress;

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
    uint256 private constant COOLDOWN_PERIOD = 24 hours;

    struct Vault {
        uint256 totalDeposited;
        uint256 totalAuctioned;
    }

    struct Auction {
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        address orxaAddress;
        address stateToken;
    }
    struct AuctionCycle {
        uint256 firstAuctionStart; // Timestamp when the first auction started
        bool isInitialized; // Whether this pair has been initialized
    }
    struct UserSwapInfo {
        bool hasSwapped;
        bool hasReverseSwap;
        uint256 cycle;
    }

    mapping(address => Vault) public vaults;
    uint256 public RatioTarget;
    mapping(address => mapping(address => bool)) public approvals;
    mapping(address => mapping(address => mapping(address => mapping(uint256 => UserSwapInfo))))
        public userSwapTotalInfo;
    mapping(address => uint256) public maxSupply; // Max supply per token
    mapping(uint256 => bool) public reverseAuctionActive;
    mapping(address => mapping(address => AuctionCycle)) public auctionCycles;
    mapping(address => uint256) public TotalStateBurnedByUser;
    mapping(address => uint256) private lastGovernanceUpdate;

    event AuctionStarted(
        uint256 startTime,
        uint256 endTime,
        address orxaAddress,
        address stateToken
    );
    event AuctionDurationUpdated(uint256 newAuctionDuration);
    event TokensDeposited(address indexed token, uint256 amount);

    event TokensSwapped(
        address indexed user,
        address indexed orxaAddress,
        address indexed stateToken,
        uint256 amountIn,
        uint256 amountOut
    );
    event AuctionIntervalUpdated(uint256 newInterval);

    constructor(
        address state,
        address davToken,
        address _orxa,
        address _gov,
        address _pairState,
        address _pairOrxa,
        address _pairAddress
    ) {
        governanceAddress = _gov;
        orxa = Orxa(_orxa);
        orxaAddress = _orxa;
        stateToken = state;
        pairAddress = _pairAddress;
        orxaToken = _pairOrxa;
        pstateToken = _pairState;
        dav = Decentralized_Autonomous_Vaults_DAV_V1_1(payable(davToken));
    }

    function getRatioPrice() public view returns (uint256) {
        IPair pair = IPair(pairAddress);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        address token0 = pair.token0();
        address token1 = pair.token1();

        require(reserve0 > 0 && reserve1 > 0, "Invalid reserves"); // ✅ Prevents division by zero

        uint256 ratio;
        if (token0 == orxaToken && token1 == pstateToken) {
            ratio = (uint256(reserve1) * 1e18) / uint256(reserve0);
        } else if (token0 == pstateToken && token1 == orxaToken) {
            ratio = (uint256(reserve0) * 1e18) / uint256(reserve1);
        } else {
            revert("Invalid pair, does not match orxa/PSTATE");
        }

        return ratio;
    }

    function depositTokens(
        address token,
        uint256 amount
    ) external onlyGovernance {
        require(token != address(0), "Orxa: Invalid token address");
        require(amount > 0, "Orxa: Cannot deposit zero tokens");
        vaults[token].totalDeposited += amount;

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit TokensDeposited(token, amount);
    }

    function startAuction() public onlyGovernance {
        require(
            orxaAddress != address(0) && stateToken != address(0),
            "Invalid token addresses"
        );

        uint256 currentTime = block.timestamp;

        AuctionCycle storage cycle = auctionCycles[orxaAddress][stateToken];

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

        auctionCycles[stateToken][orxaAddress] = AuctionCycle({
            firstAuctionStart: currentTime,
            isInitialized: true
        });

        emit AuctionStarted(
            currentTime,
            currentTime + auctionDuration,
            orxaAddress,
            stateToken
        );
    }

    function checkAndActivateReverseAuction() internal {
        uint256 currentAuctionCycle = getCurrentAuctionCycle();
        uint256 currentRatio = getRatioPrice();
        uint256 RatioTargetForRevrese = getRatioTarget();
        uint256 currentRatioNormalized = currentRatio / 1e18;
        if (
            !reverseAuctionActive[currentAuctionCycle] &&
            currentRatioNormalized >= RatioTargetForRevrese
        ) {
            reverseAuctionActive[currentAuctionCycle] = true;
        }
    }

    function checkAndActivateReverseForNextCycle() public onlyGovernance {
        uint256 currentRatio = getRatioPrice();
        uint256 currentRatioNormalized = currentRatio / 1e18;
        uint256 currentAuctionCycle = getCurrentAuctionCycle();
        uint256 RatioTargetForRevrese = getRatioTarget();
        if (isAuctionActive()) {
            if (
                !reverseAuctionActive[currentAuctionCycle] &&
                currentRatioNormalized >= RatioTargetForRevrese
            ) {
                reverseAuctionActive[currentAuctionCycle] = true;
            }
        } else if (
            !reverseAuctionActive[currentAuctionCycle + 1] &&
            currentRatioNormalized >= _RatioTarget
        ) {
            reverseAuctionActive[currentAuctionCycle + 1] = true;
        }
    }

    function swapTokens(address user) public nonReentrant {
        require(stateToken != address(0), "State token cannot be null");
        require(
            dav.balanceOf(user) >= dav.getRequiredDAVAmount(),
            "required enough dav to paritcipate"
        );
        uint256 currentAuctionCycle = getCurrentAuctionCycle();

        // Ensure the user has not swapped for this token pair in the current auction cycle
        UserSwapInfo storage userSwapInfo = userSwapTotalInfo[user][
            orxaAddress
        ][stateToken][currentAuctionCycle];
        bool isReverseActive = isReverseAuctionActive();

        if (isReverseActive == true) {
            require(isReverseActive, "No active reverse Auction for this pair");
            require(
                !userSwapInfo.hasReverseSwap,
                "User already swapped in reverse auction for this cycle"
            );
        } else {
            require(isAuctionActive(), "No active auction for this pair");
            require(
                !userSwapInfo.hasSwapped,
                "User already swapped in normal auction for this cycle"
            );
        }

        require(user != address(0), "Sender cannot be null");

        address spender = user;
        if (user != tx.origin) {
            require(approvals[tx.origin][user], "Caller not approved");
            spender = tx.origin;
        }

        address inputToken = orxaAddress;
        address outputToken = stateToken;
        uint256 amountIn = calculateAuctionEligibleAmount();
        uint256 amountOut = getOutPutAmount();

        if (isReverseActive == true) {
            require(isReverseActive == true, "Reverse swaps are disabled");

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

        if (isReverseActive == true) {
            userSwapInfo.hasReverseSwap = true;
            require(
                vaults[outputToken].totalDeposited > 0,
                "outputToken vault empty"
            );
            IERC20(inputToken).safeTransferFrom(
                spender,
                BURN_ADDRESS,
                amountIn
            );
            TotalBurnedStates += amountIn;
            TotalStateBurnedByUser[user] += amountIn;
            IERC20(outputToken).safeTransfer(spender, amountOut);
        } else {
            userSwapInfo.hasSwapped = true;
            require(
                vaults[outputToken].totalDeposited > 0,
                "outputToken vault empty"
            );
            IERC20(inputToken).safeTransferFrom(
                spender,
                BURN_ADDRESS,
                amountIn
            );
            TotalTokensBurned += amountIn;
            IERC20(outputToken).safeTransfer(spender, amountOut);
        }

        emit TokensSwapped(
            spender,
            inputToken,
            outputToken,
            amountIn,
            amountOut
        );
        checkAndActivateReverseAuction();
    }

    function setRatioTarget(uint256 ratioTarget) external onlyGovernance {
        /**
         * @dev Sets the target ratio for auctions.
         * - This DApp **does not use scaled ratios (1e18 precision)** anywhere.
         * - Both **current ratio and RatioTarget** are stored and compared in their **raw integer form**.
         * - Ensures that **RatioTarget is always greater than 1**, preventing invalid values.
         * - Since the current ratio is derived from `getRatioPrice()`, it **can never be 0 or below 1**.
         */

        require(ratioTarget > 1, "Target ratio must be greater than one");

        // Store the ratio target directly without applying 1e18 scaling.
        RatioTarget = ratioTarget;
    }

    function setAuctionDuration(
        uint256 _auctionDuration
    ) external onlyGovernance {
        auctionDuration = _auctionDuration;
        emit AuctionDurationUpdated(_auctionDuration);
    }

    function setAddressOfPair(
        address _pairState,
        address _pairOrxa,
        address _pairAddress
    ) public onlyGovernance {
        pairAddress = _pairAddress;
        orxaToken = _pairOrxa;
        pstateToken = _pairState;
    }
    function setAuctionInterval(uint256 _newInterval) external onlyGovernance {
        require(_newInterval > 0, "Interval must be greater than 0");
        auctionInterval = _newInterval;
        emit AuctionIntervalUpdated(_newInterval);
    }
    function setInAmountPercentage(uint256 amount) public onlyGovernance {
        require(amount <= 100, "should be less than 100");
        percentage = amount;
    }
    function updateGovernance(address newGov) external onlyGovernance {
        require(newGov != address(0), "Invalid address");
        require(
            block.timestamp >=
                lastGovernanceUpdate[governanceAddress] + COOLDOWN_PERIOD,
            "Governance update cooldown period not yet passed"
        );

        governanceAddress = newGov;
        lastGovernanceUpdate[newGov] = block.timestamp;
    }
    function getUserHasSwapped(address user) public view returns (bool) {
        uint256 getCycle = getCurrentAuctionCycle();
        return
            userSwapTotalInfo[user][orxaAddress][stateToken][getCycle]
                .hasSwapped;
    }

    function getUserHasReverseSwapped(address user) public view returns (bool) {
        uint256 getCycle = getCurrentAuctionCycle();
        return
            userSwapTotalInfo[user][orxaAddress][stateToken][getCycle]
                .hasReverseSwap;
    }

    function getRatioTarget() public view returns (uint256) {
        return RatioTarget;
    }

    function isAuctionActive() public view returns (bool) {
        AuctionCycle memory cycle = auctionCycles[orxaAddress][stateToken];

        if (!cycle.isInitialized) {
            return false;
        }
        uint256 currentCycle = getCurrentAuctionCycle();
        uint256 currentTime = block.timestamp;
        uint256 timeSinceStart = currentTime - cycle.firstAuctionStart;
        uint256 fullCycleLength = auctionDuration + auctionInterval;
        uint256 currentCyclePosition = timeSinceStart % fullCycleLength;

        if (
            reverseAuctionActive[currentCycle] &&
            currentCyclePosition >= auctionDuration
        ) {
            return false;
        }

        // If we're in a cycle, find where we are in it
        if (timeSinceStart > 0) {
            return currentCyclePosition < auctionDuration;
        }

        return false;
    }
    function isReverseAuctionActive() public view returns (bool) {
        uint256 currentTime = block.timestamp;
        AuctionCycle storage cycle = auctionCycles[orxaAddress][stateToken];
        if (!cycle.isInitialized) {
            return false;
        }
        uint256 fullCycleLength = auctionDuration + auctionInterval;
        uint256 timeSinceStart = currentTime - cycle.firstAuctionStart;
        uint256 currentCycleCount = getCurrentAuctionCycle();
        uint256 currentCycle = (timeSinceStart / fullCycleLength) + 1;
        uint256 auctionEndTime = cycle.firstAuctionStart +
            currentCycle *
            fullCycleLength -
            auctionInterval;
        if (
            reverseAuctionActive[currentCycleCount] &&
            currentTime >= auctionEndTime &&
            currentTime < auctionEndTime + reverseDuration
        ) {
            return true;
        }
        return false;
    }
    function getNextAuctionStart() public view returns (uint256) {
        AuctionCycle memory cycle = auctionCycles[orxaAddress][stateToken];

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
    function getCurrentAuctionCycle() public view returns (uint256) {
        AuctionCycle memory cycle = auctionCycles[orxaAddress][stateToken];
        if (!cycle.isInitialized) return 0;

        uint256 timeSinceStart = block.timestamp - cycle.firstAuctionStart;
        uint256 fullCycleLength = auctionDuration + auctionInterval;
        return timeSinceStart / fullCycleLength;
    }

    function calculateAuctionEligibleAmount() public view returns (uint256) {
        uint256 currentCycle = getCurrentAuctionCycle();
        if (currentCycle > 100) {
            currentCycle = 100; // Cap the cycle to 100 to prevent underflow
        }
        uint256 davbalance = dav.getUserMintedAmount(msg.sender);
        bool isReverse = isReverseAuctionActive();
        if (davbalance == 0) {
            return 0;
        }
        uint256 firstCal = (orxa.getMax_supply() * percentage) / 100 ether;
        uint256 secondCalWithDavMax = (firstCal / 5000000) * davbalance;
        uint256 baseAmount = isReverse
            ? secondCalWithDavMax * 2
            : secondCalWithDavMax;

        if (currentCycle > 0) {
            uint256 decrementFactor = 100 - currentCycle; // Each cycle decreases amount by 1%
            return (baseAmount * decrementFactor) / 100;
        }
        return baseAmount;
    }
    function getSwapAmounts(
        uint256 _amountIn,
        uint256 _amountOut
    ) public pure returns (uint256 newAmountIn, uint256 newAmountOut) {
        uint256 tempAmountOut = _amountIn;

        newAmountIn = _amountOut;

        newAmountOut = tempAmountOut;

        return (newAmountIn, newAmountOut);
    }
    function getOutPutAmount() public view returns (uint256) {
        /**
         * @dev Retrieves the current price ratio of ORXA to PSTATE from the liquidity pool.
         * This ratio determines the value of 1 ORXA in terms of PSTATE.
         */
        uint256 currentRatio = getRatioPrice();
        // Ensure the ratio is valid (greater than zero) to prevent invalid calculations.
        require(currentRatio > 0, "Invalid ratio");

        uint256 currentRatioNormalized = currentRatio / 1e18;

        /**
         * @dev Fetches the user's minted DAV balance.
         * If the user has no balance, they cannot participate in the auction, so return 0.
         */
        uint256 userBalance = dav.getUserMintedAmount(msg.sender);
        if (userBalance == 0) {
            return 0;
        }

        /**
         * @dev Checks if a reverse auction is currently active.
         * Reverse auctions follow a different calculation logic.
         */
        bool isReverseActive = isReverseAuctionActive();

        /**
         * @dev Determines 1% of the user's eligible auction amount.
         * This value is used to compute the output amount based on the auction type.
         */
        uint256 onePercent = calculateAuctionEligibleAmount();
        require(onePercent > 0, "Invalid one percent balance");

        uint256 multiplications;

        if (isReverseActive) {
            /**
             * @dev Reverse auction calculation:
             * - This DApp **rewards double ORXA in reverse auctions** compared to traditional DEXs.
             * - The goal is to **incentivize STATE burning** by offering **higher rewards**.
             * - Normally, a reverse auction might offer 1 ORXA for (currentRatio * ORXA) STATE.
             * - Here, we **divide the amount by two ** (CurrentRatio * ORXA) / 2) to make it more attractive.
             * - the main goal is to make state value half by current calculation so, it can provide double the orxa amount.
             * - This is a **strategic liquidity incentive** that differentiates this DApp.
             * - on other hand it is burning tokens so, removing from market supply
             * - below is only the outPut amount.
             */
            multiplications = (onePercent * currentRatioNormalized) / 2;
        } else {
            /**
             * @dev Normal auction calculation:
             * - This DApp **rewards double STATE in normal auctions** compared to other DEXs.
             * - The goal is to **encourage users to mint STATE through this platform** rather than competitors.
             * - Normally, swapping 1 ORXA would yield `X` STATE, but here, it **yields 2X STATE**.
             * - This feature **creates a competitive advantage**, making swaps more rewarding on this DApp.
             * - While this increases market fluidity, it **ensures higher participation and engagement**.
             * - on other hand it is burning tokens so, removing from market supply
             *
             * - **There is no risk of vault depletion** because:
             *   - The vault is **managed by governance** to control supply.
             *   - Any imbalances in issuance can be corrected by governance actions.
             *   - The system is designed to handle liquidity fluctuations dynamically.
             */

            multiplications = (onePercent * currentRatioNormalized);
            require(
                multiplications <= type(uint256).max / 2,
                "Multiplication overflow"
            );
            // **give double the amount in normal auction**
            multiplications *= 2;
        }

        return multiplications;
    }

    function getTotalStateBurned() public view returns (uint256) {
        return TotalBurnedStates;
    }
    function getTotalStateBurnedByUser(
        address user
    ) public view returns (uint256) {
        return TotalStateBurnedByUser[user];
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

        AuctionCycle storage cycle = auctionCycles[orxaAddress][stateToken];
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
