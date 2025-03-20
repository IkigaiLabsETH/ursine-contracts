// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IBuybackEngine.sol";

/**
 * @title TreasuryV2
 * @notice Manages protocol treasury with advanced tokenomics features
 * @dev Includes milestone-based unlocks and adaptive fee structure
 */
contract TreasuryV2 is ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // Token references
    IERC20 public immutable ikigaiToken;
    IERC20 public immutable stablecoin;

    // Treasury parameters
    uint256 public constant TARGET_LIQUIDITY_RATIO = 2000; // 20% of treasury
    uint256 public constant REBALANCING_THRESHOLD = 500;   // 5% threshold
    uint256 public constant MAX_SLIPPAGE = 100;           // 1% max slippage
    uint256 public constant MIN_LIQUIDITY = 1000 * 10**18; // 1,000 tokens

    // Distribution ratios (in basis points)
    uint256 public constant BUYBACK_SHARE = 2500;   // 25% (increased from 20%)
    uint256 public constant STAKING_SHARE = 4000;   // 40% (reduced from 50%)
    uint256 public constant LIQUIDITY_SHARE = 2500; // 25% (reduced from 30%)
    uint256 public constant OPERATIONS_SHARE = 1500; // 15% unchanged

    // Addresses
    address public stakingContract;
    address public liquidityPool;
    address public operationsWallet;
    address public burnAddress;

    // Treasury state
    uint256 public totalAssets;
    uint256 public liquidityBalance;
    uint256 public lastRebalance;

    // Add buyback engine reference
    IBuybackEngine public buybackEngine;

    // Fee structure
    uint256 public baseFee = 300; // 3%
    uint256 public minFee = 100;  // 1%
    uint256 public maxFee = 500;  // 5%
    
    // Milestone-based unlocks
    struct Milestone {
        string description;
        uint256 tokenAmount;
        bool achieved;
        uint256 unlockTime;
        uint256 releasedAmount;
    }
    
    Milestone[] public milestones;
    mapping(uint256 => uint256) public milestoneUnlockTime;

    // Add loyalty-based fee discounts
    mapping(address => uint256) public userFirstActivityTime;
    uint256 public constant LOYALTY_DISCOUNT_PER_YEAR = 500; // 5% per year
    uint256 public constant MAX_LOYALTY_DISCOUNT = 2000; // 20% max

    // Events
    event RevenueDistributed(
        uint256 buybackAmount,
        uint256 stakingAmount,
        uint256 liquidityAmount,
        uint256 operationsAmount
    );
    event LiquidityRebalanced(uint256 amount, bool added);
    event AddressesUpdated(
        address stakingContract,
        address liquidityPool,
        address operationsWallet
    );
    event AdaptiveDistribution(
        uint256 buybackAmount,
        uint256 stakingAmount,
        uint256 liquidityAmount,
        uint256 operationsAmount,
        uint256 adaptiveBuybackShare
    );
    event EmergencyRecovery(address indexed token, uint256 amount);
    event FeeCollected(address indexed from, uint256 amount, uint256 fee);
    event FeeParametersUpdated(uint256 baseFee, uint256 minFee, uint256 maxFee);
    event MilestoneAdded(uint256 indexed index, string description, uint256 tokenAmount);
    event MilestoneAchieved(uint256 indexed index, string description, uint256 delay);
    event MilestoneTokensClaimed(uint256 indexed index, address recipient, uint256 amount);
    event FundsWithdrawn(address indexed token, address indexed recipient, uint256 amount);

    constructor(
        address _ikigaiToken,
        address _stablecoin,
        address _buybackEngine,
        address _admin,
        address _stakingContract,
        address _liquidityPool,
        address _operationsWallet
    ) {
        require(_ikigaiToken != address(0), "Invalid token");
        
        ikigaiToken = IERC20(_ikigaiToken);
        stablecoin = IERC20(_stablecoin);
        stakingContract = _stakingContract;
        liquidityPool = _liquidityPool;
        operationsWallet = _operationsWallet;
        burnAddress = address(0xdead);
        buybackEngine = IBuybackEngine(_buybackEngine);

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(OPERATOR_ROLE, _admin);
        _setupRole(REBALANCER_ROLE, _admin);
        _setupRole(GOVERNANCE_ROLE, _admin);

        lastRebalance = block.timestamp;
    }

    // Update critical addresses
    function updateAddresses(
        address _stakingContract,
        address _liquidityPool,
        address _operationsWallet
    ) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not admin");
        require(_stakingContract != address(0), "Invalid staking contract");
        require(_liquidityPool != address(0), "Invalid liquidity pool");
        require(_operationsWallet != address(0), "Invalid operations wallet");

        stakingContract = _stakingContract;
        liquidityPool = _liquidityPool;
        operationsWallet = _operationsWallet;

        emit AddressesUpdated(_stakingContract, _liquidityPool, _operationsWallet);
    }

    // Distribute revenue according to ratios
    function distributeRevenue() external nonReentrant whenNotPaused {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Caller is not operator");
        
        uint256 balance = ikigaiToken.balanceOf(address(this));
        require(balance > 0, "No tokens to distribute");

        // Calculate shares including buyback
        uint256 buybackAmount = (balance * BUYBACK_SHARE) / 10000;
        uint256 stakingAmount = (balance * STAKING_SHARE) / 10000;
        uint256 liquidityAmount = (balance * LIQUIDITY_SHARE) / 10000;
        uint256 operationsAmount = (balance * OPERATIONS_SHARE) / 10000;

        // Process buyback
        if (buybackAmount > 0) {
            ikigaiToken.safeApprove(address(buybackEngine), buybackAmount);
            buybackEngine.collectRevenue(keccak256("TREASURY_YIELD"), buybackAmount);
        }

        // Transfer shares
        if (stakingAmount > 0) {
            ikigaiToken.safeTransfer(stakingContract, stakingAmount);
        }
        if (liquidityAmount > 0) {
            ikigaiToken.safeTransfer(liquidityPool, liquidityAmount);
        }
        if (operationsAmount > 0) {
            ikigaiToken.safeTransfer(operationsWallet, operationsAmount);
        }

        emit RevenueDistributed(
            buybackAmount,
            stakingAmount,
            liquidityAmount,
            operationsAmount
        );
    }

    // Check if rebalancing is needed
    function needsRebalancing() public view returns (bool, bool) {
        uint256 currentRatio = (liquidityBalance * 10000) / totalAssets;
        
        if (currentRatio < TARGET_LIQUIDITY_RATIO - REBALANCING_THRESHOLD) {
            return (true, true); // Needs more liquidity
        }
        if (currentRatio > TARGET_LIQUIDITY_RATIO + REBALANCING_THRESHOLD) {
            return (true, false); // Needs less liquidity
        }
        
        return (false, false);
    }

    // Rebalance liquidity
    function rebalanceLiquidity() external nonReentrant whenNotPaused {
        require(hasRole(REBALANCER_ROLE, msg.sender), "Caller is not rebalancer");
        require(block.timestamp >= lastRebalance + 1 days, "Too soon to rebalance");

        (bool shouldRebalance, bool addLiquidity) = needsRebalancing();
        require(shouldRebalance, "No rebalancing needed");

        uint256 targetLiquidity = (totalAssets * TARGET_LIQUIDITY_RATIO) / 10000;
        uint256 difference = addLiquidity ? 
            targetLiquidity - liquidityBalance :
            liquidityBalance - targetLiquidity;

        require(difference >= MIN_LIQUIDITY, "Below minimum liquidity change");

        if (addLiquidity) {
            // Add liquidity logic here
            liquidityBalance += difference;
        } else {
            // Remove liquidity logic here
            liquidityBalance -= difference;
        }

        lastRebalance = block.timestamp;
        emit LiquidityRebalanced(difference, addLiquidity);
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

    // View functions
    function getTreasuryStats() external view returns (
        uint256 _totalAssets,
        uint256 _liquidityBalance,
        uint256 _liquidityRatio,
        uint256 _lastRebalance
    ) {
        _liquidityRatio = (liquidityBalance * 10000) / totalAssets;
        return (
            totalAssets,
            liquidityBalance,
            _liquidityRatio,
            lastRebalance
        );
    }

    // Add bull market reserve function
    function allocateBullMarketReserve() external nonReentrant whenNotPaused {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Caller is not operator");
        require(buybackEngine.getCurrentPrice() >= buybackEngine.BULL_PRICE_THRESHOLD(), "Not bull market");
        
        uint256 balance = ikigaiToken.balanceOf(address(this));
        uint256 bullMarketAmount = (balance * 1000) / 10000; // 10% to bull market reserve
        
        if (bullMarketAmount > 0) {
            ikigaiToken.safeApprove(address(buybackEngine), bullMarketAmount);
            buybackEngine.collectRevenue(keccak256("BULL_MARKET_RESERVE"), bullMarketAmount);
        }
    }

    // Add function to handle adaptive distribution based on market conditions
    function adaptiveDistribution() external nonReentrant whenNotPaused {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Caller is not operator");
        
        uint256 currentPrice = buybackEngine.getCurrentPrice();
        uint256 balance = ikigaiToken.balanceOf(address(this));
        require(balance > 0, "No tokens to distribute");
        
        // Increase buyback allocation in bear market
        uint256 adaptiveBuybackShare = BUYBACK_SHARE;
        if (currentPrice < 0.3e8) { // Below $0.30
            adaptiveBuybackShare = 3500; // 35%
        } else if (currentPrice < 0.5e8) { // Below $0.50
            adaptiveBuybackShare = 3000; // 30%
        }
        
        // Adjust staking share based on buyback change
        uint256 adjustedStakingShare = STAKING_SHARE - (adaptiveBuybackShare - BUYBACK_SHARE);
        
        uint256 buybackAmount = (balance * adaptiveBuybackShare) / 10000;
        uint256 stakingAmount = (balance * adjustedStakingShare) / 10000;
        uint256 liquidityAmount = (balance * LIQUIDITY_SHARE) / 10000;
        uint256 operationsAmount = (balance * OPERATIONS_SHARE) / 10000;
        
        // Process adaptive buyback
        if (buybackAmount > 0) {
            ikigaiToken.safeApprove(address(buybackEngine), buybackAmount);
            buybackEngine.collectRevenue(keccak256("ADAPTIVE_TREASURY_YIELD"), buybackAmount);
        }
        
        // Transfer other shares
        if (stakingAmount > 0) {
            ikigaiToken.safeTransfer(stakingContract, stakingAmount);
        }
        if (liquidityAmount > 0) {
            ikigaiToken.safeTransfer(liquidityPool, liquidityAmount);
        }
        if (operationsAmount > 0) {
            ikigaiToken.safeTransfer(operationsWallet, operationsAmount);
        }
        
        emit AdaptiveDistribution(
            buybackAmount,
            stakingAmount,
            liquidityAmount,
            operationsAmount,
            adaptiveBuybackShare
        );
    }

    // Add emergency token recovery
    function emergencyTokenRecovery(address token, uint256 amount) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Must be admin");
        require(paused(), "Contract not paused");
        
        IERC20(token).safeTransfer(msg.sender, amount);
        emit EmergencyRecovery(token, amount);
    }

    /**
     * @notice Collects fee with adaptive rate
     * @param _from Address to collect from
     * @param _amount Amount to collect fee on
     * @return Fee amount collected
     */
    function collectFee(address _from, uint256 _amount) external nonReentrant returns (uint256) {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Not operator");
        require(_amount > 0, "Zero amount");
        
        uint256 feeRate = calculateDynamicFee(_amount, _from);
        uint256 feeAmount = (_amount * feeRate) / 10000;
        
        // Transfer fee
        ikigaiToken.safeTransferFrom(_from, address(this), feeAmount);
        
        emit FeeCollected(_from, _amount, feeAmount);
        
        return feeAmount;
    }
    
    /**
     * @notice Calculates dynamic fee based on transaction size
     * @param _transactionValue Value of the transaction
     * @return Fee rate in basis points
     */
    function calculateDynamicFee(uint256 _transactionValue, address _user) public view returns (uint256) {
        // Base fee for standard transactions
        uint256 fee = baseFee;
        uint256 totalDiscount = 0;
        
        // Volume discount
        if (_transactionValue > 10000e18) { // > 10,000 tokens
            totalDiscount += 1000; // 10% discount
        }
        
        if (_transactionValue > 100000e18) { // > 100,000 tokens
            totalDiscount += 1000; // Additional 10% discount
        }
        
        // Cap whale discount at 25%
        if (totalDiscount > 2500) totalDiscount = 2500;
        
        // Loyalty discount
        if (userFirstActivityTime[_user] > 0) {
            uint256 yearsActive = (block.timestamp - userFirstActivityTime[_user]) / 365 days;
            uint256 loyaltyDiscount = yearsActive * LOYALTY_DISCOUNT_PER_YEAR;
            
            if (loyaltyDiscount > MAX_LOYALTY_DISCOUNT) {
                loyaltyDiscount = MAX_LOYALTY_DISCOUNT;
            }
            
            totalDiscount += loyaltyDiscount;
        }
        
        // Apply total discount
        fee = fee * (10000 - totalDiscount) / 10000;
        
        // Ensure fee is within bounds
        if (fee < minFee) return minFee;
        if (fee > maxFee) return maxFee;
        
        return fee;
    }
    
    /**
     * @notice Updates fee parameters
     * @param _baseFee New base fee
     * @param _minFee New minimum fee
     * @param _maxFee New maximum fee
     */
    function updateFeeParameters(
        uint256 _baseFee,
        uint256 _minFee,
        uint256 _maxFee
    ) external {
        require(hasRole(GOVERNANCE_ROLE, msg.sender), "Not governance");
        require(_minFee <= _baseFee && _baseFee <= _maxFee, "Invalid fee range");
        require(_maxFee <= 1000, "Max fee too high");
        
        baseFee = _baseFee;
        minFee = _minFee;
        maxFee = _maxFee;
        
        emit FeeParametersUpdated(_baseFee, _minFee, _maxFee);
    }
    
    /**
     * @notice Adds a new milestone
     * @param _description Milestone description
     * @param _tokenAmount Token amount to unlock
     */
    function addMilestone(string memory _description, uint256 _tokenAmount) external {
        require(hasRole(GOVERNANCE_ROLE, msg.sender), "Not governance");
        require(bytes(_description).length > 0, "Empty description");
        require(_tokenAmount > 0, "Zero amount");
        
        milestones.push(Milestone({
            description: _description,
            tokenAmount: _tokenAmount,
            achieved: false,
            unlockTime: 0,
            releasedAmount: 0
        }));
        
        emit MilestoneAdded(milestones.length - 1, _description, _tokenAmount);
    }
    
    /**
     * @notice Marks a milestone as achieved
     * @param _index Milestone index
     */
    function achieveMilestone(uint256 _index) external {
        require(hasRole(GOVERNANCE_ROLE, msg.sender), "Not governance");
        require(_index < milestones.length, "Invalid milestone");
        require(!milestones[_index].achieved, "Already achieved");
        
        milestones[_index].achieved = true;
        
        // Calculate delay based on token amount
        uint256 amount = milestones[_index].tokenAmount;
        uint256 delay;
        
        if (amount < 1000000 * 1e18) { // < 1M tokens
            delay = 30 days;
        } else if (amount < 5000000 * 1e18) { // 1-5M tokens
            delay = 60 days;
        } else { // > 5M tokens
            delay = 90 days;
        }
        
        // Set unlock time
        milestoneUnlockTime[_index] = block.timestamp + delay;
        
        emit MilestoneAchieved(_index, milestones[_index].description, delay);
    }
    
    /**
     * @notice Claims tokens from an achieved milestone
     * @param _index Milestone index
     * @param _recipient Recipient of the tokens
     */
    function claimMilestoneTokens(uint256 _index, address _recipient) external {
        require(hasRole(GOVERNANCE_ROLE, msg.sender), "Not governance");
        require(_index < milestones.length, "Invalid milestone");
        require(milestones[_index].achieved, "Not achieved");
        require(block.timestamp >= milestoneUnlockTime[_index], "Not unlocked");
        require(_recipient != address(0), "Invalid recipient");
        
        Milestone storage milestone = milestones[_index];
        
        // Calculate release schedule (25% per month over 4 months)
        uint256 monthsSinceUnlock = (block.timestamp - milestoneUnlockTime[_index]) / 30 days;
        uint256 maxReleasePercentage = (monthsSinceUnlock + 1) * 25;
        if (maxReleasePercentage > 100) maxReleasePercentage = 100;
        
        uint256 maxReleasable = (milestone.tokenAmount * maxReleasePercentage) / 100;
        uint256 alreadyReleased = milestone.releasedAmount;
        
        require(maxReleasable > alreadyReleased, "No tokens to release");
        
        uint256 amount = maxReleasable - alreadyReleased;
        milestone.releasedAmount = maxReleasable;
        
        // Transfer tokens
        ikigaiToken.safeTransfer(_recipient, amount);
        
        emit MilestoneTokensClaimed(_index, _recipient, amount);
    }
    
    /**
     * @notice Withdraws funds from treasury
     * @param _token Token address
     * @param _recipient Recipient address
     * @param _amount Amount to withdraw
     */
    function withdrawFunds(
        address _token,
        address _recipient,
        uint256 _amount
    ) external nonReentrant {
        require(hasRole(GOVERNANCE_ROLE, msg.sender), "Not governance");
        require(_recipient != address(0), "Invalid recipient");
        require(_amount > 0, "Zero amount");
        
        IERC20(_token).safeTransfer(_recipient, _amount);
        
        emit FundsWithdrawn(_token, _recipient, _amount);
    }
    
    /**
     * @notice Gets all milestones
     * @return Array of milestones
     */
    function getAllMilestones() external view returns (Milestone[] memory) {
        return milestones;
    }
    
    /**
     * @notice Gets milestone count
     * @return Number of milestones
     */
    function getMilestoneCount() external view returns (uint256) {
        return milestones.length;
    }

    // Record first activity
    function recordUserActivity(address _user) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Not operator");
        
        if (userFirstActivityTime[_user] == 0) {
            userFirstActivityTime[_user] = block.timestamp;
        }
    }
} 