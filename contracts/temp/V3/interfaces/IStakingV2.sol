// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IStakingV2
 * @notice Interface for the Ikigai V2 staking system with tiered rewards
 * @dev Implements flexible lock periods, tier-based multipliers, and emergency controls
 */
interface IStakingV2 {
    /**
     * @notice Represents a staking position
     * @param amount Number of tokens staked
     * @param startTime Timestamp when staking began
     * @param lockPeriod Duration of the lock in seconds
     * @param tier Staking tier (0-3) based on amount
     * @param rewards Accumulated rewards
     * @param active Whether the stake is currently active
     */
    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 lockPeriod;
        uint256 tier;
        uint256 rewards;
        bool active;
    }

    /**
     * @notice Creates a new stake with specified amount and lock period
     * @dev Transfers tokens from caller to contract
     * @param amount Number of tokens to stake
     * @param lockPeriod Duration to lock tokens (7-28 days)
     */
    function stake(uint256 amount, uint256 lockPeriod) external;

    /**
     * @notice Unstakes tokens and claims rewards after lock period
     * @dev Transfers original stake and rewards to caller
     */
    function unstake() external;

    /**
     * @notice Allows emergency withdrawal of staked tokens
     * @dev Only available when contract is paused, forfeits rewards
     */
    function emergencyWithdraw() external;

    /**
     * @notice Calculates rewards for a given stake
     * @param _stake Stake struct to calculate rewards for
     * @return uint256 Amount of rewards earned
     */
    function calculateRewards(Stake memory _stake) external view returns (uint256);

    /**
     * @notice Gets the tier level based on staked amount
     * @param amount Amount of tokens to check
     * @return uint256 Tier level (0-3)
     */
    function getUserTier(uint256 amount) external pure returns (uint256);

    /**
     * @notice Calculates the lock period multiplier
     * @param lockPeriod Duration of lock in seconds
     * @return uint256 Multiplier in basis points (100 = 1%)
     */
    function getLockMultiplier(uint256 lockPeriod) external pure returns (uint256);

    /**
     * @notice Gets the tier multiplier
     * @param tier Tier level to get multiplier for
     * @return uint256 Multiplier in basis points (100 = 1%)
     */
    function getTierMultiplier(uint256 tier) external pure returns (uint256);

    /**
     * @notice Gets detailed information about a user's stake
     * @param user Address to query
     * @return amount Amount staked
     * @return startTime Start timestamp
     * @return lockPeriod Lock duration
     * @return tier Current tier
     * @return rewards Pending rewards
     * @return active Whether stake is active
     */
    function getStakeInfo(address user) external view returns (
        uint256 amount,
        uint256 startTime,
        uint256 lockPeriod,
        uint256 tier,
        uint256 rewards,
        bool active
    );

    /**
     * @notice Gets the total amount of tokens staked
     * @return uint256 Total staked amount
     */
    function totalStaked() external view returns (uint256);

    /**
     * @notice Gets a user's stake details
     * @param user Address to query
     * @return Stake struct containing stake details
     */
    function stakes(address user) external view returns (Stake memory);

    /**
     * @notice Pauses staking operations
     * @dev Only callable by operator role
     */
    function pause() external;

    /**
     * @notice Resumes staking operations
     * @dev Only callable by operator role
     */
    function unpause() external;

    /**
     * @notice Emitted when tokens are staked
     * @param user Address of the staker
     * @param amount Amount of tokens staked
     * @param lockPeriod Duration of the lock
     */
    event Staked(address indexed user, uint256 amount, uint256 lockPeriod);

    /**
     * @notice Emitted when tokens are unstaked
     * @param user Address of the staker
     * @param amount Amount of tokens unstaked
     * @param rewards Amount of rewards claimed
     */
    event Unstaked(address indexed user, uint256 amount, uint256 rewards);

    /**
     * @notice Emitted when rewards are claimed
     * @param user Address of the claimer
     * @param amount Amount of rewards claimed
     */
    event RewardsClaimed(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user's tier changes
     * @param user Address of the user
     * @param oldTier Previous tier level
     * @param newTier New tier level
     */
    event TierUpgraded(address indexed user, uint256 oldTier, uint256 newTier);

    // Constants
    function TIER1_THRESHOLD() external pure returns (uint256);
    function TIER2_THRESHOLD() external pure returns (uint256);
    function TIER3_THRESHOLD() external pure returns (uint256);
    function TIER1_DISCOUNT() external pure returns (uint256);
    function TIER2_DISCOUNT() external pure returns (uint256);
    function TIER3_DISCOUNT() external pure returns (uint256);
    function MIN_LOCK_PERIOD() external pure returns (uint256);
    function MAX_LOCK_PERIOD() external pure returns (uint256);
    function WEEKLY_BONUS() external pure returns (uint256);
    function BASE_RATE() external pure returns (uint256);

    /**
     * @notice Gets user staking information
     * @param _user User address
     * @return stakedAmount Amount staked
     * @return lockDuration Lock duration in seconds
     */
    function getUserStakeInfo(address _user) external view returns (uint256 stakedAmount, uint256 lockDuration);
    
    /**
     * @notice Checks if user is eligible for a specific tier
     * @param _user User address
     * @param _tier Tier level
     * @return isEligible Whether user is eligible
     */
    function isEligibleForTier(address _user, uint256 _tier) external view returns (bool isEligible);

    /**
     * @notice Gets user's voting power based on stake amount and duration
     * @param _user User address
     * @return votingPower Voting power in basis points
     */
    function getVotingPower(address _user) external view returns (uint256 votingPower);

    /**
     * @notice Gets user's APY based on tier and lock duration
     * @param _user User address
     * @return apy Annual percentage yield in basis points
     */
    function getUserAPY(address _user) external view returns (uint256 apy);
} 