// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IRewardsV2
 * @notice Interface for the Ikigai V2 trading rewards and referral system
 * @dev Implements tiered rewards, combo multipliers, and referral tracking
 */
interface IRewardsV2 {
    /**
     * @notice Tracks user's trading statistics and rewards
     * @param lastTradeTime Timestamp of last trade
     * @param weeklyVolume Trading volume in current week
     * @param weeklyTradeCount Number of trades in current week
     * @param comboCount Consecutive trades within window
     * @param lastWeeklyReset Timestamp of last weekly stats reset
     * @param holdStartTime Start of holding period
     * @param totalRewards Total rewards earned
     * @param referrer Address that referred this user
     * @param referralCount Number of successful referrals
     * @param isActive Whether user has been referred
     */
    struct UserStats {
        uint256 lastTradeTime;
        uint256 weeklyVolume;
        uint256 weeklyTradeCount;
        uint256 comboCount;
        uint256 lastWeeklyReset;
        uint256 holdStartTime;
        uint256 totalRewards;
        address referrer;
        uint256 referralCount;
        bool isActive;
    }

    /**
     * @notice Adds a referrer for the caller
     * @dev Can only be set once per user
     * @param referrer Address to set as referrer
     */
    function addReferral(address referrer) external;

    /**
     * @notice Processes trading rewards for a completed trade
     * @dev Updates stats and distributes rewards
     * @param trader Address of the trader
     * @param tradeAmount Size of the trade in BERA
     */
    function processTradingReward(address trader, uint256 tradeAmount) external;

    /**
     * @notice Gets the reward tier based on trade amount
     * @param amount Trade amount to check
     * @return uint256 Reward rate in basis points
     */
    function getRewardTier(uint256 amount) external pure returns (uint256);

    /**
     * @notice Gets the combo multiplier based on consecutive trades
     * @param comboCount Number of consecutive trades
     * @return uint256 Multiplier in basis points
     */
    function getComboMultiplier(uint256 comboCount) external pure returns (uint256);

    /**
     * @notice Gets a user's trading statistics
     * @param user Address to query
     * @return lastTradeTime Last trade timestamp
     * @return weeklyVolume Current week's volume
     * @return weeklyTradeCount Current week's trade count
     * @return comboCount Current combo streak
     * @return totalRewards Total rewards earned
     * @return referrer Referrer address
     * @return referralCount Number of referrals
     */
    function getUserStats(address user) external view returns (
        uint256 lastTradeTime,
        uint256 weeklyVolume,
        uint256 weeklyTradeCount,
        uint256 comboCount,
        uint256 totalRewards,
        address referrer,
        uint256 referralCount
    );

    /**
     * @notice Gets all referrals made by a user
     * @param user Address to query
     * @return address[] Array of referred addresses
     */
    function getReferrals(address user) external view returns (address[] memory);

    /**
     * @notice Gets detailed user statistics
     * @param user Address to query
     * @return UserStats Complete user statistics
     */
    function userStats(address user) external view returns (
        uint256 lastTradeTime,
        uint256 weeklyVolume,
        uint256 weeklyTradeCount,
        uint256 comboCount,
        uint256 lastWeeklyReset,
        uint256 holdStartTime,
        uint256 totalRewards,
        address referrer,
        uint256 referralCount,
        bool isActive
    );

    /**
     * @notice Pauses reward distribution
     * @dev Only callable by operator role
     */
    function pause() external;

    /**
     * @notice Resumes reward distribution
     * @dev Only callable by operator role
     */
    function unpause() external;

    /**
     * @notice Emitted when trading rewards are paid
     * @param user Trader address
     * @param amount Reward amount
     * @param multiplier Applied multiplier
     * @param comboCount Current combo count
     */
    event TradeRewardPaid(
        address indexed user,
        uint256 amount,
        uint256 multiplier,
        uint256 comboCount
    );

    /**
     * @notice Emitted when referral rewards are paid
     * @param referrer Referrer address
     * @param trader Trader address
     * @param amount Reward amount
     */
    event ReferralRewardPaid(
        address indexed referrer,
        address indexed trader,
        uint256 amount
    );

    /**
     * @notice Emitted when a combo streak increases
     * @param user Trader address
     * @param comboCount New combo count
     */
    event ComboAchieved(address indexed user, uint256 comboCount);

    /**
     * @notice Emitted when a referral link is created
     * @param referrer Referrer address
     * @param referred New user address
     */
    event ReferralAdded(
        address indexed referrer,
        address indexed referred
    );

    // Constants
    function TIER1_THRESHOLD() external pure returns (uint256);
    function TIER2_THRESHOLD() external pure returns (uint256);
    function TIER3_THRESHOLD() external pure returns (uint256);
    function BASE_RATE() external pure returns (uint256);
    function TIER2_RATE() external pure returns (uint256);
    function TIER3_RATE() external pure returns (uint256);
    function BASE_REFERRAL() external pure returns (uint256);
    function COMBO_2X() external pure returns (uint256);
    function COMBO_3X() external pure returns (uint256);
    function COMBO_4X() external pure returns (uint256);
    function COMBO_5X() external pure returns (uint256);
    function COMBO_WINDOW() external pure returns (uint256);
    function WEEKLY_WINDOW() external pure returns (uint256);
    function HOLD_TIME() external pure returns (uint256);
    function WEEKLY_BONUS() external pure returns (uint256);
    function HOLD_BONUS() external pure returns (uint256);
    function MAX_REFERRALS() external pure returns (uint256);
    function MIN_TRADE_FOR_REFERRAL() external pure returns (uint256);
} 