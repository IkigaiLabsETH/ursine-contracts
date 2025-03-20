// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./GenesisNFTLogic.sol";

/**
 * @title GenesisNFTLogicV2
 * @notice V2 Implementation of GenesisNFT with enhanced features
 * @dev Demonstrates how to create an upgrade to the GenesisNFT contract
 */
contract GenesisNFTLogicV2 is GenesisNFTLogic {
    // New state variables for V2
    mapping(address => bool) public vipWhitelist;
    uint256 public vipPrice;
    uint256 public discountPercentage; // 100 = 1%, 1000 = 10%
    bool public stakingEnabled;
    
    // Events for V2
    event VipWhitelistUpdated(address indexed user, bool status);
    event VipPriceUpdated(uint256 newPrice);
    event DiscountUpdated(uint256 newDiscountPercentage);
    event StakingStatusUpdated(bool enabled);

    /**
     * @notice Initialize V2 specific features (optional)
     * @dev Can be called only once after upgrading
     * @param _vipPrice Price for VIP whitelist
     * @param _discountPercentage Discount percentage (100 = 1%)
     */
    function initializeV2(
        uint256 _vipPrice,
        uint256 _discountPercentage
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_vipPrice > 0, "Invalid VIP price");
        require(_discountPercentage <= 5000, "Discount too high"); // Max 50% discount
        
        vipPrice = _vipPrice;
        discountPercentage = _discountPercentage;
        
        // V2 initializes with staking disabled
        stakingEnabled = false;
        
        emit VipPriceUpdated(_vipPrice);
        emit DiscountUpdated(_discountPercentage);
        emit StakingStatusUpdated(false);
    }
    
    /**
     * @notice Set VIP whitelist status for users
     * @param _users Array of user addresses
     * @param _status Array of VIP statuses
     */
    function setVipWhitelist(
        address[] calldata _users,
        bool[] calldata _status
    ) external nonReentrant onlyRole(WHITELIST_MANAGER_ROLE) {
        require(_users.length == _status.length, "Array length mismatch");
        require(_users.length <= 1000, "Batch too large");
        
        for (uint256 i = 0; i < _users.length; i++) {
            require(_users[i] != address(0), "Invalid address");
            vipWhitelist[_users[i]] = _status[i];
            emit VipWhitelistUpdated(_users[i], _status[i]);
        }
    }
    
    /**
     * @notice Set VIP price
     * @param _vipPrice New VIP price
     */
    function setVipPrice(uint256 _vipPrice) external nonReentrant onlyRole(PRICE_MANAGER_ROLE) {
        require(_vipPrice > 0, "Invalid VIP price");
        vipPrice = _vipPrice;
        emit VipPriceUpdated(_vipPrice);
    }
    
    /**
     * @notice Set discount percentage
     * @param _discountPercentage New discount percentage (100 = 1%)
     */
    function setDiscountPercentage(uint256 _discountPercentage) external nonReentrant onlyRole(PRICE_MANAGER_ROLE) {
        require(_discountPercentage <= 5000, "Discount too high"); // Max 50% discount
        discountPercentage = _discountPercentage;
        emit DiscountUpdated(_discountPercentage);
    }
    
    /**
     * @notice Set staking status
     * @param _enabled Whether staking is enabled
     */
    function setStakingStatus(bool _enabled) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingEnabled = _enabled;
        emit StakingStatusUpdated(_enabled);
    }

    /**
     * @notice Get current price for user - overrides the parent implementation
     * @param _user User address
     * @return Current price with VIP tier and discounts
     */
    function getCurrentPriceForUser(address _user) public view override returns (uint256) {
        uint256 basePrice;
        
        if (currentPhase == SalePhase.BeraHolders) {
            if (beraHolderWhitelist[_user]) basePrice = beraHolderPrice;
            else if (vipWhitelist[_user]) return vipPrice; // VIPs can mint in BERA holder phase
            else revert("Not eligible to mint");
        } else if (currentPhase == SalePhase.Whitelist) {
            if (beraHolderWhitelist[_user]) basePrice = beraHolderPrice;
            else if (vipWhitelist[_user]) basePrice = vipPrice;
            else if (generalWhitelist[_user]) basePrice = whitelistPrice;
            else revert("Not eligible to mint");
        } else if (currentPhase == SalePhase.Public) {
            basePrice = publicPrice;
            if (vipWhitelist[_user]) basePrice = vipPrice;
        } else {
            revert("Not eligible to mint");
        }
        
        // Apply discount if holding multiple NFTs
        uint256 heldNFTs = balanceOf(_user);
        if (heldNFTs > 0) {
            uint256 discount = (basePrice * discountPercentage * heldNFTs) / 10000;
            if (discount > basePrice / 2) discount = basePrice / 2; // Max 50% discount
            return basePrice - discount;
        }
        
        return basePrice;
    }
    
    /**
     * @notice Stake NFT for rewards (new V2 feature)
     * @param _tokenId Token ID to stake
     */
    function stakeNFT(uint256 _tokenId) external nonReentrant whenNotPaused {
        require(stakingEnabled, "Staking not enabled");
        require(ownerOf(_tokenId) == msg.sender, "Not token owner");
        
        // Implementation of staking logic would go here
        // This is a placeholder for the V2 enhancement
    }
    
    /**
     * @notice Unstake NFT (new V2 feature)
     * @param _tokenId Token ID to unstake
     */
    function unstakeNFT(uint256 _tokenId) external nonReentrant {
        require(stakingEnabled, "Staking not enabled");
        // Check if token is staked by the user
        
        // Implementation of unstaking logic would go here
        // This is a placeholder for the V2 enhancement
    }
    
    /**
     * @notice Claim staking rewards (new V2 feature)
     */
    function claimStakingRewards() external nonReentrant whenNotPaused {
        require(stakingEnabled, "Staking not enabled");
        
        // Implementation of staking rewards claiming would go here
        // This is a placeholder for the V2 enhancement
    }
    
    /**
     * @notice Calculates staking rewards for a user (new V2 feature)
     * @param _user User address
     * @return Rewards amount
     */
    function calculateStakingRewards(address _user) external view returns (uint256) {
        require(stakingEnabled, "Staking not enabled");
        
        // Implementation of staking rewards calculation would go here
        // This is a placeholder for the V2 enhancement
        return 0;
    }
} 