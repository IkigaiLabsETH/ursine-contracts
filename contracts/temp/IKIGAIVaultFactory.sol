// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IKIGAIVault.sol";
import "@thirdweb-dev/contracts/extension/PermissionsEnumerable.sol";
import "@thirdweb-dev/contracts/extension/ContractMetadata.sol";

/**
 * @title IKIGAI Vault Factory
 * @notice Factory contract for deploying IKIGAI Vaults
 */
contract IKIGAIVaultFactory is PermissionsEnumerable, ContractMetadata {
    // Array of deployed vaults
    address[] public vaults;
    
    // Mapping of asset to vault
    mapping(address => address) public assetToVault;
    
    // Default performance fee in basis points (10%)
    uint256 public defaultPerformanceFee = 1000;
    
    // Default management fee in basis points per year (2%)
    uint256 public defaultManagementFee = 200;
    
    // Fee recipient
    address public feeRecipient;
    
    // Events
    event VaultDeployed(address indexed vault, address indexed asset, string name, string symbol);
    event DefaultPerformanceFeeUpdated(uint256 newFee);
    event DefaultManagementFeeUpdated(uint256 newFee);
    event FeeRecipientUpdated(address newFeeRecipient);

    constructor(
        address _defaultAdmin,
        address _feeRecipient
    ) {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        
        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        feeRecipient = _feeRecipient;
        
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
     * @notice Deploy a new vault
     * @param _asset Address of the underlying asset
     * @param _name Name of the vault token
     * @param _symbol Symbol of the vault token
     * @return Address of the deployed vault
     */
    function deployVault(
        address _asset,
        string memory _name,
        string memory _symbol
    ) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        returns (address) 
    {
        require(_asset != address(0), "Invalid asset address");
        require(assetToVault[_asset] == address(0), "Vault for asset already exists");
        
        // Deploy new vault
        IKIGAIVault vault = new IKIGAIVault(
            msg.sender,
            _asset,
            _name,
            _symbol,
            feeRecipient,
            defaultPerformanceFee,
            defaultManagementFee
        );
        
        // Register vault
        address vaultAddress = address(vault);
        vaults.push(vaultAddress);
        assetToVault[_asset] = vaultAddress;
        
        emit VaultDeployed(vaultAddress, _asset, _name, _symbol);
        
        return vaultAddress;
    }
    
    /**
     * @notice Set the default performance fee
     * @param _defaultPerformanceFee New default performance fee in basis points
     */
    function setDefaultPerformanceFee(uint256 _defaultPerformanceFee) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_defaultPerformanceFee <= 3000, "Fee too high"); // Max 30%
        defaultPerformanceFee = _defaultPerformanceFee;
        emit DefaultPerformanceFeeUpdated(_defaultPerformanceFee);
    }
    
    /**
     * @notice Set the default management fee
     * @param _defaultManagementFee New default management fee in basis points per year
     */
    function setDefaultManagementFee(uint256 _defaultManagementFee) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_defaultManagementFee <= 500, "Fee too high"); // Max 5%
        defaultManagementFee = _defaultManagementFee;
        emit DefaultManagementFeeUpdated(_defaultManagementFee);
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
     * @notice Get the total number of vaults
     * @return Number of vaults
     */
    function getVaultCount() external view returns (uint256) {
        return vaults.length;
    }
    
    /**
     * @notice Get all vaults
     * @return Array of vault addresses
     */
    function getAllVaults() external view returns (address[] memory) {
        return vaults;
    }
    
    /**
     * @notice Check if a vault exists for an asset
     * @param _asset Address of the asset
     * @return True if a vault exists, false otherwise
     */
    function vaultExists(address _asset) external view returns (bool) {
        return assetToVault[_asset] != address(0);
    }
    
    /**
     * @notice Get the vault for an asset
     * @param _asset Address of the asset
     * @return Address of the vault
     */
    function getVault(address _asset) external view returns (address) {
        return assetToVault[_asset];
    }
} 