// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IBuybackEngine
 * @notice Interface for the BuybackEngine contract that manages token buybacks and price stability
 * @dev Defines functions for revenue collection, buyback execution, and market analysis
 *      The buyback engine is responsible for:
 *      1. Collecting revenue from various protocol sources
 *      2. Executing buybacks based on market conditions
 *      3. Managing price pressure and liquidity
 *      4. Converting between token types (e.g., BERA to IKIGAI)
 */
interface IBuybackEngine {
    /**
     * @notice Collects revenue from various sources
     * @param source Identifier for the revenue source (e.g., "MINT_FEES", "TRADING_FEES")
     * @param amount Amount of tokens collected
     * @dev Revenue is tracked per source and partially allocated to buybacks
     */
    function collectRevenue(bytes32 source, uint256 amount) external;
    
    /**
     * @notice Executes a buyback operation based on current market conditions
     * @dev Buys tokens from the market using collected revenue and burns a portion
     *      The remaining portion is allocated to the rewards pool
     * @return amountBought The amount of tokens purchased
     * @return amountBurned The amount of tokens burned
     * @return amountToRewards The amount of tokens sent to rewards
     */
    function executeBuyback() external returns (uint256 amountBought, uint256 amountBurned, uint256 amountToRewards);
    
    /**
     * @notice Executes a buyback with explicit slippage protection
     * @param maxSlippageBps Maximum acceptable slippage in basis points (e.g., 100 = 1%)
     * @return amountBought The amount of tokens purchased
     * @return amountBurned The amount of tokens burned
     * @return amountToRewards The amount of tokens sent to rewards
     * @dev Allows caller to specify maximum acceptable slippage, reverts if exceeded
     */
    function executeBuybackWithSlippage(uint256 maxSlippageBps) external returns (
        uint256 amountBought,
        uint256 amountBurned,
        uint256 amountToRewards
    );
    
    /**
     * @notice Calculates the current buyback pressure based on price
     * @param currentPrice Current token price
     * @return Buyback pressure as a percentage (basis points)
     * @dev Higher pressure means more aggressive buybacks
     */
    function calculatePressure(uint256 currentPrice) external view returns (uint256);
    
    /**
     * @notice Gets the current token price from primary price feed
     * @return Current price with 8 decimals
     */
    function getCurrentPrice() external view returns (uint256);
    
    /**
     * @notice Gets the current token price from multiple oracles and returns a safe value
     * @return price Aggregated price with 8 decimals
     * @return confidence Confidence level in the price (basis points, 10000 = 100%)
     * @dev Aggregates prices from multiple sources for improved reliability
     */
    function getAggregatedPrice() external view returns (uint256 price, uint256 confidence);
    
    /**
     * @notice Gets the bull market price threshold
     * @return Price threshold with 8 decimals
     * @dev Above this threshold, buyback pressure is reduced
     */
    function BULL_PRICE_THRESHOLD() external view returns (uint256);
    
    /**
     * @notice Executes an emergency buyback
     * @dev Can be triggered in extreme market conditions
     *      May bypass certain checks to ensure quick execution
     */
    function emergencyBuyback() external;
    
    /**
     * @notice Analyzes liquidity depth at multiple price levels
     * @param amount Amount of stablecoin to analyze
     * @return depths Array of liquidity depth data
     * @dev Used to determine optimal buyback size
     */
    function analyzeLiquidityDepth(uint256 amount) external view returns (
        LiquidityDepth[] memory depths
    );
    
    /**
     * @notice Gets detailed liquidity analysis
     * @return totalDepth Total liquidity depth in the stablecoin asset
     * @return optimalExecutionSize Recommended maximum trade size for minimal impact
     * @return averageImpact Average price impact across depths (basis points)
     * @dev Provides key metrics for optimizing buyback execution
     */
    function getLiquidityAnalysis() external view returns (
        uint256 totalDepth,
        uint256 optimalExecutionSize,
        uint256 averageImpact
    );
    
    /**
     * @notice Gets the minimum required liquidity based on market cap
     * @return Minimum liquidity amount
     * @dev Used to ensure sufficient market depth before buybacks
     */
    function getMinimumLiquidity() external view returns (uint256);
    
