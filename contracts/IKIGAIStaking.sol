// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@thirdweb-dev/contracts/base/Staking20Base.sol";
import "@thirdweb-dev/contracts/extension/PermissionsEnumerable.sol";

/**
 * @title IKIGAI Token Staking
 * @notice Staking contract for IKIGAI tokens with tiered rewards
 */
contract IKIGAIStaking is Staking20Base, PermissionsEnumerable {
    // Staking tiers
    enum Tier { BASE, SILVER, GOLD, DIAMOND }
    
    // Tier configuration
    struct TierConfig {
        uint256 minStakeAmount;  // Minimum amount to stake for this tier
        uint256 lockPeriod;      // Lock period in seconds
        uint256 rewardMultiplier; // Reward multiplier (100 = 1x, 125 = 1.25x, etc.)
    }
    
    // Mapping of tier to its configuration
    mapping(Tier => TierConfig) public tierConfigs;
    
    // Staker info with tier
    struct StakerInfo {
        uint256 amountStaked;
        uint256 timeOfLastUpdate;
        uint256 unclaimedRewards;
        uint256 lockEndTime;
        Tier tier;
    }
    
    // Override stakerInfo mapping
    mapping(address => StakerInfo) public override stakerInfo;
    
    // Default reward rate per second (base rate)
    uint256 public defaultRewardRatePerSecond;
    
    // Total rewards distributed
    uint256 public totalRewardsDistributed;

    constructor(
        address _defaultAdmin,
        address _stakingToken,
        address _rewardToken,
        address _nativeTokenWrapper
    )
        Staking20Base(
            _stakingToken,
            _rewardToken,
            _nativeTokenWrapper
        )
    {
        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        
        // Initialize tier configurations
        tierConfigs[Tier.BASE] = TierConfig({
            minStakeAmount: 1000 * 10**18,  // 1,000 IKIGAI
            lockPeriod: 7 days,
            rewardMultiplier: 100           // 1x
        });
        
        tierConfigs[Tier.SILVER] = TierConfig({
            minStakeAmount: 5000 * 10**18,  // 5,000 IKIGAI
            lockPeriod: 14 days,
            rewardMultiplier: 125           // 1.25x
        });
        
        tierConfigs[Tier.GOLD] = TierConfig({
            minStakeAmount: 10000 * 10**18, // 10,000 IKIGAI
            lockPeriod: 21 days,
            rewardMultiplier: 150           // 1.5x
        });
        
        tierConfigs[Tier.DIAMOND] = TierConfig({
            minStakeAmount: 25000 * 10**18, // 25,000 IKIGAI
            lockPeriod: 28 days,
            rewardMultiplier: 200           // 2x
        });
        
        // Set default reward rate (can be updated by admin)
        defaultRewardRatePerSecond = 1 * 10**18 / (365 days); // 1 token per year per token staked
    }
    
    /**
     * @notice Set the default reward rate per second
     * @param _rewardRatePerSecond New reward rate per second
     */
    function setDefaultRewardRatePerSecond(uint256 _rewardRatePerSecond) external onlyRole(DEFAULT_ADMIN_ROLE) {
        defaultRewardRatePerSecond = _rewardRatePerSecond;
    }
    
    /**
     * @notice Update a tier configuration
     * @param _tier Tier to update
     * @param _minStakeAmount New minimum stake amount
     * @param _lockPeriod New lock period in seconds
     * @param _rewardMultiplier New reward multiplier
     */
    function updateTierConfig(
        Tier _tier,
        uint256 _minStakeAmount,
        uint256 _lockPeriod,
        uint256 _rewardMultiplier
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        tierConfigs[_tier] = TierConfig({
            minStakeAmount: _minStakeAmount,
            lockPeriod: _lockPeriod,
            rewardMultiplier: _rewardMultiplier
        });
    }
    
    /**
     * @notice Determine tier based on amount and lock period
     * @param _amount Amount to stake
     * @param _lockPeriod Lock period in seconds
     * @return tier The determined tier
     */
    function determineTier(uint256 _amount, uint256 _lockPeriod) public view returns (Tier tier) {
        if (_amount >= tierConfigs[Tier.DIAMOND].minStakeAmount && _lockPeriod >= tierConfigs[Tier.DIAMOND].lockPeriod) {
            return Tier.DIAMOND;
        } else if (_amount >= tierConfigs[Tier.GOLD].minStakeAmount && _lockPeriod >= tierConfigs[Tier.GOLD].lockPeriod) {
            return Tier.GOLD;
        } else if (_amount >= tierConfigs[Tier.SILVER].minStakeAmount && _lockPeriod >= tierConfigs[Tier.SILVER].lockPeriod) {
            return Tier.SILVER;
        } else if (_amount >= tierConfigs[Tier.BASE].minStakeAmount && _lockPeriod >= tierConfigs[Tier.BASE].lockPeriod) {
            return Tier.BASE;
        } else {
            revert("Amount or lock period too low for any tier");
        }
    }
    
    /**
     * @notice Stake tokens with a specified lock period
     * @param _amount Amount to stake
     * @param _lockPeriod Lock period in seconds
     */
    function stake(uint256 _amount, uint256 _lockPeriod) external {
        require(_amount > 0, "Stake amount must be greater than zero");
        
        // Determine tier based on amount and lock period
        Tier tier = determineTier(_amount, _lockPeriod);
        
        // Update staker info
        StakerInfo storage staker = stakerInfo[msg.sender];
        
        // If already staking, claim rewards first
        if (staker.amountStaked > 0) {
            _updateUnclaimedRewards(msg.sender);
        }
        
        // Transfer tokens from user
        stakingToken.transferFrom(msg.sender, address(this), _amount);
        
        // Update staker info
        staker.amountStaked += _amount;
        staker.timeOfLastUpdate = block.timestamp;
        staker.lockEndTime = block.timestamp + _lockPeriod;
        staker.tier = tier;
        
        // Update total staked
        _totalStaked += _amount;
        
        emit Staked(msg.sender, _amount);
    }
    
    /**
     * @notice Withdraw staked tokens
     * @param _amount Amount to withdraw
     */
    function withdraw(uint256 _amount) external override {
        StakerInfo storage staker = stakerInfo[msg.sender];
        
        require(staker.amountStaked >= _amount, "Not enough staked tokens");
        require(block.timestamp >= staker.lockEndTime, "Tokens are still locked");
        
        // Update unclaimed rewards
        _updateUnclaimedRewards(msg.sender);
        
        // Update staker info
        staker.amountStaked -= _amount;
        staker.timeOfLastUpdate = block.timestamp;
        
        // If withdrawing all, reset tier
        if (staker.amountStaked == 0) {
            staker.tier = Tier.BASE;
            staker.lockEndTime = 0;
        } else {
            // Recalculate tier based on remaining amount
            // Keep the same lock period
            uint256 remainingLockPeriod = 0;
            if (staker.lockEndTime > block.timestamp) {
                remainingLockPeriod = staker.lockEndTime - block.timestamp;
            }
            
            // Try to determine new tier, but don't revert if it doesn't match any tier
            try this.determineTier(staker.amountStaked, remainingLockPeriod) returns (Tier newTier) {
                staker.tier = newTier;
            } catch {
                // Keep current tier if no matching tier found
            }
        }
        
        // Update total staked
        _totalStaked -= _amount;
        
        // Transfer tokens back to user
        stakingToken.transfer(msg.sender, _amount);
        
        emit Withdrawn(msg.sender, _amount);
    }
    
    /**
     * @notice Claim accumulated rewards
     */
    function claimRewards() external override {
        StakerInfo storage staker = stakerInfo[msg.sender];
        
        // Update unclaimed rewards
        _updateUnclaimedRewards(msg.sender);
        
        // Get rewards to transfer
        uint256 rewards = staker.unclaimedRewards;
        
        if (rewards > 0) {
            staker.unclaimedRewards = 0;
            staker.timeOfLastUpdate = block.timestamp;
            
            // Update total rewards
            totalRewardsDistributed += rewards;
            
            // Transfer rewards
            rewardToken.transfer(msg.sender, rewards);
            
            emit RewardsClaimed(msg.sender, rewards);
        }
    }
    
    /**
     * @notice Get unclaimed rewards for a staker
     * @param _staker Address of the staker
     * @return unclaimedRewards Amount of unclaimed rewards
     */
    function getStakingRewards(address _staker) external view returns (uint256 unclaimedRewards) {
        StakerInfo storage staker = stakerInfo[_staker];
        
        if (staker.amountStaked == 0) {
            return staker.unclaimedRewards;
        }
        
        // Calculate time elapsed since last update
        uint256 timeElapsed = block.timestamp - staker.timeOfLastUpdate;
        
        // Get reward multiplier based on tier
        uint256 multiplier = tierConfigs[staker.tier].rewardMultiplier;
        
        // Calculate rewards: amount * rate * time * multiplier / 100
        uint256 newRewards = (staker.amountStaked * defaultRewardRatePerSecond * timeElapsed * multiplier) / 100;
        
        return staker.unclaimedRewards + newRewards;
    }
    
    /**
     * @notice Update unclaimed rewards for a staker
     * @param _staker Address of the staker
     */
    function _updateUnclaimedRewards(address _staker) internal {
        StakerInfo storage staker = stakerInfo[_staker];
        
        if (staker.amountStaked == 0) {
            return;
        }
        
        // Calculate time elapsed since last update
        uint256 timeElapsed = block.timestamp - staker.timeOfLastUpdate;
        
        // Get reward multiplier based on tier
        uint256 multiplier = tierConfigs[staker.tier].rewardMultiplier;
        
        // Calculate rewards: amount * rate * time * multiplier / 100
        uint256 newRewards = (staker.amountStaked * defaultRewardRatePerSecond * timeElapsed * multiplier) / 100;
        
        // Update unclaimed rewards
        staker.unclaimedRewards += newRewards;
        staker.timeOfLastUpdate = block.timestamp;
    }
} 