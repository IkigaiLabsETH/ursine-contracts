// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IBuybackEngine.sol";

/**
 * @title EmissionController
 * @notice Manages token emission with adaptive rate control
 * @dev Adjusts emission rates based on market conditions
 */
contract EmissionController is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // Roles
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    // Token
    IERC20 public ikigaiToken;
    
    // Emission parameters
    uint256 public baseEmissionRate;
    uint256 public lastAdjustmentTime;
    uint256 public adjustmentCooldown = 7 days;
    uint256 public constant TARGET_PRICE_STABILITY = 500; // 5% max volatility
    uint256 public constant MAX_EMISSION_ADJUSTMENT = 2000; // 20% max adjustment
    
    // Price tracking
    IBuybackEngine public buybackEngine;
    
    // Emission caps
    uint256 public constant MAX_DAILY_EMISSION = 685000e18; // 685,000 tokens (250M / 365)
    uint256 public emissionReductionFactor = 9950; // 0.5% reduction per week (99.5%)
    uint256 public launchTimestamp;
    
    // Distribution
    mapping(address => uint256) public distributionShares;
    address[] public distributionRecipients;
    
    // Events
    event EmissionRateAdjusted(uint256 newRate, bool increased);
    event EmissionDistributed(address indexed recipient, uint256 amount);
    event DistributionShareUpdated(address indexed recipient, uint256 share);
    event AdjustmentCooldownUpdated(uint256 newCooldown);
    
    constructor(
        address _ikigaiToken,
        address _buybackEngine,
        uint256 _initialEmissionRate
    ) {
        require(_ikigaiToken != address(0), "Invalid token");
        require(_buybackEngine != address(0), "Invalid buyback engine");
        
        ikigaiToken = IERC20(_ikigaiToken);
        buybackEngine = IBuybackEngine(_buybackEngine);
        baseEmissionRate = _initialEmissionRate;
        launchTimestamp = block.timestamp;
        
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
        
        lastAdjustmentTime = block.timestamp;
    }
    
    /**
     * @notice Adjusts emission rate based on market conditions
     */
    function adjustEmissionRate() external nonReentrant {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Not operator");
        require(block.timestamp >= lastAdjustmentTime + adjustmentCooldown, "Cooldown active");
        
        // Calculate 7-day price volatility
        uint256 volatility = calculate7DayVolatility();
        
        // If volatility is too high, reduce emissions
        if (volatility > TARGET_PRICE_STABILITY) {
            uint256 reduction = (volatility - TARGET_PRICE_STABILITY) / 100;
            reduction = reduction > 20 ? 20 : reduction; // Cap at 20%
            
            baseEmissionRate = baseEmissionRate * (100 - reduction) / 100;
            emit EmissionRateAdjusted(baseEmissionRate, false);
        } 
        // If volatility is low, can slightly increase emissions
        else if (volatility < TARGET_PRICE_STABILITY / 2) {
            baseEmissionRate = baseEmissionRate * 102 / 100; // +2%
            emit EmissionRateAdjusted(baseEmissionRate, true);
        }
        
        lastAdjustmentTime = block.timestamp;
    }
    
    /**
     * @notice Calculates 7-day price volatility
     * @return Volatility in basis points
     */
    function calculate7DayVolatility() public view returns (uint256) {
        // This is a simplified implementation
        // In production, you would use an oracle or calculate from price history
        
        // For now, we'll use a simple high/low calculation from buyback engine
        uint256 currentPrice = buybackEngine.getCurrentPrice();
        uint256 sevenDayAvg = buybackEngine.getThirtyDayAveragePrice(); // Using 30-day as proxy
        
        if (currentPrice > sevenDayAvg) {
            return ((currentPrice - sevenDayAvg) * 10000) / sevenDayAvg;
        } else {
            return ((sevenDayAvg - currentPrice) * 10000) / sevenDayAvg;
        }
    }
    
    /**
     * @notice Gets weekly emission cap
     * @return Weekly emission cap
     */
    function getWeeklyEmissionCap() public view returns (uint256) {
        uint256 weeksSinceLaunch = (block.timestamp - launchTimestamp) / 1 weeks;
        
        if (weeksSinceLaunch >= 104) { // 2 years
            return MAX_DAILY_EMISSION * 7 * 5000 / 10000; // 50% of initial cap
        }
        
        // Apply weekly reduction
        uint256 reductionPower = 10000;
        for (uint256 i = 0; i < weeksSinceLaunch; i++) {
            reductionPower = (reductionPower * emissionReductionFactor) / 10000;
        }
        
        return (MAX_DAILY_EMISSION * 7 * reductionPower) / 10000;
    }
    
    /**
     * @notice Distributes emissions to recipients
     */
    function distributeEmissions() external nonReentrant {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Not operator");
        
        uint256 emissionAmount = baseEmissionRate;
        uint256 weeklyEmissionCap = getWeeklyEmissionCap();
        
        // Ensure we don't exceed weekly cap
        if (emissionAmount > weeklyEmissionCap) {
            emissionAmount = weeklyEmissionCap;
        }
        
        // Distribute to recipients based on shares
        for (uint256 i = 0; i < distributionRecipients.length; i++) {
            address recipient = distributionRecipients[i];
            uint256 share = distributionShares[recipient];
            
            if (share > 0) {
                uint256 amount = (emissionAmount * share) / 10000;
                
                if (amount > 0) {
                    ikigaiToken.safeTransfer(recipient, amount);
                    emit EmissionDistributed(recipient, amount);
                }
            }
        }
    }
    
    /**
     * @notice Updates distribution share for a recipient
     * @param _recipient Recipient address
     * @param _share Share in basis points
     */
    function updateDistributionShare(address _recipient, uint256 _share) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(_recipient != address(0), "Invalid recipient");
        require(_share <= 10000, "Share too high");
        
        // If recipient doesn't exist and share > 0, add to array
        if (distributionShares[_recipient] == 0 && _share > 0) {
            distributionRecipients.push(_recipient);
        }
        
        distributionShares[_recipient] = _share;
        
        emit DistributionShareUpdated(_recipient, _share);
    }
    
    /**
     * @notice Updates adjustment cooldown
     * @param _newCooldown New cooldown in seconds
     */
    function updateAdjustmentCooldown(uint256 _newCooldown) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(_newCooldown >= 1 days, "Cooldown too short");
        require(_newCooldown <= 30 days, "Cooldown too long");
        
        adjustmentCooldown = _newCooldown;
        
        emit AdjustmentCooldownUpdated(_newCooldown);
    }
    
    /**
     * @notice Gets all distribution recipients and their shares
     * @return recipients Array of recipient addresses
     * @return shares Array of shares
     */
    function getAllDistributionShares() external view returns (
        address[] memory recipients,
        uint256[] memory shares
    ) {
        recipients = new address[](distributionRecipients.length);
        shares = new uint256[](distributionRecipients.length);
        
        for (uint256 i = 0; i < distributionRecipients.length; i++) {
            recipients[i] = distributionRecipients[i];
            shares[i] = distributionShares[distributionRecipients[i]];
        }
        
        return (recipients, shares);
    }
    
    /**
     * @notice Emergency function to recover tokens
     * @param _token Token address
     */
    function recoverTokens(address _token) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        
        IERC20 tokenToRecover = IERC20(_token);
        uint256 balance = tokenToRecover.balanceOf(address(this));
        tokenToRecover.safeTransfer(msg.sender, balance);
    }
} 