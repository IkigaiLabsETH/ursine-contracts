## Getting Started

Create a project using this example:

```bash
npx thirdweb create --contract --template hardhat-javascript-starter
```

You can start editing the page by modifying `contracts/Contract.sol`.

To add functionality to your contracts, you can use the `@thirdweb-dev/contracts` package which provides base contracts and extensions to inherit. The package is already installed with this project. Head to our [Contracts Extensions Docs](https://portal.thirdweb.com/contractkit) to learn more.

## Building the project

After any changes to the contract, run:

```bash
npm run build
# or
yarn build
```

to compile your contracts. This will also detect the [Contracts Extensions Docs](https://portal.thirdweb.com/contractkit) detected on your contract.

## Deploying Contracts

When you're ready to deploy your contracts, just run one of the following command to deploy you're contracts:

```bash
npm run deploy
# or
yarn deploy
```

> [!IMPORTANT]
> This requires a secret key to make it work. Get your secret key [here](https://thirdweb.com/dashboard/settings/api-keys).
> Pass your secret key as a value after `-k` flag.
> ```bash
> npm run deploy -- -k <your-secret-key>
> # or
> yarn deploy -k <your-secret-key>

## Releasing Contracts

If you want to release a version of your contracts publicly, you can use one of the followings command:

```bash
npm run release
# or
yarn release
```

## Join our Discord!

For any questions, suggestions, join our discord at [https://discord.gg/thirdweb](https://discord.gg/thirdweb).

# Ikigai Buyback Engine

## Overview

The Ikigai Buyback Engine is a sophisticated tokenomics management system designed to provide price stability, manage token supply, and maintain healthy market dynamics for the IKIGAI token ecosystem. It works in conjunction with the GenesisNFT to create a circular economy where fees from NFT minting and other protocol activities fund buybacks and rewards.

## Architecture

The Buyback Engine uses an interface-based design pattern that allows for flexible implementation and future upgrades. The main components include:

### Core Components

1. **Revenue Collection System**
   - Collects revenue from various protocol sources
   - Tracks revenue by source with transparent allocation
   - Maintains a record of all collected funds and their usage

2. **Buyback Execution System**
   - Executes token buybacks based on market conditions
   - Burns a portion of bought tokens to reduce supply
   - Allocates remaining tokens to the rewards pool

3. **Market Analysis System**
   - Monitors token price and market conditions
   - Analyzes liquidity depth across the market
   - Calculates optimal buyback sizes and timing

4. **Price Oracle System**
   - Aggregates price data from multiple sources
   - Provides reliable and manipulation-resistant pricing
   - Enables confidence-weighted price aggregation

5. **Rate Limiting System**
   - Prevents excessive buybacks in short timeframes
   - Protects market stability with configurable limits
   - Tracks buyback frequency and volumes

## Detailed Functionality

### Revenue Management

The Buyback Engine collects revenue from various protocol sources (e.g., NFT minting fees, trading fees, etc.) and allocates it according to predefined ratios:

```solidity
function collectRevenue(bytes32 source, uint256 amount) external;
```

- Each revenue source is tracked separately for transparency
- Revenue allocation between treasury and buybacks is configurable
- Historical revenue data is accessible through query functions:

```solidity
function getRevenueStream(bytes32 source) external view returns (
    uint256 totalCollected,
    uint256 lastUpdate,
    uint256 buybackAllocation
);
```

### Buyback Execution

The engine executes buybacks strategically based on market conditions:

```solidity
function executeBuyback() external returns (
    uint256 amountBought, 
    uint256 amountBurned, 
    uint256 amountToRewards
);
```

It includes advanced protection mechanisms:

```solidity
function executeBuybackWithSlippage(uint256 maxSlippageBps) external returns (...);
```

- Slippage protection to prevent adverse market impact
- Variable execution sizes based on liquidity conditions
- Configurable burn/reward allocation ratio

### Pressure System

The engine uses a dynamic "pressure" system to determine buyback aggressiveness:

```solidity
function calculatePressure(uint256 currentPrice) external view returns (uint256);
```

- Lower token prices increase buyback pressure
- Multiple configurable price thresholds define behavior
- Bull market conditions reduce pressure to conserve resources

### Market Analysis

Sophisticated market analysis ensures optimal execution:

```solidity
function analyzeLiquidityDepth(uint256 amount) external view returns (LiquidityDepth[] memory);
function getLiquidityAnalysis() external view returns (...);
```

- Analyzes liquidity at multiple price levels
- Calculates optimal execution sizes to minimize impact
- Monitors market depth to ensure sufficient liquidity

### Price Impact Protection

The engine includes multiple safety mechanisms:

```solidity
function checkPriceImpact(uint256 amount) external view returns (bool);
function getPriceImpact(uint256 amount) external view returns (uint256);
```

- Prevents buybacks that would cause excessive price impact
- Provides detailed impact analysis before execution
- Implements configuralbe impact thresholds

### Rate Limiting

To prevent market manipulation and protect protocol resources:

```solidity
function updateRateLimit(uint256 maxAmountPerPeriod, uint256 periodDuration, bool enabled) external;
```

- Limits the maximum buyback volume in a time period
- Configurable time windows and amount restrictions
- Emergency override for extreme market conditions

### Token Conversion

The engine facilitates token conversion for the GenesisNFT reward system:

```solidity
function getIkigaiAmountForBera(uint256 beraAmount) external view returns (uint256);
function getBeraAmountForIkigai(uint256 ikigaiAmount) external view returns (uint256);
```

- Converts between BERA and IKIGAI tokens
- Used for calculating GenesisNFT rewards
- Ensures fair and transparent conversion rates

### Multi-Token Support

For enhanced flexibility, the engine can work with multiple tokens:

```solidity
function swapTokenForBera(address token, uint256 amount) external returns (uint256);
```

- Supports multiple payment tokens
- Optimal routing for token swaps
- Transparent accounting for all conversions

## Data Structures

### LiquidityDepth

Analyzes market liquidity at specific price points:

```solidity
struct LiquidityDepth {
    uint256 price;      // Price level
    uint256 volume;     // Available volume at this level
    uint256 impact;     // Price impact in basis points (100 = 1%)
    bool sufficient;    // Whether liquidity is sufficient at this level
}
```

### PriceThreshold

Configures buyback behavior at different price levels:

```solidity
struct PriceThreshold {
    uint256 price;          // Price threshold
    uint256 pressureLevel;  // Buyback pressure at this threshold
    bool active;            // Whether this threshold is active
}
```

### RevenueStream

Tracks revenue from different protocol sources:

```solidity
struct RevenueStream {
    uint256 totalCollected;     // Total revenue collected
    uint256 lastUpdate;         // Last update timestamp
    uint256 buybackAllocation;  // Amount allocated to buybacks
}
```

### RateLimit

Controls buyback frequency and size:

```solidity
struct RateLimit {
    uint256 maxAmountPerPeriod;    // Maximum buyback amount per period
    uint256 periodDuration;        // Duration of the rate limiting period
    uint256 currentPeriodStart;    // Start timestamp of current period
    uint256 amountInCurrentPeriod; // Amount bought back in current period
    bool enabled;                  // Whether rate limiting is enabled
}
```

## Events

The engine emits detailed events for transparency and analytics:

- `BuybackExecuted`: When a buyback operation completes
- `RevenueCollected`: When revenue is collected from a source
- `PriceThresholdUpdated`: When buyback behavior at a price level changes
- `PressureSystemUpdated`: When the pressure system parameters change
- `RateLimitUpdated`: When rate limiting parameters are modified
- `PriceOracleUpdated`: When price oracle sources are added or modified
- `TokenSwapped`: When tokens are converted through the engine

## Safety Mechanisms

### Emergency Controls

For exceptional market conditions:

```solidity
function emergencyBuyback() external;
function emergencyMode() external view returns (bool);
```

- Emergency buyback capability for extreme conditions
- Circuit breaker to halt operations when necessary
- Admin controls for crisis management

### Pause Functionality

Operations can be paused for maintenance or emergency:

```solidity
function pause() external;
function unpause() external;
```

### Oracle Redundancy

Multiple price sources protect against manipulation:

```solidity
function addPriceOracle(address oracle, uint256 weight) external;
function removePriceOracle(address oracle) external;
function getAggregatedPrice() external view returns (uint256 price, uint256 confidence);
```

- Weighted price aggregation from multiple sources
- Confidence scoring for price reliability
- Dynamic oracle management

## Integration with GenesisNFT

The Buyback Engine works closely with the GenesisNFT contract:

1. **Revenue Collection**: GenesisNFT minting fees flow into the Buyback Engine
2. **Token Conversion**: The engine converts BERA to IKIGAI for reward calculations
3. **Reward Distribution**: Tokens bought back are partially allocated to rewards
4. **Tokenomics Management**: The engine helps maintain healthy IKIGAI token economics

## Implementation Best Practices

When implementing the IBuybackEngine interface:

1. **Security First**: Implement comprehensive access controls and security checks
2. **Gas Optimization**: Optimize for gas efficiency, especially in buyback execution
3. **Fail-Safe Defaults**: Use conservative default settings for all parameters
4. **Gradual Parameter Changes**: Make incremental changes to sensitive parameters
5. **Thorough Testing**: Test against all market conditions, including extreme scenarios
6. **Transparent Monitoring**: Implement detailed logging and monitoring
7. **Emergency Planning**: Have clear procedures for emergency situations

## Conclusion

The Ikigai Buyback Engine is a cornerstone of the IKIGAI tokenomics model, providing stability, growth incentives, and sustainable token economics. Through its sophisticated market analysis and buyback execution systems, it helps maintain a healthy token economy while supporting the broader IKIGAI ecosystem.