    /**
     * @notice Checks if emergency mode is active
     * @return Emergency mode status
     * @dev In emergency mode, certain restrictions may be bypassed
     */
    function emergencyMode() external view returns (bool);
    
    /**
     * @notice Converts BERA amount to equivalent IKIGAI tokens
     * @param beraAmount Amount of BERA tokens to convert
     * @return ikigaiAmount Equivalent amount of IKIGAI tokens
     * @dev Used by GenesisNFT to calculate rewards
     */
    function getIkigaiAmountForBera(uint256 beraAmount) external view returns (uint256 ikigaiAmount);
    
    /**
     * @notice Converts IKIGAI amount to equivalent BERA tokens
     * @param ikigaiAmount Amount of IKIGAI tokens to convert
     * @return beraAmount Equivalent amount of BERA tokens
     * @dev Reverse conversion function for token exchanges
     */
    function getBeraAmountForIkigai(uint256 ikigaiAmount) external view returns (uint256 beraAmount);
    
    /**
     * @notice Swaps a token for BERA through optimal routing
     * @param token Address of the token to swap
     * @param amount Amount of token to swap
     * @return beraAmount Amount of BERA received
     * @dev Used for multi-token support in payment systems
     */
    function swapTokenForBera(address token, uint256 amount) external returns (uint256 beraAmount);
    
    /**
     * @notice Structure for liquidity depth analysis
     * @dev Contains data about liquidity at specific price points
     */
    struct LiquidityDepth {
        uint256 price;      // Price level
        uint256 volume;     // Available volume at this level
        uint256 impact;     // Price impact in basis points (100 = 1%)
        bool sufficient;    // Whether liquidity is sufficient at this level
    }

    /**
     * @notice Structure for price threshold configuration
     * @dev Defines buyback behavior at specific price levels
     */
    struct PriceThreshold {
        uint256 price;          // Price threshold
        uint256 pressureLevel;  // Buyback pressure at this threshold
        bool active;            // Whether this threshold is active
    }

    /**
     * @notice Structure for revenue stream tracking
     * @dev Tracks revenue from different sources and allocations
     */
    struct RevenueStream {
        uint256 totalCollected;     // Total revenue collected
        uint256 lastUpdate;         // Last update timestamp
        uint256 buybackAllocation;  // Amount allocated to buybacks
    }

    /**
     * @notice Structure for rate limiting configuration
     * @dev Controls buyback frequency and size
     */
    struct RateLimit {
        uint256 maxAmountPerPeriod;    // Maximum buyback amount per period
        uint256 periodDuration;        // Duration of the rate limiting period
        uint256 currentPeriodStart;    // Start timestamp of current period
        uint256 amountInCurrentPeriod; // Amount bought back in current period
        bool enabled;                  // Whether rate limiting is enabled
    }

    /**
     * @notice Updates price threshold configuration
     * @param level Threshold level to update
     * @param price New price threshold
     * @param pressureLevel New pressure level
     * @param active Whether threshold is active
     * @dev Controls buyback aggressiveness at different price points
     */
    function updatePriceThreshold(
        uint256 level,
        uint256 price,
        uint256 pressureLevel,
        bool active
    ) external;

    /**
     * @notice Gets revenue stream information
     * @param source Revenue source identifier
     * @return totalCollected Total revenue collected
     * @return lastUpdate Last update timestamp
     * @return buybackAllocation Amount allocated to buybacks
     * @dev Provides transparency into revenue collection and allocation
     */
    function getRevenueStream(bytes32 source) external view returns (
        uint256 totalCollected,
        uint256 lastUpdate,
        uint256 buybackAllocation
    );

    /**
     * @notice Gets all price thresholds
     * @return An array of price thresholds
     * @dev Used for UI display and configuration verification
     */
    function getPriceThresholds() external view returns (PriceThreshold[] memory);

    /**
     * @notice Gets the current rate limit configuration and status
     * @return Configuration and status of the rate limit
     * @dev Used to monitor buyback restrictions
     */
    function getRateLimit() external view returns (RateLimit memory);

