// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@thirdweb-dev/contracts/extension/PermissionsEnumerable.sol";

/**
 * @title IKIGAI Strategy Interface
 * @notice Interface for yield-generating strategies used by IKIGAI Vaults
 */
interface IIKIGAIStrategy {
    /**
     * @notice Get the address of the underlying asset used by this strategy
     * @return Address of the asset
     */
    function asset() external view returns (address);
    
    /**
     * @notice Get the address of the vault that owns this strategy
     * @return Address of the vault
     */
    function vault() external view returns (address);
    
    /**
     * @notice Deposit assets into the strategy
     * @param _amount Amount of assets to deposit
     */
    function deposit(uint256 _amount) external;
    
    /**
     * @notice Withdraw assets from the strategy
     * @param _amount Amount of assets to withdraw
     * @return Amount of assets actually withdrawn
     */
    function withdraw(uint256 _amount) external returns (uint256);
    
    /**
     * @notice Withdraw all assets from the strategy
     * @return Amount of assets withdrawn
     */
    function withdrawAll() external returns (uint256);
    
    /**
     * @notice Harvest rewards and reinvest
     * @return Amount of rewards harvested
     */
    function harvest() external returns (uint256);
    
    /**
     * @notice Get the total assets managed by this strategy
     * @return Total assets
     */
    function totalAssets() external view returns (uint256);
    
    /**
     * @notice Get the estimated APY of this strategy
     * @return APY in basis points
     */
    function estimatedAPY() external view returns (uint256);
    
    /**
     * @notice Check if the strategy is active
     * @return True if active, false otherwise
     */
    function isActive() external view returns (bool);
    
    /**
     * @notice Pause the strategy
     */
    function pause() external;
    
    /**
     * @notice Unpause the strategy
     */
    function unpause() external;
}

/**
 * @title IKIGAI Strategy Base
 * @notice Base implementation for IKIGAI strategies
 */
abstract contract IKIGAIStrategy is IIKIGAIStrategy, PermissionsEnumerable {
    // Role definitions
    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");
    bytes32 public constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");
    
    // Underlying asset
    address public override asset;
    
    // Vault that owns this strategy
    address public override vault;
    
    // Whether the strategy is active
    bool private _isActive;
    
    // Whether the strategy is paused
    bool private _isPaused;
    
    // Last harvest time
    uint256 public lastHarvestTime;
    
    // Total harvested amount
    uint256 public totalHarvested;
    
    // Events
    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);
    event Harvested(uint256 amount);
    event StrategyPaused();
    event StrategyUnpaused();
    
    /**
     * @notice Constructor
     * @param _defaultAdmin Address of the default admin
     * @param _asset Address of the underlying asset
     * @param _vault Address of the vault
     */
    constructor(
        address _defaultAdmin,
        address _asset,
        address _vault
    ) {
        require(_asset != address(0), "Invalid asset address");
        require(_vault != address(0), "Invalid vault address");
        
        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _setupRole(HARVESTER_ROLE, _defaultAdmin);
        _setupRole(STRATEGY_MANAGER_ROLE, _defaultAdmin);
        
        asset = _asset;
        vault = _vault;
        _isActive = true;
        _isPaused = false;
        lastHarvestTime = block.timestamp;
    }
    
    /**
     * @notice Check if the strategy is active
     * @return True if active, false otherwise
     */
    function isActive() public view override returns (bool) {
        return _isActive && !_isPaused;
    }
    
    /**
     * @notice Pause the strategy
     */
    function pause() external override onlyRole(STRATEGY_MANAGER_ROLE) {
        _isPaused = true;
        emit StrategyPaused();
    }
    
    /**
     * @notice Unpause the strategy
     */
    function unpause() external override onlyRole(STRATEGY_MANAGER_ROLE) {
        _isPaused = false;
        emit StrategyUnpaused();
    }
    
    /**
     * @notice Modifier to check if the caller is the vault
     */
    modifier onlyVault() {
        require(msg.sender == vault, "Caller is not the vault");
        _;
    }
    
    /**
     * @notice Modifier to check if the strategy is active
     */
    modifier whenActive() {
        require(isActive(), "Strategy is not active");
        _;
    }
} 