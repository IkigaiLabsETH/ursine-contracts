// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@thirdweb-dev/contracts/prebuilts/split/Split.sol";
import "@thirdweb-dev/contracts/extension/PermissionsEnumerable.sol";

/**
 * @title IKIGAI Revenue Split
 * @notice Split contract for distributing protocol revenue
 */
contract IKIGAISplit is Split, PermissionsEnumerable {
    // Split types
    enum SplitType { TRADING_FEES, NFT_ROYALTIES, BUNDLE_FEES }
    
    // Split type info
    struct SplitTypeInfo {
        SplitType splitType;
        string name;
        string description;
    }
    
    // Mapping of split type to info
    mapping(SplitType => SplitTypeInfo) public splitTypeInfo;
    
    // Current split type
    SplitType public currentSplitType;
    
    // Events
    event SplitTypeUpdated(SplitType indexed splitType);
    event SplitTypeInfoUpdated(SplitType indexed splitType, string name, string description);

    constructor(
        address _defaultAdmin,
        address[] memory _payees,
        uint256[] memory _shares
    )
        Split(
            _payees,
            _shares
        )
    {
        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        
        // Initialize split type info
        splitTypeInfo[SplitType.TRADING_FEES] = SplitTypeInfo({
            splitType: SplitType.TRADING_FEES,
            name: "Trading Fees",
            description: "Revenue from trading fees (4.3%)"
        });
        
        splitTypeInfo[SplitType.NFT_ROYALTIES] = SplitTypeInfo({
            splitType: SplitType.NFT_ROYALTIES,
            name: "NFT Royalties",
            description: "Revenue from NFT royalties (35%)"
        });
        
        splitTypeInfo[SplitType.BUNDLE_FEES] = SplitTypeInfo({
            splitType: SplitType.BUNDLE_FEES,
            name: "Bundle Fees",
            description: "Revenue from bundle fees (2.5%)"
        });
        
        // Set initial split type
        currentSplitType = SplitType.TRADING_FEES;
    }
    
    /**
     * @notice Set the current split type
     * @param _splitType New split type
     */
    function setSplitType(SplitType _splitType) external onlyRole(DEFAULT_ADMIN_ROLE) {
        currentSplitType = _splitType;
        emit SplitTypeUpdated(_splitType);
    }
    
    /**
     * @notice Update split type info
     * @param _splitType Split type to update
     * @param _name New name
     * @param _description New description
     */
    function updateSplitTypeInfo(
        SplitType _splitType,
        string calldata _name,
        string calldata _description
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        splitTypeInfo[_splitType] = SplitTypeInfo({
            splitType: _splitType,
            name: _name,
            description: _description
        });
        
        emit SplitTypeInfoUpdated(_splitType, _name, _description);
    }
    
    /**
     * @notice Get split type info
     * @param _splitType Split type to get info for
     * @return info Split type info
     */
    function getSplitTypeInfo(SplitType _splitType) external view returns (SplitTypeInfo memory info) {
        return splitTypeInfo[_splitType];
    }
    
    /**
     * @notice Distribute funds with a specific split type
     * @param _splitType Split type to use for distribution
     */
    function distributeWithSplitType(SplitType _splitType) external {
        // Store current split type
        SplitType previousSplitType = currentSplitType;
        
        // Set new split type
        currentSplitType = _splitType;
        
        // Distribute funds
        distribute();
        
        // Restore previous split type
        currentSplitType = previousSplitType;
    }
    
    /**
     * @notice Override distribute to add split type context
     */
    function distribute() public override returns (uint256 distributedAmount) {
        // Call parent distribute function
        distributedAmount = super.distribute();
        
        return distributedAmount;
    }
} 