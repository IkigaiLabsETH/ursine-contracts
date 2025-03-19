// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../IKIGAIStrategy.sol";
import "@thirdweb-dev/contracts/extension/PermissionsEnumerable.sol";
import "@thirdweb-dev/contracts/extension/ContractMetadata.sol";

/**
 * @title IKIGAI Lending Strategy
 * @notice Strategy that lends assets to a lending protocol to generate yield
 */
contract LendingStrategy is IKIGAIStrategy, ContractMetadata {
    // Mock lending protocol interface
    address public lendingProtocol;
    
    // Current balance in the lending protocol
    uint256 private _balance;
    
    // APY of the lending protocol (in basis points)
    uint256 public lendingAPY;
    
    // Last update time for the balance
    uint256 private _lastUpdateTime;
    
    /**
     * @notice Constructor
     * @param _defaultAdmin Address of the default admin
     * @param _asset Address of the underlying asset
     * @param _vault Address of the vault
     * @param _lendingProtocol Address of the lending protocol
     * @param _initialAPY Initial APY of the lending protocol (in basis points)
     */
    constructor(
        address _defaultAdmin,
        address _asset,
        address _vault,
        address _lendingProtocol,
        uint256 _initialAPY
    )
        IKIGAIStrategy(_defaultAdmin, _asset, _vault)
    {
        require(_lendingProtocol != address(0), "Invalid lending protocol address");
        
        lendingProtocol = _lendingProtocol;
        lendingAPY = _initialAPY;
        _lastUpdateTime = block.timestamp;
        
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
     * @notice Set the lending protocol address
     * @param _lendingProtocol New lending protocol address
     */
    function setLendingProtocol(address _lendingProtocol) external onlyRole(STRATEGY_MANAGER_ROLE) {
        require(_lendingProtocol != address(0), "Invalid lending protocol address");
        lendingProtocol = _lendingProtocol;
    }
    
    /**
     * @notice Set the lending APY
     * @param _lendingAPY New lending APY (in basis points)
     */
    function setLendingAPY(uint256 _lendingAPY) external onlyRole(STRATEGY_MANAGER_ROLE) {
        lendingAPY = _lendingAPY;
    }
    
    /**
     * @notice Deposit assets into the strategy
     * @param _amount Amount of assets to deposit
     */
    function deposit(uint256 _amount) external override onlyVault whenActive {
        require(_amount > 0, "Amount must be greater than 0");
        
        // Update balance with accrued interest before deposit
        _updateBalance();
        
        // In a real implementation, this would transfer tokens from the vault
        // to the lending protocol
        
        // For this mock implementation, we just update the balance
        _balance += _amount;
        
        emit Deposited(_amount);
    }
    
    /**
     * @notice Withdraw assets from the strategy
     * @param _amount Amount of assets to withdraw
     * @return Amount of assets actually withdrawn
     */
    function withdraw(uint256 _amount) external override onlyVault returns (uint256) {
        // Update balance with accrued interest before withdrawal
        _updateBalance();
        
        // Ensure we don't withdraw more than we have
        uint256 amountToWithdraw = _amount > _balance ? _balance : _amount;
        
        // In a real implementation, this would withdraw tokens from the lending protocol
        // and transfer them to the vault
        
        // For this mock implementation, we just update the balance
        _balance -= amountToWithdraw;
        
        emit Withdrawn(amountToWithdraw);
        return amountToWithdraw;
    }
    
    /**
     * @notice Withdraw all assets from the strategy
     * @return Amount of assets withdrawn
     */
    function withdrawAll() external override onlyVault returns (uint256) {
        // Update balance with accrued interest before withdrawal
        _updateBalance();
        
        uint256 amountToWithdraw = _balance;
        
        // In a real implementation, this would withdraw all tokens from the lending protocol
        // and transfer them to the vault
        
        // For this mock implementation, we just update the balance
        _balance = 0;
        
        emit Withdrawn(amountToWithdraw);
        return amountToWithdraw;
    }
    
    /**
     * @notice Harvest rewards and reinvest
     * @return Amount of rewards harvested
     */
    function harvest() external override onlyRole(HARVESTER_ROLE) whenActive returns (uint256) {
        // Update balance with accrued interest
        uint256 oldBalance = _balance;
        _updateBalance();
        uint256 harvestedAmount = _balance - oldBalance;
        
        // In a real implementation, this would claim rewards from the lending protocol
        // and reinvest them
        
        // Update last harvest time
        lastHarvestTime = block.timestamp;
        totalHarvested += harvestedAmount;
        
        emit Harvested(harvestedAmount);
        return harvestedAmount;
    }
    
    /**
     * @notice Get the total assets managed by this strategy
     * @return Total assets
     */
    function totalAssets() external view override returns (uint256) {
        // Calculate current balance with accrued interest
        return _calculateCurrentBalance();
    }
    
    /**
     * @notice Get the estimated APY of this strategy
     * @return APY in basis points
     */
    function estimatedAPY() external view override returns (uint256) {
        return lendingAPY;
    }
    
    /**
     * @notice Update the balance with accrued interest
     */
    function _updateBalance() internal {
        _balance = _calculateCurrentBalance();
        _lastUpdateTime = block.timestamp;
    }
    
    /**
     * @notice Calculate the current balance with accrued interest
     * @return Current balance
     */
    function _calculateCurrentBalance() internal view returns (uint256) {
        if (_balance == 0) {
            return 0;
        }
        
        uint256 timeElapsed = block.timestamp - _lastUpdateTime;
        
        // Calculate interest: balance * APY * timeElapsed / (365 days * 10000)
        // APY is in basis points, so we divide by 10000
        uint256 interest = (_balance * lendingAPY * timeElapsed) / (365 days * 10000);
        
        return _balance + interest;
    }
} 