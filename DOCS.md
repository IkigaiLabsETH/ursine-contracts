# GenesisNFT - Upgradeable NFT Contract Implementation

This directory contains an advanced, upgradeable implementation of the GenesisNFT contract using the UUPS (Universal Upgradeable Proxy Standard) pattern. This implementation provides a robust, secure, and flexible NFT contract that accepts BERA for minting and rewards users with IKIGAI tokens.

## Architecture Overview

The upgradeable pattern separates the contract's storage and logic, allowing the logic to be upgraded while preserving the state and contract address.

### Contract Structure

The implementation consists of several contracts with specific responsibilities:

1. **GenesisNFTStorage.sol**: Contains all state variables to ensure proper storage layout for upgrades
2. **GenesisNFTLogic.sol**: Contains the implementation logic for the V1 contract
3. **GenesisNFTProxy.sol**: The proxy contract that delegates calls to the implementation
4. **GenesisNFTDeployer.sol**: Helper contract for encoding initialization data
5. **GenesisNFTLogicV2.sol**: Example V2 implementation with additional features

### Key Features

This implementation includes:

#### Core Functionality
- ERC721 NFT with enumerable and URI storage extensions
- Multiple sale phases (BERA holders, Whitelist, Public)
- BERA payment acceptance with tiered pricing
- IKIGAI token rewards with vesting schedule
- Royalty support via ERC2981

#### Security Enhancements
- Comprehensive role-based access control
- Reentrancy protection on all state-modifying functions
- Circuit breakers for emergency situations
- Rate limiting for claims and minting
- Input validation and error handling

#### Advanced Features
- Delayed metadata reveal functionality
- Treasury management with configurable fee splits
- Conversion of BERA to IKIGAI rewards via buyback engine
- Customizable whitelist tiers
- Multi-token payment support with price multipliers

## Proxy Pattern Implementation

The implementation uses the UUPS (Universal Upgradeable Proxy Standard) pattern:

1. **Storage Contract**: Maintains all storage variables in a consistent layout
2. **Logic Contract**: Contains all implementation logic but no storage definitions
3. **Proxy Contract**: Delegates all calls to the current implementation

This pattern offers several advantages:
- The upgrade mechanism is in the implementation, not the proxy
- Lower deployment and usage gas costs
- More flexibility for complex upgrade patterns

## Access Control System

The contract implements a robust role-based access control system with the following roles:

- `DEFAULT_ADMIN_ROLE`: Can grant and revoke all roles
- `TREASURY_ROLE`: Can update the treasury address
- `WHITELIST_MANAGER_ROLE`: Can update whitelist statuses
- `PRICE_MANAGER_ROLE`: Can update pricing parameters
- `EMERGENCY_ROLE`: Can trigger emergency mode and pausing
- `METADATA_ROLE`: Can update URI information and reveal the collection
- `UPGRADE_ROLE`: Can upgrade the implementation contract

## Vesting and Rewards

The contract includes a sophisticated vesting mechanism for IKIGAI rewards:

- 90-day vesting period with 7-day cliff
- 10% of tokens released at cliff
- Remaining 90% linearly vested over the remaining period
- Rate limiting to prevent abuse
- Global and per-user claim limits

## Deployment Process

### Pre-requisites
- Node.js and npm/yarn installed
- Hardhat or thirdweb CLI configured
- Wallet with sufficient funds for deployment

### Step 1: Deploy the Implementation Contract

```bash
npx thirdweb deploy
```

Select the `GenesisNFTLogic` contract and deploy it. The implementation contract doesn't need to be initialized as it will be called through the proxy.

### Step 2: Get Initialization Data

Deploy the helper contract:

```bash
npx thirdweb deploy
```

Select the `GenesisNFTDeployer` contract and deploy it. Then call the `getInitializationData` function with your parameters:

