// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./strategies/LendingStrategy.sol";
import "@thirdweb-dev/contracts/extension/PermissionsEnumerable.sol";
import "@thirdweb-dev/contracts/extension/ContractMetadata.sol";

/**
 * @title IKIGAI Strategy Factory
 * @notice Factory contract for deploying IKIGAI Strategies
 */
contract IKIGAIStrategyFactory is PermissionsEnumerable, ContractMetadata {
    // Array of deployed strategies
    address[] public strategies;
    
    // Mapping of vault to its strategies
    mapping(address => address[]) public vaultStrategies;
    
    // Events
    event StrategyDeployed(address indexed strategy, address indexed vault, address indexed asset, string strategyType);

    constructor(
        address _defaultAdmin
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        
        // Set contract metadata
        _setupContractURI("ipfs://QmYourContractMetadataHash");
    }
    
    /**
     * @notice Set the contract URI
     * @param _uri New contract URI
     */
    function setContractURI(string memory _uri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setupContractURI(_uri);
    }
    
    /**
     * @notice Deploy a new lending strategy
     * @param _vault Address of the vault
     * @param _asset Address of the underlying asset
     * @param _lendingProtocol Address of the lending protocol
     * @param _initialAPY Initial APY of the lending protocol (in basis points)
     * @return Address of the deployed strategy
     */
    function deployLendingStrategy(
        address _vault,
        address _asset,
        address _lendingProtocol,
        uint256 _initialAPY
    ) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        returns (address) 
    {
        require(_vault != address(0), "Invalid vault address");
        require(_asset != address(0), "Invalid asset address");
        require(_lendingProtocol != address(0), "Invalid lending protocol address");
        
        // Deploy new strategy
        LendingStrategy strategy = new LendingStrategy(
            msg.sender,
            _asset,
            _vault,
            _lendingProtocol,
            _initialAPY
        );
        
        // Register strategy
        address strategyAddress = address(strategy);
        strategies.push(strategyAddress);
        vaultStrategies[_vault].push(strategyAddress);
        
        emit StrategyDeployed(strategyAddress, _vault, _asset, "LendingStrategy");
        
        return strategyAddress;
    }
    
    /**
     * @notice Get the total number of strategies
     * @return Number of strategies
     */
    function getStrategyCount() external view returns (uint256) {
        return strategies.length;
    }
    
    /**
     * @notice Get all strategies
     * @return Array of strategy addresses
     */
    function getAllStrategies() external view returns (address[] memory) {
        return strategies;
    }
    
    /**
     * @notice Get the number of strategies for a vault
     * @param _vault Address of the vault
     * @return Number of strategies
     */
    function getVaultStrategyCount(address _vault) external view returns (uint256) {
        return vaultStrategies[_vault].length;
    }
    
    /**
     * @notice Get all strategies for a vault
     * @param _vault Address of the vault
     * @return Array of strategy addresses
     */
    function getVaultStrategies(address _vault) external view returns (address[] memory) {
        return vaultStrategies[_vault];
    }
} 