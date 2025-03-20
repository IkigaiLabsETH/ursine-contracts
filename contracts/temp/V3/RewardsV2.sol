// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IBuybackEngine.sol";

contract RewardsV2 is ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // Token reference
    IERC20 public immutable ikigaiToken;

    // Trading reward tiers (in BERA)
    uint256 public constant TIER1_THRESHOLD = 100 * 10**18;  // 100 BERA
    uint256 public constant TIER2_THRESHOLD = 500 * 10**18;  // 500 BERA
    uint256 public constant TIER3_THRESHOLD = 1000 * 10**18; // 1000 BERA

    // Reward rates (in basis points)
    uint256 public constant BASE_RATE = 300;     // 3%
    uint256 public constant TIER2_RATE = 350;    // 3.5%
    uint256 public constant TIER3_RATE = 400;    // 4%
    uint256 public constant BASE_REFERRAL = 100; // 1%

    // Combo multipliers (in basis points)
    uint256 public constant COMBO_2X = 15000;  // 1.5x
    uint256 public constant COMBO_3X = 20000;  // 2x
    uint256 public constant COMBO_4X = 30000;  // 3x
    uint256 public constant COMBO_5X = 50000;  // 5x

    // Time windows
    uint256 public constant COMBO_WINDOW = 24 hours;
    uint256 public constant WEEKLY_WINDOW = 7 days;
    uint256 public constant HOLD_TIME = 30 days;

    // Bonuses (in basis points)
    uint256 public constant WEEKLY_BONUS = 2000;  // 20%
    uint256 public constant HOLD_BONUS = 1000;    // 10%

    // Referral limits
    uint256 public constant MAX_REFERRALS = 100;
    uint256 public constant MIN_TRADE_FOR_REFERRAL = 0.1 * 10**18; // 0.1 BERA

    // Add buyback engine reference
    IBuybackEngine public buybackEngine;
    
    // Add buyback configuration
    uint256 public constant TRADING_BUYBACK_SHARE = 3000; // 30% of trading fees to buyback

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

    // Mappings
    mapping(address => UserStats) public userStats;
    mapping(address => address[]) public userReferrals;

    // Events
    event TradeRewardPaid(
        address indexed user,
        uint256 amount,
        uint256 multiplier,
        uint256 comboCount
    );
    event ReferralRewardPaid(
        address indexed referrer,
        address indexed trader,
        uint256 amount
    );
    event ComboAchieved(address indexed user, uint256 comboCount);
    event ReferralAdded(
        address indexed referrer,
        address indexed referred
    );
    event EmergencyRewardPaid(address indexed trader, uint256 amount);
    event EmergencyRecovery(address indexed token, uint256 amount);

    constructor(
        address _ikigaiToken,
        address _buybackEngine,
        address _admin
    ) {
        ikigaiToken = IERC20(_ikigaiToken);
        buybackEngine = IBuybackEngine(_buybackEngine);
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(OPERATOR_ROLE, _admin);
    }

    // Calculate trading reward tier
    function getRewardTier(uint256 amount) public pure returns (uint256) {
        if (amount >= TIER3_THRESHOLD) return TIER3_RATE;
        if (amount >= TIER2_THRESHOLD) return TIER2_RATE;
        return BASE_RATE;
    }

    // Calculate combo multiplier
    function getComboMultiplier(uint256 comboCount) public pure returns (uint256) {
        if (comboCount >= 5) return COMBO_5X;
        if (comboCount >= 4) return COMBO_4X;
        if (comboCount >= 3) return COMBO_3X;
        if (comboCount >= 2) return COMBO_2X;
        return 10000; // 1x
    }

    // Add referral
    function addReferral(address referrer) external {
        require(referrer != msg.sender, "Cannot refer self");
        require(referrer != address(0), "Invalid referrer");
        require(!userStats[msg.sender].isActive, "Already has referrer");
        require(userReferrals[referrer].length < MAX_REFERRALS, "Max referrals reached");

        userStats[msg.sender].referrer = referrer;
        userStats[msg.sender].isActive = true;
        userReferrals[referrer].push(msg.sender);

        emit ReferralAdded(referrer, msg.sender);
    }

    // Process trading reward
    function processTradingReward(
        address trader,
        uint256 tradeAmount
    ) external nonReentrant whenNotPaused {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Caller is not operator");
        require(tradeAmount > 0, "Invalid trade amount");

        UserStats storage stats = userStats[trader];
        
        // Update combo count if within window
        if (block.timestamp <= stats.lastTradeTime + COMBO_WINDOW) {
            stats.comboCount++;
            emit ComboAchieved(trader, stats.comboCount);
        } else {
            stats.comboCount = 1;
        }

        // Update weekly stats
        if (block.timestamp >= stats.lastWeeklyReset + WEEKLY_WINDOW) {
            stats.weeklyVolume = 0;
            stats.weeklyTradeCount = 0;
            stats.lastWeeklyReset = block.timestamp;
        }
        stats.weeklyVolume += tradeAmount;
        stats.weeklyTradeCount++;

        // Calculate reward
        uint256 baseReward = (tradeAmount * getRewardTier(tradeAmount)) / 10000;
        uint256 comboMultiplier = getComboMultiplier(stats.comboCount);
        
        // Add weekly activity bonus if applicable
        if (stats.weeklyTradeCount >= 5) {
            comboMultiplier = (comboMultiplier * (10000 + WEEKLY_BONUS)) / 10000;
        }

        // Add hold time bonus if applicable
        if (stats.holdStartTime > 0 && 
            block.timestamp >= stats.holdStartTime + HOLD_TIME) {
            comboMultiplier = (comboMultiplier * (10000 + HOLD_BONUS)) / 10000;
        }

        uint256 finalReward = (baseReward * comboMultiplier) / 10000;
        stats.totalRewards += finalReward;

        // Process referral reward if applicable
        if (stats.referrer != address(0) && tradeAmount >= MIN_TRADE_FOR_REFERRAL) {
            uint256 referralReward = (baseReward * BASE_REFERRAL) / 10000;
            ikigaiToken.safeTransfer(stats.referrer, referralReward);
            emit ReferralRewardPaid(stats.referrer, trader, referralReward);
        }

        // Update state
        stats.lastTradeTime = block.timestamp;
        if (stats.holdStartTime == 0) {
            stats.holdStartTime = block.timestamp;
        }

        // Calculate and send buyback allocation
        uint256 buybackAmount = (tradeAmount * TRADING_BUYBACK_SHARE) / 10000;
        if (buybackAmount > 0) {
            ikigaiToken.safeApprove(address(buybackEngine), buybackAmount);
            buybackEngine.collectRevenue(keccak256("TRADING_FEES"), buybackAmount);
        }

        // Transfer reward
        ikigaiToken.safeTransfer(trader, finalReward);
        emit TradeRewardPaid(trader, finalReward, comboMultiplier, stats.comboCount);
    }

    // View functions
    function getUserStats(address user) external view returns (
        uint256 lastTradeTime,
        uint256 weeklyVolume,
        uint256 weeklyTradeCount,
        uint256 comboCount,
        uint256 totalRewards,
        address referrer,
        uint256 referralCount
    ) {
        UserStats memory stats = userStats[user];
        return (
            stats.lastTradeTime,
            stats.weeklyVolume,
            stats.weeklyTradeCount,
            stats.comboCount,
            stats.totalRewards,
            stats.referrer,
            userReferrals[user].length
        );
    }

    function getReferrals(address user) external view returns (address[] memory) {
        return userReferrals[user];
    }

    // Emergency functions
    function pause() external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Caller is not operator");
        _pause();
    }

    function unpause() external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Caller is not operator");
        _unpause();
    }

    // Add function to handle emergency rewards
    function emergencyRewardDistribution(
        address[] calldata traders,
        uint256[] calldata amounts
    ) external nonReentrant {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Caller is not operator");
        require(traders.length == amounts.length, "Array length mismatch");
        require(traders.length <= 100, "Batch too large"); // Prevent gas limit issues
        
        uint256 totalRewards = 0;
        for (uint i = 0; i < traders.length; i++) {
            require(traders[i] != address(0), "Invalid address");
            require(amounts[i] > 0, "Invalid amount");
            
            // Calculate total rewards to ensure we have enough balance
            totalRewards += calculateReward(amounts[i]);
        }
        
        require(ikigaiToken.balanceOf(address(this)) >= totalRewards, "Insufficient balance");
        
        // Process rewards
        for (uint i = 0; i < traders.length; i++) {
            // Process with reduced buyback
            uint256 reducedBuybackShare = TRADING_BUYBACK_SHARE / 2;
            uint256 buybackAmount = (amounts[i] * reducedBuybackShare) / 10000;
            
            if (buybackAmount > 0) {
                ikigaiToken.safeApprove(address(buybackEngine), buybackAmount);
                buybackEngine.collectRevenue(keccak256("EMERGENCY_TRADING_FEES"), buybackAmount);
            }
            
            uint256 rewardAmount = calculateReward(amounts[i]);
            ikigaiToken.safeTransfer(traders[i], rewardAmount);
            
            emit EmergencyRewardPaid(traders[i], rewardAmount);
        }
    }

    // Add missing calculateReward function
    function calculateReward(uint256 tradeAmount) public view returns (uint256) {
        uint256 baseReward = (tradeAmount * getRewardTier(tradeAmount)) / 10000;
        return baseReward;
    }

    // Add emergency token recovery
    function emergencyTokenRecovery(address token, uint256 amount) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Must be admin");
        require(paused(), "Contract not paused");
        
        IERC20(token).safeTransfer(msg.sender, amount);
        emit EmergencyRecovery(token, amount);
    }
} 