- `_defaultAdmin`: Address of the admin
- `_name`: NFT collection name
- `_symbol`: NFT collection symbol
- `_royaltyRecipient`: Address to receive royalties
- `_royaltyBps`: Royalty percentage in basis points (e.g., 500 = 5%)
- `_beraToken`: BERA token address
- `_ikigaiToken`: IKIGAI token address
- `_treasuryAddress`: Treasury address
- `_buybackEngine`: Buyback engine address
- `_beraHolderPrice`: Price for BERA holders
- `_whitelistPrice`: Price for whitelist
- `_publicPrice`: Public sale price

This will return the initialization data needed for the proxy deployment.

### Step 3: Deploy the Proxy Contract

```bash
npx thirdweb deploy
```

Select the `GenesisNFTProxy` contract and provide:
- `_logic`: The address of the implementation contract
- `_data`: The initialization data from Step 2

### Step 4: Interact with the Contract

After deployment, you interact with the proxy address, not the implementation address. All function calls will be delegated to the implementation.

## Upgrading the Contract

When you want to add new features or fix bugs:

1. Deploy the new implementation (e.g., `GenesisNFTLogicV2`)
2. Call the `upgradeTo` function on the proxy contract with the new implementation address:

```solidity
// Call this on the proxy contract
function upgradeTo(address newImplementation) external;
```

Only accounts with the `UPGRADE_ROLE` can perform upgrades.

### V2 Implementation Example

The V2 implementation included in this repository demonstrates how to add new features:

- VIP whitelist tier with special pricing
- Dynamic discounts based on NFT holdings
- NFT staking functionality
- Enhanced pricing logic

After upgrading to V2, call the `initializeV2` function to set up the new features:

```solidity
function initializeV2(
    uint256 _vipPrice,
    uint256 _discountPercentage
) external;
```

## Automation Scripts

The repository includes scripts to automate deployment and upgrades:

- `deploy.js`: Script for deploying the V1 implementation and proxy
- `upgrade.js`: Script for upgrading to the V2 implementation

These scripts can be run using Hardhat:

```bash
# Deploy initial implementation
npx hardhat run deploy.js --network <network>

# Upgrade to V2
npx hardhat run upgrade.js --network <network>
```

## Security Considerations

1. **Storage Layout**: Always maintain the same storage layout in new implementations. Add new variables at the end of the storage contract.

2. **Testing**: Thoroughly test new implementations before upgrading. Use the storage gap in the storage contract to future-proof against storage collisions.

3. **Access Control**: Ensure the `UPGRADE_ROLE` is only granted to trusted addresses. Consider implementing a timelock or multi-signature mechanism.

4. **Initialization**: Never initialize the implementation contract directly. Always use the proxy.

5. **Implementation Deployment**: After deploying a new implementation, verify its bytecode on-chain before upgrading.

6. **No Selfdestruct**: Never include selfdestruct functionality in implementation contracts as it would break the proxy.

7. **Function Signatures**: Be careful with function signature collisions when adding new functions.

## Deployment with thirdweb

The contract is compatible with thirdweb's deployment tools. Follow these steps:

1. Install the thirdweb CLI:
```bash
npm install -g @thirdweb-dev/cli
```

2. Deploy using thirdweb:
```bash
npx thirdweb deploy
```

3. Follow the same steps as above, using the thirdweb dashboard to interact with your deployed contracts.

## Additional Resources

- [OpenZeppelin Proxy Documentation](https://docs.openzeppelin.com/contracts/4.x/api/proxy)
- [EIP-1967: Standard Proxy Storage Slots](https://eips.ethereum.org/EIPS/eip-1967)
- [thirdweb NFT Drop Documentation](https://portal.thirdweb.com/contracts/explore/pre-built-modular/nft-drop)
- [UUPS Proxies vs Transparent Proxies](https://forum.openzeppelin.com/t/uups-proxies-tutorial-solidity-javascript/7786)

## License

Apache-2.0 