    /**
     * @notice Updates rate limit configuration
     * @param maxAmountPerPeriod Maximum buyback amount per period
     * @param periodDuration Duration of the rate limiting period in seconds
     * @param enabled Whether rate limiting is enabled
     * @dev Protects against excessive buybacks in short time periods
     */
    function updateRateLimit(
        uint256 maxAmountPerPeriod,
        uint256 periodDuration,
        bool enabled
    ) external;

    /**
     * @notice Pauses buyback operations
     * @dev Used during maintenance or abnormal market conditions
     */
    function pause() external;

    /**
     * @notice Resumes buyback operations
     * @dev Re-enables buybacks after maintenance or market stabilization
     */
    function unpause() external;

    /**
     * @notice Adds a new price oracle
     * @param oracle Address of the oracle
     * @param weight Weight of the oracle in aggregation (basis points)
     * @dev Enhances price reliability through multiple sources
     */
    function addPriceOracle(address oracle, uint256 weight) external;

    /**
     * @notice Removes a price oracle
     * @param oracle Address of the oracle to remove
     * @dev Used when an oracle becomes unreliable
     */
    function removePriceOracle(address oracle) external;

    /**
     * @notice Calculates the optimal buyback amount based on current conditions
     * @param availableAmount Amount available for buyback
     * @return optimalAmount The recommended amount to use for buyback
     * @dev Balances between impact, depth, and rate limits
     */
    function calculateOptimalBuyback(uint256 availableAmount) external view returns (uint256 optimalAmount);
    
    /**
     * @notice Checks if a buyback of the given amount would exceed price impact limits
     * @param amount Amount to check
     * @return safe Whether the buyback is considered safe
     * @dev Used to prevent excessive market impact
     */
    function checkPriceImpact(uint256 amount) external view returns (bool safe);

    /**
     * @notice Gets the current price impact for a given buyback amount
     * @param amount Buyback amount to check
     * @return impact Price impact in basis points (100 = 1%)
     * @dev More precise than the binary safe/unsafe check
     */
    function getPriceImpact(uint256 amount) external view returns (uint256 impact);

    // Events
    /**
     * @notice Emitted when a buyback is executed
     * @param amount Amount of stablecoin used for buyback
     * @param tokensBought Amount of tokens purchased
     * @param tokensBurned Amount of tokens burned
     * @param tokensToRewards Amount of tokens sent to rewards
     */
    event BuybackExecuted(
        uint256 amount,
        uint256 tokensBought,
        uint256 tokensBurned,
        uint256 tokensToRewards
    );

    /**
     * @notice Emitted when revenue is collected
     * @param source Revenue source identifier
     * @param amount Amount collected
     * @param buybackAllocation Amount allocated to buybacks
     */
    event RevenueCollected(
        bytes32 indexed source,
        uint256 amount,
        uint256 buybackAllocation
    );

    /**
     * @notice Emitted when a price threshold is updated
     * @param level Threshold level
     * @param price New price
     * @param pressureLevel New pressure level
     */
    event PriceThresholdUpdated(
        uint256 indexed level,
        uint256 price,
        uint256 pressureLevel
    );

    /**
     * @notice Emitted when the pressure system is updated
     * @param baseLevel Base pressure level
     * @param currentPressure Current calculated pressure
     */
    event PressureSystemUpdated(
        uint256 baseLevel,
        uint256 currentPressure
    );

    /**
     * @notice Emitted when rate limits are updated
     * @param maxAmount Maximum amount per period
     * @param periodDuration Period duration in seconds
     * @param enabled Whether rate limiting is enabled
     */
    event RateLimitUpdated(
        uint256 maxAmount,
        uint256 periodDuration,
        bool enabled
    );

    /**
     * @notice Emitted when a price oracle is added or removed
     * @param oracle Oracle address
     * @param weight Oracle weight (0 for removal)
     */
    event PriceOracleUpdated(
        address indexed oracle,
        uint256 weight
    );

    /**
     * @notice Emitted when a token swap occurs
     * @param fromToken Source token
     * @param toToken Destination token
     * @param amountIn Amount input
     * @param amountOut Amount received
     */
    event TokenSwapped(
        address indexed fromToken,
        address indexed toToken,
        uint256 amountIn,
        uint256 amountOut
    );
} 