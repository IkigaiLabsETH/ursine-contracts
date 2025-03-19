// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@thirdweb-dev/contracts/base/Staking721Base.sol";
import "@thirdweb-dev/contracts/extension/PermissionsEnumerable.sol";

/**
 * @title IKIGAI NFT Staking
 * @notice Staking contract for IKIGAI Genesis NFTs
 */
contract NFTStaking is Staking721Base, PermissionsEnumerable {
    // Default reward rate per second per NFT
    uint256 public rewardRatePerSecond;
    
    // Total rewards distributed
    uint256 public totalRewardsDistributed;
    
    // Mapping for custom reward rates per token ID
    mapping(uint256 => uint256) public tokenRewardRates;
    
    // Flag to enable/disable custom reward rates
    bool public useCustomRewardRates;

    constructor(
        address _defaultAdmin,
        address _nftCollection,
        address _rewardToken,
        address _nativeTokenWrapper
    )
        Staking721Base(
            _nftCollection,
            _rewardToken,
            _nativeTokenWrapper
        )
    {
        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        
        // Set default reward rate (can be updated by admin)
        rewardRatePerSecond = 10 * 10**18 / (365 days); // 10 tokens per year per NFT
        
        // Disable custom reward rates by default
        useCustomRewardRates = false;
    }
    
    /**
     * @notice Set the default reward rate per second
     * @param _rewardRatePerSecond New reward rate per second
     */
    function setRewardRatePerSecond(uint256 _rewardRatePerSecond) external onlyRole(DEFAULT_ADMIN_ROLE) {
        rewardRatePerSecond = _rewardRatePerSecond;
    }
    
    /**
     * @notice Set custom reward rate for a specific token ID
     * @param _tokenId Token ID to set rate for
     * @param _rewardRate Custom reward rate
     */
    function setTokenRewardRate(uint256 _tokenId, uint256 _rewardRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        tokenRewardRates[_tokenId] = _rewardRate;
    }
    
    /**
     * @notice Enable or disable custom reward rates
     * @param _useCustomRates Whether to use custom rates
     */
    function setUseCustomRewardRates(bool _useCustomRates) external onlyRole(DEFAULT_ADMIN_ROLE) {
        useCustomRewardRates = _useCustomRates;
    }
    
    /**
     * @notice Get reward rate for a specific token ID
     * @param _tokenId Token ID to get rate for
     * @return rate Reward rate for the token
     */
    function getRewardRateForToken(uint256 _tokenId) public view returns (uint256 rate) {
        if (useCustomRewardRates && tokenRewardRates[_tokenId] > 0) {
            return tokenRewardRates[_tokenId];
        }
        return rewardRatePerSecond;
    }
    
    /**
     * @notice Calculate staking rewards for a staker
     * @param _staker Address of the staker
     * @return rewards Amount of rewards
     */
    function calculateRewards(address _staker) public view override returns (uint256 rewards) {
        Staker storage staker = stakers[_staker];
        
        if (staker.amountStaked == 0) {
            return staker.unclaimedRewards;
        }
        
        rewards = staker.unclaimedRewards;
        
        // Calculate rewards for each staked token
        for (uint256 i = 0; i < staker.stakedTokens.length; i++) {
            uint256 tokenId = staker.stakedTokens[i];
            uint256 stakedAt = staker.tokenStakedAt[tokenId];
            
            if (stakedAt == 0) {
                continue;
            }
            
            // Get reward rate for this token
            uint256 tokenRate = getRewardRateForToken(tokenId);
            
            // Calculate time elapsed since staking
            uint256 timeElapsed = block.timestamp - stakedAt;
            
            // Calculate rewards for this token
            rewards += tokenRate * timeElapsed;
        }
        
        return rewards;
    }
    
    /**
     * @notice Claim accumulated rewards
     */
    function claimRewards() external override {
        uint256 rewards = calculateRewards(msg.sender);
        
        Staker storage staker = stakers[msg.sender];
        
        if (rewards > 0) {
            staker.unclaimedRewards = 0;
            
            // Update staked timestamps for all tokens
            for (uint256 i = 0; i < staker.stakedTokens.length; i++) {
                uint256 tokenId = staker.stakedTokens[i];
                staker.tokenStakedAt[tokenId] = block.timestamp;
            }
            
            // Update total rewards
            totalRewardsDistributed += rewards;
            
            // Transfer rewards
            rewardToken.transfer(msg.sender, rewards);
            
            emit RewardsClaimed(msg.sender, rewards);
        }
    }
    
    /**
     * @notice Stake NFTs
     * @param _tokenIds Array of token IDs to stake
     */
    function stake(uint256[] calldata _tokenIds) external override {
        require(_tokenIds.length > 0, "No tokens to stake");
        
        Staker storage staker = stakers[msg.sender];
        
        // Calculate rewards before adding new tokens
        uint256 rewards = calculateRewards(msg.sender);
        staker.unclaimedRewards = rewards;
        
        // Update staker info
        staker.amountStaked += _tokenIds.length;
        
        // Transfer and update for each token
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];
            
            // Transfer token to contract
            nftCollection.transferFrom(msg.sender, address(this), tokenId);
            
            // Update staking info
            staker.tokenStakedAt[tokenId] = block.timestamp;
            staker.stakedTokens.push(tokenId);
        }
        
        emit TokensStaked(msg.sender, _tokenIds);
    }
    
    /**
     * @notice Withdraw staked NFTs
     * @param _tokenIds Array of token IDs to withdraw
     */
    function withdraw(uint256[] calldata _tokenIds) external override {
        require(_tokenIds.length > 0, "No tokens to withdraw");
        
        Staker storage staker = stakers[msg.sender];
        require(staker.amountStaked >= _tokenIds.length, "Not enough staked tokens");
        
        // Calculate rewards before removing tokens
        uint256 rewards = calculateRewards(msg.sender);
        staker.unclaimedRewards = rewards;
        
        // Update staker info
        staker.amountStaked -= _tokenIds.length;
        
        // Transfer and update for each token
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];
            
            // Verify token is staked by this user
            require(staker.tokenStakedAt[tokenId] > 0, "Token not staked by user");
            
            // Reset staking info
            staker.tokenStakedAt[tokenId] = 0;
            
            // Remove token from stakedTokens array
            _removeTokenFromStakedTokens(staker, tokenId);
            
            // Transfer token back to user
            nftCollection.transferFrom(address(this), msg.sender, tokenId);
        }
        
        emit TokensWithdrawn(msg.sender, _tokenIds);
    }
    
    /**
     * @notice Remove a token from the stakedTokens array
     * @param _staker Staker struct
     * @param _tokenId Token ID to remove
     */
    function _removeTokenFromStakedTokens(Staker storage _staker, uint256 _tokenId) internal {
        for (uint256 i = 0; i < _staker.stakedTokens.length; i++) {
            if (_staker.stakedTokens[i] == _tokenId) {
                // Replace with the last element and pop
                if (i != _staker.stakedTokens.length - 1) {
                    _staker.stakedTokens[i] = _staker.stakedTokens[_staker.stakedTokens.length - 1];
                }
                _staker.stakedTokens.pop();
                break;
            }
        }
    }
} 