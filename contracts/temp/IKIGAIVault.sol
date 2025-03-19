// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@thirdweb-dev/contracts/extension/PermissionsEnumerable.sol";

/**
 * @title IKIGAI Vault
 * @notice Yield-generating vault for the IKIGAI Protocol
 */
contract IKIGAIVault is ERC4626, PermissionsEnumerable {
    // Role definitions
    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");
    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");
    
    // Strategy info
    struct StrategyInfo {
        address strategyAddress;
        uint256 allocation;        // Percentage allocation in basis points (e.g., 5000 = 50%)
        bool active;
        uint256 lastHarvestTime;
    }
    
    // Array of strategy addresses
    address[] public strategies;
    
    // Mapping of strategy address to its info
    mapping(address => StrategyInfo) public strategyInfo;
    
    // Performance fee in basis points (e.g., 1000 = 10%)
    uint256 public performanceFee;
    
    // Fee recipient
    address public feeRecipient;
    
    // Management fee in basis points per year (e.g., 200 = 2%)
    uint256 public managementFee;
    
    // Last management fee collection timestamp
    uint256 public lastManagementFeeCollection;
    
    // Events
    event StrategyAdded(address indexed strategy, uint256 allocation);
    event StrategyRemoved(address indexed strategy);
    event StrategyAllocationUpdated(address indexed strategy, uint256 newAllocation);
    event Harvested(address indexed strategy, uint256 amount);
    event PerformanceFeeUpdated(uint256 newFee);
    event ManagementFeeUpdated(uint256 newFee);
    event FeeRecipientUpdated(address newFeeRecipient);

    constructor(
        address _defaultAdmin,
        address _asset,
        string memory _name,
        string memory _symbol,
        address _feeRecipient,
        uint256 _performanceFee,
        uint256 _managementFee
    )
        ERC4626(
            _asset,
            _name,
            _symbol
        )
    {
        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _setupRole(STRATEGY_ROLE, _defaultAdmin);
        _setupRole(HARVESTER_ROLE, _defaultAdmin);
        
        feeRecipient = _feeRecipient;
        performanceFee = _performanceFee;
        managementFee = _managementFee;
        lastManagementFeeCollection = block.timestamp;
    }
    
    /**
     * @notice Add a new strategy to the vault
     * @param _strategy Address of the strategy contract
     * @param _allocation Percentage allocation in basis points
     */
    function addStrategy(address _strategy, uint256 _allocation) 
        external 
        onlyRole(STRATEGY_ROLE) 
    {
        require(_strategy != address(0), "Invalid strategy address");
        require(_allocation <= 10000, "Allocation cannot exceed 100%");
        require(!strategyInfo[_strategy].active, "Strategy already added");
        
        // Check total allocation doesn't exceed 100%
        uint256 totalAllocation = _allocation;
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategyInfo[strategies[i]].active) {
                totalAllocation += strategyInfo[strategies[i]].allocation;
            }
        }
        require(totalAllocation <= 10000, "Total allocation exceeds 100%");
        
        // Add strategy
        strategies.push(_strategy);
        strategyInfo[_strategy] = StrategyInfo({
            strategyAddress: _strategy,
            allocation: _allocation,
            active: true,
            lastHarvestTime: block.timestamp
        });
        
        emit StrategyAdded(_strategy, _allocation);
    }
    
    /**
     * @notice Remove a strategy from the vault
     * @param _strategy Address of the strategy to remove
     */
    function removeStrategy(address _strategy) 
        external 
        onlyRole(STRATEGY_ROLE) 
    {
        require(strategyInfo[_strategy].active, "Strategy not active");
        
        // Withdraw all funds from strategy
        // This would require the strategy to implement a withdraw function
        // that the vault can call
        
        // Mark strategy as inactive
        strategyInfo[_strategy].active = false;
        strategyInfo[_strategy].allocation = 0;
        
        emit StrategyRemoved(_strategy);
    }
    
    /**
     * @notice Update a strategy's allocation
     * @param _strategy Address of the strategy
     * @param _newAllocation New allocation in basis points
     */
    function updateStrategyAllocation(address _strategy, uint256 _newAllocation) 
        external 
        onlyRole(STRATEGY_ROLE) 
    {
        require(strategyInfo[_strategy].active, "Strategy not active");
        require(_newAllocation <= 10000, "Allocation cannot exceed 100%");
        
        // Check total allocation doesn't exceed 100%
        uint256 totalAllocation = _newAllocation;
        for (uint256 i = 0; i < strategies.length; i++) {
            address strategyAddress = strategies[i];
            if (strategyAddress != _strategy && strategyInfo[strategyAddress].active) {
                totalAllocation += strategyInfo[strategyAddress].allocation;
            }
        }
        require(totalAllocation <= 10000, "Total allocation exceeds 100%");
        
        // Update allocation
        strategyInfo[_strategy].allocation = _newAllocation;
        
        emit StrategyAllocationUpdated(_strategy, _newAllocation);
    }
    
    /**
     * @notice Harvest returns from a strategy
     * @param _strategy Address of the strategy to harvest
     */
    function harvest(address _strategy) 
        external 
        onlyRole(HARVESTER_ROLE) 
    {
        require(strategyInfo[_strategy].active, "Strategy not active");
        
        // This would call the harvest function on the strategy
        // and collect any returns
        // For now, we'll just update the last harvest time
        strategyInfo[_strategy].lastHarvestTime = block.timestamp;
        
        // In a real implementation, we would:
        // 1. Call the strategy's harvest function
        // 2. Collect the returns
        // 3. Take performance fee
        // 4. Reinvest the rest
        
        emit Harvested(_strategy, 0); // Replace 0 with actual harvested amount
    }
    
    /**
     * @notice Set the performance fee
     * @param _performanceFee New performance fee in basis points
     */
    function setPerformanceFee(uint256 _performanceFee) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_performanceFee <= 3000, "Fee too high"); // Max 30%
        performanceFee = _performanceFee;
        emit PerformanceFeeUpdated(_performanceFee);
    }
    
    /**
     * @notice Set the management fee
     * @param _managementFee New management fee in basis points per year
     */
    function setManagementFee(uint256 _managementFee) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_managementFee <= 500, "Fee too high"); // Max 5%
        managementFee = _managementFee;
        emit ManagementFeeUpdated(_managementFee);
    }
    
    /**
     * @notice Set the fee recipient
     * @param _feeRecipient New fee recipient address
     */
    function setFeeRecipient(address _feeRecipient) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }
    
    /**
     * @notice Get the total number of strategies
     * @return Number of strategies
     */
    function getStrategyCount() external view returns (uint256) {
        return strategies.length;
    }
    
    /**
     * @notice Get all active strategies
     * @return Array of active strategy addresses
     */
    function getActiveStrategies() external view returns (address[] memory) {
        uint256 activeCount = 0;
        
        // Count active strategies
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategyInfo[strategies[i]].active) {
                activeCount++;
            }
        }
        
        // Create array of active strategies
        address[] memory activeStrategies = new address[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategyInfo[strategies[i]].active) {
                activeStrategies[index] = strategies[i];
                index++;
            }
        }
        
        return activeStrategies;
    }
    
    /**
     * @notice Calculate the total assets in the vault
     * @return Total assets
     */
    function totalAssets() public view override returns (uint256) {
        // In a real implementation, this would sum:
        // 1. Assets in the vault
        // 2. Assets deployed in strategies
        return super.totalAssets();
    }
    
    /**
     * @notice Calculate the APY of the vault
     * @return APY in basis points
     */
    function getAPY() external view returns (uint256) {
        // This would be implemented to calculate the actual APY
        // based on historical performance
        return 0;
    }
} 