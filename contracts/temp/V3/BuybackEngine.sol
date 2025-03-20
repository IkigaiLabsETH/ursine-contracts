// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./interfaces/IBuybackEngine.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Factory.sol";

/**
 * @title BuybackEngine
 * @notice Manages automated buybacks, revenue streams, and token burns for Ikigai V2
 * @dev Implements dynamic pressure system and strategic allocation with Uniswap V2 integration
 */
contract BuybackEngine is IBuybackEngine, ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant REVENUE_SOURCE_ROLE = keccak256("REVENUE_SOURCE_ROLE");

    // Token references
    IERC20 public immutable ikigaiToken;
    IERC20 public immutable stablecoin;
    AggregatorV3Interface public priceFeed;

    // Uniswap integration
    IUniswapV2Router02 public immutable uniswapRouter;
    address public immutable uniswapPair;
    uint256 public constant SLIPPAGE_TOLERANCE = 50; // 0.5%

    // Updated pressure system parameters
    uint256 public constant BASE_PRESSURE = 4000;        // 40% base buyback pressure
    uint256 public constant MAX_PRESSURE = 7000;         // 70% max buyback pressure
    uint256 public constant PRESSURE_INCREASE_RATE = 500; // 5% increase per level
    uint256 public constant PRESSURE_LEVELS = 6;         // Number of pressure levels
    uint256 public constant RESERVE_RATIO = 3000;        // 30% reserve buffer

    // Updated revenue distribution
    uint256 public constant NFT_SALES_BUYBACK = 3500;    // 35% of NFT sales
    uint256 public constant PLATFORM_FEES_BUYBACK = 3000; // 30% of platform fees
    uint256 public constant TREASURY_YIELD_BUYBACK = 2500;// 25% of treasury yield

    // Updated distribution ratios
    uint256 public constant BURN_RATIO = 9000;           // 90% of buybacks are burned
    uint256 public constant REWARD_POOL_RATIO = 1000;    // 10% to rewards pool

    // Updated safety parameters
    uint256 public constant MIN_BUYBACK_AMOUNT = 100e18; // Minimum buyback size
    uint256 public constant BUYBACK_COOLDOWN = 12 hours;   // 12 hour cooldown
    uint256 public constant EMERGENCY_THRESHOLD = 2000;   // 20% price drop trigger
    uint256 public constant MIN_LIQUIDITY_RATIO = 100;   // 1% of market cap
    uint256 public constant PRICE_DECIMALS = 8;          // Chainlink price decimals

    // New liquidity protection parameters
    uint256 public constant DEPTH_ANALYSIS_STEPS = 5;
    uint256 public constant MIN_LIQUIDITY_DEPTH = 1000e18; // $1M minimum depth
    uint256 public constant MAX_DEPTH_IMPACT = 200;      // 2% max impact per level
    uint256 public constant DEPTH_THRESHOLD = 5000;      // 50% minimum depth ratio

    // Add bull market reserve
    uint256 public constant BULL_MARKET_RESERVE = 1000;  // 10% for bull market buybacks
    uint256 public constant BULL_PRICE_THRESHOLD = 1e8;  // $1.00 activation price

    // Revenue tracking
    struct RevenueStream {
        uint256 totalCollected;
        uint256 lastUpdate;
        uint256 buybackAllocation;
    }
    mapping(bytes32 => RevenueStream) public revenueStreams;

    struct LiquidityDepth {
        uint256 price;
        uint256 volume;
        uint256 impact;
        bool sufficient;
    }

    // Events
    event BuybackExecuted(
        uint256 amount,
        uint256 tokensBought,
        uint256 tokensBurned,
        uint256 tokensToRewards
    );
    event RevenueCollected(
        bytes32 indexed source,
        uint256 amount,
        uint256 buybackAllocation
    );
    event PriceThresholdUpdated(
        uint256 indexed level,
        uint256 price,
        uint256 pressureLevel
    );
    event PressureSystemUpdated(
        uint256 baseLevel,
        uint256 currentPressure
    );
    event EmergencyModeChanged(bool mode);
    event TokensRecovered(address token, uint256 amount);
    event PriceRecorded(uint256 price, uint256 timestamp);

    // Add missing getPreviousPrice function
    uint256 private lastRecordedPrice;
    uint256 private lastPriceUpdateTime;

    // Record price history for emergency detection
    function recordPrice() public {
        if (block.timestamp >= lastPriceUpdateTime + 1 hours) {
            lastRecordedPrice = getCurrentPrice();
            lastPriceUpdateTime = block.timestamp;
        }
    }

    function getPreviousPrice() public view returns (uint256) {
        require(lastRecordedPrice > 0, "No price history");
        return lastRecordedPrice;
    }

    // Add circuit breaker
    bool public emergencyMode = false;

    function setEmergencyMode(bool _mode) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        emergencyMode = _mode;
        if (_mode) {
            _pause();
        } else {
            _unpause();
        }
    }

    // Add recovery function
    function recoverTokens(address token, uint256 amount) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(emergencyMode, "Not in emergency mode");
        
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    constructor(
        address _ikigaiToken,
        address _stablecoin,
        address _priceFeed,
        address _uniswapRouter,
        address _admin
    ) {
        ikigaiToken = IERC20(_ikigaiToken);
        stablecoin = IERC20(_stablecoin);
        priceFeed = AggregatorV3Interface(_priceFeed);
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);

        // Create or get Uniswap pair
        address factory = uniswapRouter.factory();
        uniswapPair = IUniswapV2Factory(factory).getPair(_ikigaiToken, _stablecoin);
        require(uniswapPair != address(0), "Pair does not exist");

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(OPERATOR_ROLE, _admin);

        // Initialize price thresholds
        priceThresholds.push(PriceThreshold({
            price: 0.5e8,  // $0.50
            pressureLevel: 1,
            active: true
        }));
        priceThresholds.push(PriceThreshold({
            price: 0.4e8,  // $0.40
            pressureLevel: 2,
            active: true
        }));
        priceThresholds.push(PriceThreshold({
            price: 0.3e8,  // $0.30
            pressureLevel: 3,
            active: true
        }));
        priceThresholds.push(PriceThreshold({
            price: 0.2e8,  // $0.20
            pressureLevel: 4,
            active: true
        }));
        priceThresholds.push(PriceThreshold({
            price: 0.1e8,  // $0.10
            pressureLevel: 5,
            active: true
        }));
    }

    /**
     * @notice Collects revenue from various sources and allocates to buyback pool
     * @param source Identifier for the revenue source
     * @param amount Amount of stablecoin collected
     */
    function collectRevenue(bytes32 source, uint256 amount) external override nonReentrant whenNotPaused {
        require(hasRole(REVENUE_SOURCE_ROLE, msg.sender), "Not authorized");
        require(amount > 0, "Zero amount");
        require(source != bytes32(0), "Invalid source");
        
        // Record price for emergency detection
        recordPrice();
        
        RevenueStream storage stream = revenueStreams[source];
        uint256 buybackShare;

        // Calculate buyback allocation based on source
        if (source == keccak256("NFT_SALES")) {
            buybackShare = (amount * NFT_SALES_BUYBACK) / 10000;
        } else if (source == keccak256("PLATFORM_FEES")) {
            buybackShare = (amount * PLATFORM_FEES_BUYBACK) / 10000;
        } else if (source == keccak256("TREASURY_YIELD")) {
            buybackShare = (amount * TREASURY_YIELD_BUYBACK) / 10000;
        } else {
            revert("Invalid revenue source");
        }

        // Transfer revenue
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        // Update stream stats
        stream.totalCollected += amount;
        stream.lastUpdate = block.timestamp;
        stream.buybackAllocation += buybackShare;
        accumulatedFunds += buybackShare;

        emit RevenueCollected(source, amount, buybackShare);

        // Try to execute buyback if enough funds
        if (accumulatedFunds >= MIN_BUYBACK_AMOUNT) {
            _executeBuyback();
        }
    }

    /**
     * @notice Executes buyback based on current market conditions and pressure system
     */
    function executeBuyback() external nonReentrant whenNotPaused {
        require(hasRole(OPERATOR_ROLE, msg.sender) || msg.sender == address(this), "Unauthorized");
        require(block.timestamp >= lastBuybackTime + BUYBACK_COOLDOWN, "Cooldown active");
        
        uint256 currentPrice = getCurrentPrice();
        bool isBullMarket = currentPrice >= BULL_PRICE_THRESHOLD;
        
        // Use bull market reserve if in bull market
        if (isBullMarket) {
            uint256 bullMarketFunds = (accumulatedFunds * BULL_MARKET_RESERVE) / 10000;
            if (bullMarketFunds >= MIN_BUYBACK_AMOUNT) {
                _executeBuybackWithAmount(bullMarketFunds);
            }
        } else {
            _executeBuyback();
        }
    }

    /**
     * @notice Internal function to execute buyback
     */
    function _executeBuyback() internal override {
        uint256 amount = accumulatedFunds;
        uint256 currentPrice = getCurrentPrice();
        uint256 pressure = calculatePressure(currentPrice);
        
        // Calculate initial buyback amount based on pressure
        uint256 buybackAmount = (amount * pressure) / 10000;
        
        // Optimize amount based on liquidity depth
        uint256 optimalAmount = calculateOptimalBuyback(buybackAmount);
        require(optimalAmount > 0, "Insufficient liquidity depth");
        
        // Adjust buyback amount if needed
        buybackAmount = optimalAmount < buybackAmount ? optimalAmount : buybackAmount;
        
        // Execute optimized buyback
        uint256 tokensBought = executeMarketBuy(buybackAmount);
        
        // Distribute bought tokens
        uint256 tokensToBurn = (tokensBought * BURN_RATIO) / 10000;
        uint256 tokensToRewards = tokensBought - tokensToBurn;
        
        // Burn tokens
        ikigaiToken.transfer(address(0xdead), tokensToBurn);
        
        // Send to rewards pool
        address rewardsPool = getRewardsPool();
        ikigaiToken.transfer(rewardsPool, tokensToRewards);
        
        // Update state
        accumulatedFunds -= buybackAmount;
        lastBuybackTime = block.timestamp;
        
        emit BuybackExecuted(
            buybackAmount,
            tokensBought,
            tokensToBurn,
            tokensToRewards
        );
    }

    /**
     * @notice Calculates current buyback pressure based on price
     * @param currentPrice Current token price
     * @return uint256 Pressure level (5000-8000 = 50-80%)
     */
    function calculatePressure(uint256 currentPrice) public view returns (uint256) {
        uint256 pressureLevel = BASE_PRESSURE;
        
        for (uint i = 0; i < priceThresholds.length; i++) {
            if (priceThresholds[i].active && 
                currentPrice <= priceThresholds[i].price) {
                pressureLevel += PRESSURE_INCREASE_RATE * priceThresholds[i].pressureLevel;
            }
        }
        
        return pressureLevel > MAX_PRESSURE ? MAX_PRESSURE : pressureLevel;
    }

    /**
     * @notice Gets current token price from Chainlink
     */
    function getCurrentPrice() public view returns (uint256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        return uint256(price);
    }

    /**
     * @notice Executes market buy order through Uniswap V2
     * @param amount Amount of stablecoin to spend
     * @return uint256 Amount of tokens bought
     */
    function executeMarketBuy(uint256 amount) internal returns (uint256) {
        require(amount > 0, "Invalid amount");

        // Approve router to spend stablecoin
        stablecoin.safeApprove(address(uniswapRouter), amount);

        // Calculate minimum tokens to receive based on current price and slippage
        uint256 amountOutMin = calculateMinimumTokensOut(amount);

        // Prepare swap path
        address[] memory path = new address[](2);
        path[0] = address(stablecoin);
        path[1] = address(ikigaiToken);

        // Execute swap
        uint256[] memory amounts = uniswapRouter.swapExactTokensForTokens(
            amount,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );

        // Return actual tokens received
        return amounts[1];
    }

    /**
     * @notice Calculates minimum tokens to receive based on current price and slippage
     * @param amountIn Amount of stablecoin being spent
     * @return uint256 Minimum tokens to receive
     */
    function calculateMinimumTokensOut(uint256 amountIn) public view returns (uint256) {
        // Get current price from Chainlink
        uint256 currentPrice = getCurrentPrice();
        
        // Calculate expected output at current price
        uint256 expectedOut = (amountIn * 1e18) / currentPrice;
        
        // Apply slippage tolerance
        return (expectedOut * (10000 - SLIPPAGE_TOLERANCE)) / 10000;
    }

    /**
     * @notice Gets the current reserves of the Uniswap pair
     * @return reserve0 Reserve of token0
     * @return reserve1 Reserve of token1
     */
    function getUniswapReserves() public view returns (uint256 reserve0, uint256 reserve1) {
        (uint112 _reserve0, uint112 _reserve1,) = IUniswapV2Pair(uniswapPair).getReserves();
        return (uint256(_reserve0), uint256(_reserve1));
    }

    /**
     * @notice Analyzes liquidity depth at multiple price levels
     * @param amount Amount of stablecoin to analyze
     * @return depths Array of liquidity depth data
     */
    function analyzeLiquidityDepth(uint256 amount) public view returns (LiquidityDepth[] memory) {
        LiquidityDepth[] memory depths = new LiquidityDepth[](DEPTH_ANALYSIS_STEPS);
        
        // Get initial reserves
        (uint256 reserve0, uint256 reserve1) = getUniswapReserves();
        uint256 stepSize = amount / DEPTH_ANALYSIS_STEPS;
        
        // Analyze each depth level
        for (uint i = 0; i < DEPTH_ANALYSIS_STEPS; i++) {
            uint256 depthAmount = stepSize * (i + 1);
            
            // Calculate constant product price impact
            uint256 priceAfter = (reserve0 * reserve1) / (reserve0 + depthAmount);
            uint256 priceImpact = ((reserve1 - priceAfter) * 10000) / reserve1;
            
            // Calculate effective price at this depth
            uint256 effectivePrice = (reserve1 * 1e18) / (reserve0 + depthAmount);
            
            // Check if depth is sufficient
            bool isSufficient = reserve0 >= MIN_LIQUIDITY_DEPTH &&
                              priceImpact <= MAX_DEPTH_IMPACT &&
                              (reserve0 * 10000 / (reserve0 + depthAmount)) >= DEPTH_THRESHOLD;
            
            depths[i] = LiquidityDepth({
                price: effectivePrice,
                volume: depthAmount,
                impact: priceImpact,
                sufficient: isSufficient
            });
        }
        
        return depths;
    }

    /**
     * @notice Calculates optimal buyback size based on liquidity depth
     * @param amount Proposed buyback amount
     * @return optimalAmount Adjusted buyback amount
     */
    function calculateOptimalBuyback(uint256 amount) public view returns (uint256) {
        LiquidityDepth[] memory depths = analyzeLiquidityDepth(amount);
        
        // Find optimal execution point
        uint256 optimalAmount = 0;
        for (uint i = 0; i < depths.length; i++) {
            if (!depths[i].sufficient) {
                break;
            }
            optimalAmount = depths[i].volume;
        }
        
        return optimalAmount;
    }

    /**
     * @notice Enhanced price impact check with depth analysis
     * @param amount Amount of stablecoin to spend
     * @return bool Whether the trade can be executed safely
     */
    function checkPriceImpact(uint256 amount) public view returns (bool) {
        (uint256 reserve0, uint256 reserve1) = getUniswapReserves();
        
        // Basic price impact check
        uint256 priceImpact = (amount * 10000) / reserve0;
        if (priceImpact > 300) { // 3% max impact
            return false;
        }
        
        // Depth analysis check
        LiquidityDepth[] memory depths = analyzeLiquidityDepth(amount);
        
        // Require sufficient depth for entire amount
        for (uint i = 0; i < depths.length; i++) {
            if (!depths[i].sufficient) {
                return false;
            }
        }
        
        return true;
    }

    /**
     * @notice Updates price thresholds for the pressure system
     * @param level Threshold level to update
     * @param price New price threshold
     * @param pressureLevel New pressure level
     * @param active Whether the threshold is active
     */
    function updatePriceThreshold(
        uint256 level,
        uint256 price,
        uint256 pressureLevel,
        bool active
    ) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(level < priceThresholds.length, "Invalid level");
        require(pressureLevel <= PRESSURE_LEVELS, "Invalid pressure");

        priceThresholds[level] = PriceThreshold({
            price: price,
            pressureLevel: pressureLevel,
            active: active
        });

        emit PriceThresholdUpdated(level, price, pressureLevel);
    }

    // Emergency functions
    function pause() external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Not operator");
        _pause();
    }

    function unpause() external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Not operator");
        _unpause();
    }

    // View functions
    function getRevenueStream(bytes32 source) external view returns (
        uint256 totalCollected,
        uint256 lastUpdate,
        uint256 buybackAllocation
    ) {
        RevenueStream memory stream = revenueStreams[source];
        return (
            stream.totalCollected,
            stream.lastUpdate,
            stream.buybackAllocation
        );
    }

    function getPriceThresholds() external view returns (PriceThreshold[] memory) {
        return priceThresholds;
    }

    function getRewardsPool() internal view returns (address) {
        // Implement rewards pool address retrieval
        return address(0x123); // Placeholder
    }

    /**
     * @notice Gets detailed liquidity analysis
     * @return totalDepth Total liquidity depth
     * @return optimalExecutionSize Recommended max trade size
     * @return averageImpact Average price impact across depths
     */
    function getLiquidityAnalysis() external view returns (
        uint256 totalDepth,
        uint256 optimalExecutionSize,
        uint256 averageImpact
    ) {
        (uint256 reserve0, uint256 reserve1) = getUniswapReserves();
        totalDepth = reserve0;
        
        LiquidityDepth[] memory depths = analyzeLiquidityDepth(reserve0 / 2);
        
        uint256 totalImpact;
        for (uint i = 0; i < depths.length; i++) {
            if (depths[i].sufficient) {
                optimalExecutionSize = depths[i].volume;
                totalImpact += depths[i].impact;
            }
        }
        
        averageImpact = totalImpact / depths.length;
        
        return (totalDepth, optimalExecutionSize, averageImpact);
    }

    // Add adaptive liquidity check
    function getMinimumLiquidity() public view returns (uint256) {
        uint256 marketCap = getCurrentPrice() * totalSupply();
        return (marketCap * MIN_LIQUIDITY_RATIO) / 10000;
    }

    // Emergency buyback function needs to be added
    function emergencyBuyback() external nonReentrant whenNotPaused {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Caller is not operator");
        
        // Get current price
        uint256 currentPrice = getCurrentPrice();
        uint256 previousPrice = getPreviousPrice(); // Need to implement this
        
        // Check if price dropped significantly
        bool isPriceDropEmergency = previousPrice > 0 && 
            ((previousPrice - currentPrice) * 10000 / previousPrice) >= EMERGENCY_THRESHOLD;
        
        require(isPriceDropEmergency, "No emergency condition");
        
        // Skip cooldown check for emergency
        _executeBuyback();
    }

    // Update the liquidity check to use adaptive minimum
    function checkLiquidity(uint256 amount) public view returns (bool) {
        (uint256 reserve0, uint256 reserve1) = getUniswapReserves();
        uint256 minRequired = getMinimumLiquidity();
        
        return reserve0 >= minRequired && 
               calculatePriceImpact(amount) <= MAX_DEPTH_IMPACT;
    }

    // Missing function to get total supply
    function totalSupply() public view returns (uint256) {
        return IERC20(address(ikigaiToken)).totalSupply();
    }

    // Add reentrancy guard to all external functions
    function updatePriceThresholds(uint256[] calldata prices, uint256[] calldata levels) external nonReentrant {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Not authorized");
        // Function logic...
    }

    // Add to BuybackEngine.sol
    uint256[] public longTermPriceHistory; // 90-day price history
    uint256 public constant LONG_TERM_PRICE_INTERVAL = 1 days;
    uint256 public lastLongTermPriceUpdate;

    function updateLongTermPrice() external {
        require(block.timestamp >= lastLongTermPriceUpdate + LONG_TERM_PRICE_INTERVAL, "Too soon");
        
        // Get current price
        (uint256 price, ) = getLatestPrice();
        
        // Add to history
        longTermPriceHistory.push(price);
        
        // Keep only last 90 days
        if (longTermPriceHistory.length > 90) {
            // Remove oldest price
            for (uint i = 0; i < longTermPriceHistory.length - 90; i++) {
                longTermPriceHistory[i] = longTermPriceHistory[i + 1];
            }
            longTermPriceHistory.pop();
        }
        
        lastLongTermPriceUpdate = block.timestamp;
    }

    function getLongTermAveragePrice() public view returns (uint256) {
        if (longTermPriceHistory.length == 0) return 0;
        
        uint256 total = 0;
        for (uint256 i = 0; i < longTermPriceHistory.length; i++) {
            total += longTermPriceHistory[i];
        }
        
        return total / longTermPriceHistory.length;
    }

    // Enhanced buyback calculation using multi-timeframe analysis
    function calculateOptimalBuybackAmount() public view returns (uint256) {
        uint256 currentPrice = getCurrentPrice();
        uint256 thirtyDayAvg = getThirtyDayAveragePrice();
        uint256 ninetyDayAvg = getLongTermAveragePrice();
        
        // Calculate short-term deviation
        uint256 shortTermDeviation = 0;
        if (currentPrice < thirtyDayAvg) {
            shortTermDeviation = ((thirtyDayAvg - currentPrice) * 10000) / thirtyDayAvg;
        }
        
        // Calculate long-term trend
        bool isLongTermUptrend = ninetyDayAvg < thirtyDayAvg;
        
        // Adjust multiplier based on both timeframes
        uint256 multiplier = 10000; // Base 100%
        
        if (isLongTermUptrend) {
            // In uptrend, be more conservative with buybacks
            multiplier += (shortTermDeviation * 2); // +0-20% based on deviation
        } else {
            // In downtrend, be more aggressive with buybacks
            multiplier += (shortTermDeviation * 4); // +0-40% based on deviation
        }
        
        // Pause buybacks during extreme uptrends
        if (currentPrice > ninetyDayAvg * 120 / 100) {
            return 0; // No buybacks when price > 120% of 90-day avg
        }
        
        return (MIN_BUYBACK_AMOUNT * multiplier) / 10000;
    }
} 