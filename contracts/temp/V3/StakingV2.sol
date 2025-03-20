// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IBuybackEngine.sol";
import "./interfaces/IStakingV2.sol";

/**
 * @title StakingV2
 * @notice Advanced staking system with tiered rewards and composable positions
 * @dev Implements flexible lock periods, tier-based multipliers, and governance weighting
 */
contract StakingV2 is IStakingV2, ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // Staking token
    IERC20 public immutable ikigaiToken;

    // Tier thresholds
    uint256 public constant TIER1_THRESHOLD = 1_000 * 10**18; // 1,000 IKIGAI
    uint256 public constant TIER2_THRESHOLD = 5_000 * 10**18; // 5,000 IKIGAI
    uint256 public constant TIER3_THRESHOLD = 15_000 * 10**18; // 15,000 IKIGAI
    uint256 public constant TIER0_THRESHOLD = 1000 * 10**18;   // 1,000 IKIGAI (entry tier)

    // Tier discounts (in basis points, 100 = 1%)
    uint256 public constant TIER1_DISCOUNT = 500;  // 5%
    uint256 public constant TIER2_DISCOUNT = 1500; // 15%
    uint256 public constant TIER3_DISCOUNT = 2500; // 25%
    uint256 public constant TIER0_DISCOUNT = 200;   // 2%

    // Lock periods
    uint256 public constant MIN_LOCK_PERIOD = 7 days;
    uint256 public constant MAX_LOCK_PERIOD = 365 days; // Increased from 28 days
    uint256 public constant WEEKLY_BONUS = 50; // 0.5% per week

    // Base staking rate (in basis points)
    uint256 public constant BASE_RATE = 1500; // 15%

    // Add buyback engine reference
    IBuybackEngine public buybackEngine;

    // Add buyback configuration
    uint256 public constant STAKING_BUYBACK_SHARE = 2500; // 25% (increased from 20%)

    // Add whitelist for fee exemption
    mapping(address => bool) public feeExempt;

    // Add loyalty bonus
    mapping(address => uint256) public userFirstStakeTime;
    uint256 public constant LOYALTY_APY_BONUS_PER_YEAR = 200; // 2% per year
    uint256 public constant MAX_LOYALTY_APY_BONUS = 1000; // 10% max

    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        uint256 lastClaimTime;
        uint256 lockPeriod;
        uint256 tier;
        bool active;
    }

    // Stake storage
    mapping(uint256 => Stake) public stakes;
    mapping(uint256 => address) public stakeOwner;
    mapping(address => uint256[]) public userStakeIds;
    uint256 public nextStakeId = 1;

    // Rewards tracking
    mapping(address => uint256) public pendingRewards;
    uint256 public totalStaked;
    uint256 public totalRewardsDistributed;

    // Events
    event Staked(address indexed user, uint256 indexed stakeId, uint256 amount, uint256 lockPeriod);
    event Unstaked(address indexed user, uint256 indexed stakeId, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event StakeCombined(address indexed user, uint256[] oldStakeIds, uint256 newStakeId);
    event StakeSplit(address indexed user, uint256 oldStakeId, uint256[] newStakeIds);

    constructor(address _ikigaiToken, address _buybackEngine) {
        require(_ikigaiToken != address(0), "Invalid token");
        require(_buybackEngine != address(0), "Invalid buyback engine");
        
        ikigaiToken = IERC20(_ikigaiToken);
        buybackEngine = IBuybackEngine(_buybackEngine);
        
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
    }

    /**
     * @notice Stakes tokens for rewards
     * @param _amount Amount to stake
     * @param _lockPeriod Lock period in seconds
     */
    function stake(uint256 _amount, uint256 _lockPeriod) external nonReentrant whenNotPaused {
        require(_amount > 0, "Zero amount");
        require(_lockPeriod >= MIN_LOCK_PERIOD, "Lock period too short");
        require(_lockPeriod <= MAX_LOCK_PERIOD, "Lock period too long");
        
        // Transfer tokens from user
        ikigaiToken.safeTransferFrom(msg.sender, address(this), _amount);
        
        // Determine tier based on amount
        uint256 tier = 0;
        if (_amount >= TIER3_THRESHOLD) {
            tier = 3;
        } else if (_amount >= TIER2_THRESHOLD) {
            tier = 2;
        } else if (_amount >= TIER1_THRESHOLD) {
            tier = 1;
        }
        
        // Create stake
        uint256 stakeId = nextStakeId++;
        stakes[stakeId] = Stake({
            amount: _amount,
            startTime: block.timestamp,
            endTime: block.timestamp + _lockPeriod,
            lastClaimTime: block.timestamp,
            lockPeriod: _lockPeriod,
            tier: tier,
            active: true
        });
        
        stakeOwner[stakeId] = msg.sender;
        userStakeIds[msg.sender].push(stakeId);
        totalStaked += _amount;
        
        // Track first stake time for loyalty bonus
        if (userFirstStakeTime[msg.sender] == 0) {
            userFirstStakeTime[msg.sender] = block.timestamp;
        }
        
        emit Staked(msg.sender, stakeId, _amount, _lockPeriod);
    }

    /**
     * @notice Unstakes tokens after lock period
     * @param _stakeId Stake ID to unstake
     */
    function unstake(uint256 _stakeId) external nonReentrant {
        require(stakeOwner[_stakeId] == msg.sender, "Not owner");
        
        Stake storage userStake = stakes[_stakeId];
        require(userStake.active, "Not active");
        require(block.timestamp >= userStake.endTime, "Still locked");
        
        // Calculate rewards
        uint256 rewards = calculateRewards(_stakeId);
        if (rewards > 0) {
            pendingRewards[msg.sender] += rewards;
        }
        
        // Update state
        userStake.active = false;
        totalStaked -= userStake.amount;
        
        // Transfer tokens back to user
        ikigaiToken.safeTransfer(msg.sender, userStake.amount);
        
        emit Unstaked(msg.sender, _stakeId, userStake.amount);
    }

    /**
     * @notice Claims pending rewards
     */
    function claimRewards() external nonReentrant {
        uint256 rewards = pendingRewards[msg.sender];
        require(rewards > 0, "No rewards");
        
        pendingRewards[msg.sender] = 0;
        totalRewardsDistributed += rewards;
        
        // Transfer rewards to user
        ikigaiToken.safeTransfer(msg.sender, rewards);
        
        emit RewardsClaimed(msg.sender, rewards);
    }

    /**
     * @notice Combines multiple stakes into a single stake
     * @param _stakeIds Array of stake IDs to combine
     * @return New stake ID
     */
    function combineStakes(uint256[] calldata _stakeIds) external nonReentrant returns (uint256) {
        require(_stakeIds.length > 1, "Need at least 2 stakes");
        
        uint256 totalAmount = 0;
        uint256 weightedLockPeriod = 0;
        uint256 historicalCommitment = 0;
        
        // Verify ownership and calculate combined properties
        for (uint256 i = 0; i < _stakeIds.length; i++) {
            uint256 stakeId = _stakeIds[i];
            require(stakeOwner[stakeId] == msg.sender, "Not owner of all stakes");
            
            Stake storage userStake = stakes[stakeId];
            require(userStake.active, "Stake not active");
            
            // Calculate time already staked
            uint256 timeStaked = block.timestamp - userStake.startTime;
            
            // Add historical commitment bonus (5% of time already staked)
            historicalCommitment += (timeStaked * userStake.amount * 5) / 100;
            
            // Add rewards to pending rewards
            uint256 rewards = calculateRewards(stakeId);
            if (rewards > 0) {
                pendingRewards[msg.sender] += rewards;
            }
            
            // Calculate weighted lock period
            weightedLockPeriod += userStake.amount * userStake.lockPeriod;
            totalAmount += userStake.amount;
        }
        
        // Calculate final weighted lock period with historical bonus
        weightedLockPeriod = (weightedLockPeriod + historicalCommitment) / totalAmount;
        
        // Create new combined stake
        uint256 newStakeId = _createStake(totalAmount, weightedLockPeriod);
        
        // Close original stakes
        for (uint256 i = 0; i < _stakeIds.length; i++) {
            stakes[_stakeIds[i]].active = false;
            totalStaked -= stakes[_stakeIds[i]].amount;
        }
        
        emit StakeCombined(msg.sender, _stakeIds, newStakeId);
        
        return newStakeId;
    }

    /**
     * @notice Creates a new stake
     * @param _amount Amount to stake
     * @param _lockPeriod Lock period in seconds
     * @return New stake ID
     */
    function _createStake(uint256 _amount, uint256 _lockPeriod) internal returns (uint256) {
        // Determine tier based on amount
        uint256 tier = 0;
        if (_amount >= TIER3_THRESHOLD) {
            tier = 3;
        } else if (_amount >= TIER2_THRESHOLD) {
            tier = 2;
        } else if (_amount >= TIER1_THRESHOLD) {
            tier = 1;
        }
        
        // Create stake
        uint256 stakeId = nextStakeId++;
        stakes[stakeId] = Stake({
            amount: _amount,
            startTime: block.timestamp,
            endTime: block.timestamp + _lockPeriod,
            lastClaimTime: block.timestamp,
            lockPeriod: _lockPeriod,
            tier: tier,
            active: true
        });
        
        stakeOwner[stakeId] = msg.sender;
        userStakeIds[msg.sender].push(stakeId);
        totalStaked += _amount;
        
        return stakeId;
    }

    /**
     * @notice Calculates rewards for a stake
     * @param _stakeId Stake ID
     * @return Rewards amount
     */
    function calculateRewards(uint256 _stakeId) public view returns (uint256) {
        Stake storage userStake = stakes[_stakeId];
        if (!userStake.active) return 0;
        
        uint256 timeElapsed = block.timestamp - userStake.lastClaimTime;
        if (timeElapsed == 0) return 0;
        
        // Calculate APY based on tier and lock period
        uint256 apy = BASE_RATE;
        
        // Add tier bonus
        if (userStake.amount >= TIER0_THRESHOLD && userStake.amount < TIER1_THRESHOLD) {
            apy += TIER0_DISCOUNT;
        } else if (userStake.tier == 1) {
            apy += TIER1_DISCOUNT;
        } else if (userStake.tier == 2) {
            apy += TIER2_DISCOUNT;
        } else if (userStake.tier == 3) {
            apy += TIER3_DISCOUNT;
        }
        
        // Add lock period bonus
        uint256 weeklyBonus = (userStake.lockPeriod / 1 weeks) * WEEKLY_BONUS;
        apy += weeklyBonus;
        
        // Add loyalty bonus
        address owner = stakeOwner[_stakeId];
        if (userFirstStakeTime[owner] > 0) {
            uint256 yearsStaking = (block.timestamp - userFirstStakeTime[owner]) / 365 days;
            uint256 loyaltyBonus = yearsStaking * LOYALTY_APY_BONUS_PER_YEAR;
            if (loyaltyBonus > MAX_LOYALTY_APY_BONUS) {
                loyaltyBonus = MAX_LOYALTY_APY_BONUS;
            }
            apy += loyaltyBonus;
        }
        
        // Calculate rewards
        uint256 rewards = (userStake.amount * apy * timeElapsed) / (10000 * 365 days);
        
        return rewards;
    }

    /**
     * @notice Gets user's voting power based on stake amount and duration
     * @param _user User address
     * @return Voting power
     */
    function getVotingPower(address _user) external view override returns (uint256) {
        uint256[] memory userStakes = userStakeIds[_user];
        uint256 totalVotingPower = 0;
        
        for (uint256 i = 0; i < userStakes.length; i++) {
            Stake storage userStake = stakes[userStakes[i]];
            if (userStake.active) {
                // Voting power increases with stake amount and duration
                uint256 durationMultiplier = userStake.lockPeriod / 30 days;
                if (durationMultiplier > 4) durationMultiplier = 4;
                if (durationMultiplier == 0) durationMultiplier = 1;
                
                totalVotingPower += userStake.amount * durationMultiplier / 4;
            }
        }
        
        return totalVotingPower;
    }

    /**
     * @notice Gets user's APY based on tier and lock duration
     * @param _user User address
     * @return apy Annual percentage yield in basis points
     */
    function getUserAPY(address _user) external view override returns (uint256 apy) {
        uint256[] memory userStakes = userStakeIds[_user];
        if (userStakes.length == 0) return 0;
        
        uint256 totalStaked = 0;
        uint256 weightedApy = 0;
        
        for (uint256 i = 0; i < userStakes.length; i++) {
            Stake storage userStake = stakes[userStakes[i]];
            if (userStake.active) {
                // Calculate base APY based on tier
                uint256 baseApy = BASE_RATE;
                if (userStake.amount >= TIER0_THRESHOLD && userStake.amount < TIER1_THRESHOLD) {
                    baseApy = BASE_RATE + TIER0_DISCOUNT;
                } else if (userStake.tier == 1) {
                    baseApy = BASE_RATE + TIER1_DISCOUNT;
                } else if (userStake.tier == 2) {
                    baseApy = BASE_RATE + TIER2_DISCOUNT;
                } else if (userStake.tier == 3) {
                    baseApy = BASE_RATE + TIER3_DISCOUNT;
                }
                
                // Calculate lock duration bonus
                uint256 weeklyBonus = (userStake.lockPeriod / 1 weeks) * WEEKLY_BONUS;
                
                // Calculate loyalty bonus
                uint256 loyaltyBonus = 0;
                if (userFirstStakeTime[_user] > 0) {
                    uint256 yearsStaking = (block.timestamp - userFirstStakeTime[_user]) / 365 days;
                    loyaltyBonus = yearsStaking * LOYALTY_APY_BONUS_PER_YEAR;
                    if (loyaltyBonus > MAX_LOYALTY_APY_BONUS) {
                        loyaltyBonus = MAX_LOYALTY_APY_BONUS;
                    }
                }
                
                uint256 stakeApy = baseApy + weeklyBonus + loyaltyBonus;
                
                // Add weighted APY
                weightedApy += userStake.amount * stakeApy;
                totalStaked += userStake.amount;
            }
        }
        
        if (totalStaked == 0) return 0;
        return weightedApy / totalStaked;
    }
} 