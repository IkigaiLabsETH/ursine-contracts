// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IBuybackEngine
 * @notice Interface for the BuybackEngine contract
 * @dev Defines the functions for revenue collection and buyback execution
 */
interface IBuybackEngine {
    /**
     * @notice Collects revenue from various sources
     * @param source Identifier for the revenue source
     * @param amount Amount of tokens collected
     */
    function collectRevenue(bytes32 source, uint256 amount) external;
    
    /**
     * @notice Executes a buyback operation
     */
    function executeBuyback() external;
    
    /**
     * @notice Calculates the current buyback pressure based on price
     * @param currentPrice Current token price
     * @return Buyback pressure as a percentage (basis points)
     */
    function calculatePressure(uint256 currentPrice) external view returns (uint256);
    
    /**
     * @notice Gets the current token price from price feed
     * @return Current price with 8 decimals
     */
    function getCurrentPrice() external view returns (uint256);
    
    /**
     * @notice Gets the bull market price threshold
     * @return Price threshold with 8 decimals
     */
    function BULL_PRICE_THRESHOLD() external view returns (uint256);
    
    /**
     * @notice Executes an emergency buyback
     */
    function emergencyBuyback() external;
    
    /**
     * @notice Analyzes liquidity depth at multiple price levels
     * @param amount Amount of stablecoin to analyze
     * @return depths Array of liquidity depth data
     */
    function analyzeLiquidityDepth(uint256 amount) external view returns (
        LiquidityDepth[] memory
    );
    
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
    );
    
    /**
     * @notice Gets the minimum required liquidity based on market cap
     * @return Minimum liquidity amount
     */
    function getMinimumLiquidity() external view returns (uint256);
    
    /**
     * @notice Checks if emergency mode is active
     * @return Emergency mode status
     */
    function emergencyMode() external view returns (bool);
    
    /**
     * @notice Structure for liquidity depth analysis
     */
    struct LiquidityDepth {
        uint256 price;
        uint256 volume;
        uint256 impact;
        bool sufficient;
    }

    /**
     * @notice Structure for price threshold configuration
     */
    struct PriceThreshold {
        uint256 price;
        uint256 pressureLevel;
        bool active;
    }

    /**
     * @notice Structure for revenue stream tracking
     */
    struct RevenueStream {
        uint256 totalCollected;
        uint256 lastUpdate;
        uint256 buybackAllocation;
    }

    /**
     * @notice Updates price threshold configuration
     * @param level Threshold level to update
     * @param price New price threshold
     * @param pressureLevel New pressure level
     * @param active Whether threshold is active
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
     */
    function getRevenueStream(bytes32 source) external view returns (
        uint256 totalCollected,
        uint256 lastUpdate,
        uint256 buybackAllocation
    );

    /**
     * @notice Gets all price thresholds
     * @return PriceThreshold[] Array of price thresholds
     */
    function getPriceThresholds() external view returns (PriceThreshold[] memory);

    /**
     * @notice Pauses buyback operations
     */
    function pause() external;

    /**
     * @notice Resumes buyback operations
     */
    function unpause() external;

    // Analysis functions
    function calculateOptimalBuyback(uint256 amount) external view returns (uint256);
    function checkPriceImpact(uint256 amount) external view returns (bool);

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
} 