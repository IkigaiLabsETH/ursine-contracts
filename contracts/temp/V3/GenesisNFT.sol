// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "@thirdweb-dev/contracts/base/ERC721DelayedReveal.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IBuybackEngine.sol";

/**
 * @title Ikigai Genesis NFT Collection
 * @notice First NFT collection that accepts BERA for minting and rewards IKIGAI
 * @dev Extends ERC721DelayedReveal with vesting rewards
 */
contract GenesisNFT is ERC721DelayedReveal, ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Access control roles
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    bytes32 public constant WHITELIST_MANAGER_ROLE = keccak256("WHITELIST_MANAGER_ROLE");
    bytes32 public constant PRICE_MANAGER_ROLE = keccak256("PRICE_MANAGER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant METADATA_ROLE = keccak256("METADATA_ROLE");
    
    // Token references
    IERC20 public immutable beraToken;
    IERC20 public immutable ikigaiToken;
    IBuybackEngine public buybackEngine;
    
    // Treasury and reward parameters
    address public treasuryAddress;
    uint256 public constant TREASURY_SHARE = 6000; // 60% to treasury
    uint256 public constant REWARDS_SHARE = 4000;  // 40% to rewards
    
    // Whitelist and pricing
    mapping(address => bool) public beraHolderWhitelist;
    mapping(address => bool) public generalWhitelist;
    uint256 public beraHolderPrice;
    uint256 public whitelistPrice;
    uint256 public publicPrice;
    
    // Vesting parameters
    uint256 public constant VESTING_DURATION = 90 days;
    uint256 public constant VESTING_CLIFF = 7 days;
    
    // Reward tracking with enhanced security
    struct RewardInfo {
        uint256 totalAmount;
        uint256 claimedAmount;
        uint256 vestingStart;
        uint256 lastClaimTime;
    }
    mapping(address => RewardInfo) public rewards;
    
    // Sale state
    enum SalePhase { NotStarted, BeraHolders, Whitelist, Public, Ended }
    SalePhase public currentPhase = SalePhase.NotStarted;

    // Circuit breaker
    bool public emergencyMode = false;
    
    // Rate limiting
    uint256 public claimCooldown = 1 days;
    uint256 public maxClaimAmount;
    uint256 public claimRateLimit;
    uint256 public totalClaimedInWindow;
    uint256 public claimWindowStart;
    uint256 public claimWindowDuration = 1 days;
    
    // Events
    event RewardAdded(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event SalePhaseChanged(SalePhase phase);
    event TreasuryPayment(uint256 amount);
    event PriceUpdated(uint256 beraHolderPrice, uint256 whitelistPrice, uint256 publicPrice);
    event WhitelistUpdated(address indexed user, bool beraHolder, bool general);
    event EmergencyModeChanged(bool enabled);
    event ClaimLimitsUpdated(uint256 cooldown, uint256 maxAmount, uint256 rateLimit, uint256 windowDuration);
    event BatchMinted(address indexed to, uint256 startTokenId, uint256 quantity);
    
    // Add these state variables
    uint256 public maxSupply;
    uint256 public maxMintPerWallet;
    uint256 public maxMintPerTx = 20;
    mapping(address => uint256) public mintedPerWallet;
    
    // Add metadata and reveal features
    mapping(uint256 => string) private _tokenURIs;
    bool public revealed = false;
    string public notRevealedURI;
    string public baseURI;
    
    constructor(
        address _defaultAdmin,
        string memory _name,
        string memory _symbol,
        address _royaltyRecipient,
        uint128 _royaltyBps,
        address _beraToken,
        address _ikigaiToken,
        address _treasuryAddress,
        address _buybackEngine,
        uint256 _beraHolderPrice,
        uint256 _whitelistPrice,
        uint256 _publicPrice
    ) ERC721DelayedReveal(_defaultAdmin, _name, _symbol, _royaltyRecipient, _royaltyBps) {
        require(_beraToken != address(0), "Invalid BERA token");
        require(_ikigaiToken != address(0), "Invalid IKIGAI token");
        require(_treasuryAddress != address(0), "Invalid treasury");
        require(_buybackEngine != address(0), "Invalid buyback engine");
        
        beraToken = IERC20(_beraToken);
        ikigaiToken = IERC20(_ikigaiToken);
        treasuryAddress = _treasuryAddress;
        buybackEngine = IBuybackEngine(_buybackEngine);
        
        beraHolderPrice = _beraHolderPrice;
        whitelistPrice = _whitelistPrice;
        publicPrice = _publicPrice;
        
        // Setup AccessControl roles
        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _setupRole(TREASURY_ROLE, _defaultAdmin);
        _setupRole(WHITELIST_MANAGER_ROLE, _defaultAdmin);
        _setupRole(PRICE_MANAGER_ROLE, _defaultAdmin);
        _setupRole(EMERGENCY_ROLE, _defaultAdmin);
        _setupRole(METADATA_ROLE, _defaultAdmin);
        
        // Set initial claim rate limits - adjust based on tokenomics
        maxClaimAmount = 1000 * 10**18; // 1000 tokens max claim per user
        claimRateLimit = 10000 * 10**18; // 10,000 tokens max per day across all users
        claimWindowStart = block.timestamp;
    }
    
    /**
     * @notice Mints NFT with BERA payment and IKIGAI rewards
     * @param _quantity Number of NFTs to mint
     */
    function mint(uint256 _quantity) external nonReentrant whenNotPaused {
        require(!emergencyMode, "Emergency mode: minting disabled");
        require(currentPhase != SalePhase.NotStarted && currentPhase != SalePhase.Ended, "Sale not active");
        require(_quantity > 0, "Invalid quantity");
        require(_quantity <= maxMintPerTx, "Exceeds max mint per transaction");
        
        // Check mint limits
        require(totalSupply().add(_quantity) <= maxSupply, "Exceeds max supply");
        require(mintedPerWallet[msg.sender].add(_quantity) <= maxMintPerWallet, "Exceeds wallet limit");
        
        // Determine price based on phase and user status
        uint256 price;
        if (currentPhase == SalePhase.BeraHolders) {
            require(beraHolderWhitelist[msg.sender], "Not on BERA holder whitelist");
            price = beraHolderPrice;
        } else if (currentPhase == SalePhase.Whitelist) {
            require(beraHolderWhitelist[msg.sender] || generalWhitelist[msg.sender], "Not whitelisted");
            price = beraHolderWhitelist[msg.sender] ? beraHolderPrice : whitelistPrice;
        } else {
            // Public phase
            price = publicPrice;
        }
        
        uint256 totalPrice = price.mul(_quantity);
        require(totalPrice > 0, "Price calculation error");
        
        // Additional check to prevent zero-value mints
        uint256 beraBalance = beraToken.balanceOf(msg.sender);
        require(beraBalance >= totalPrice, "Insufficient BERA balance");
        
        // Transfer BERA from user
        beraToken.safeTransferFrom(msg.sender, address(this), totalPrice);
        
        // Calculate shares
        uint256 treasuryAmount = totalPrice.mul(TREASURY_SHARE).div(10000);
        uint256 rewardsAmount = totalPrice.sub(treasuryAmount);
        
        // Send treasury share
        beraToken.safeTransfer(treasuryAddress, treasuryAmount);
        emit TreasuryPayment(treasuryAmount);
        
        // Add rewards (vested IKIGAI)
        if (rewardsAmount > 0) {
            // Convert BERA value to IKIGAI reward amount
            uint256 ikigaiRewardAmount = convertBeraToIkigaiReward(rewardsAmount);
            require(ikigaiRewardAmount > 0, "Invalid reward calculation");
            
            // Record reward
            rewards[msg.sender].totalAmount = rewards[msg.sender].totalAmount.add(ikigaiRewardAmount);
            if (rewards[msg.sender].vestingStart == 0) {
                rewards[msg.sender].vestingStart = block.timestamp;
            }
            
            emit RewardAdded(msg.sender, ikigaiRewardAmount);
        }
        
        // Mint NFT
        _safeMint(msg.sender, _quantity);
        
        // Update minted counter
        mintedPerWallet[msg.sender] = mintedPerWallet[msg.sender].add(_quantity);
    }
    
    /**
     * @notice Claims vested IKIGAI rewards
     */
    function claimRewards() external nonReentrant whenNotPaused {
        require(!emergencyMode, "Emergency mode: claiming disabled");
        
        RewardInfo storage userRewards = rewards[msg.sender];
        require(userRewards.totalAmount > userRewards.claimedAmount, "No rewards to claim");
        require(block.timestamp >= userRewards.vestingStart.add(VESTING_CLIFF), "Cliff period not passed");
        
        // Rate limit: User cooldown
        require(block.timestamp >= userRewards.lastClaimTime.add(claimCooldown), "Claim cooldown active");
        
        // Get claimable amount
        uint256 vestedAmount = calculateVestedAmount(msg.sender);
        uint256 claimableAmount = vestedAmount.sub(userRewards.claimedAmount);
        require(claimableAmount > 0, "No claimable rewards");
        
        // Apply maximum claim amount if needed
        if (claimableAmount > maxClaimAmount) {
            claimableAmount = maxClaimAmount;
        }
        
        // Reset claim window if needed
        if (block.timestamp >= claimWindowStart.add(claimWindowDuration)) {
            claimWindowStart = block.timestamp;
            totalClaimedInWindow = 0;
        }
        
        // Check global rate limit
        require(totalClaimedInWindow.add(claimableAmount) <= claimRateLimit, "Global claim rate limit exceeded");
        
        // Update user's claimed amount and last claim time
        userRewards.claimedAmount = userRewards.claimedAmount.add(claimableAmount);
        userRewards.lastClaimTime = block.timestamp;
        
        // Update global claim counter
        totalClaimedInWindow = totalClaimedInWindow.add(claimableAmount);
        
        // Transfer IKIGAI rewards
        ikigaiToken.safeTransfer(msg.sender, claimableAmount);
        
        emit RewardClaimed(msg.sender, claimableAmount);
    }
    
    /**
     * @notice Calculates vested amount for a user
     * @param _user User address
     * @return Vested amount
     */
    function calculateVestedAmount(address _user) public view returns (uint256) {
        RewardInfo memory userRewards = rewards[_user];
        
        if (userRewards.totalAmount == 0) {
            return 0;
        }
        
        // Before cliff, nothing is vested
        if (block.timestamp < userRewards.vestingStart.add(VESTING_CLIFF)) {
            return 0;
        }
        
        // After vesting period, everything is vested
        if (block.timestamp >= userRewards.vestingStart.add(VESTING_DURATION)) {
            return userRewards.totalAmount;
        }
        
        // During vesting period (after cliff), calculate linear vesting
        uint256 timeVested = block.timestamp.sub(userRewards.vestingStart).sub(VESTING_CLIFF);
        uint256 vestingPeriod = VESTING_DURATION.sub(VESTING_CLIFF);
        
        // Cliff amount + linear vesting of remaining amount
        uint256 cliffAmount = userRewards.totalAmount.mul(10).div(100); // 10% at cliff
        uint256 remainingAmount = userRewards.totalAmount.sub(cliffAmount);
        return cliffAmount.add(remainingAmount.mul(timeVested).div(vestingPeriod));
    }
    
    /**
     * @notice Converts BERA amount to IKIGAI reward amount
     * @param _beraAmount Amount of BERA
     * @return IKIGAI reward amount
     */
    function convertBeraToIkigaiReward(uint256 _beraAmount) public view returns (uint256) {
        // This implementation depends on your tokenomics
        // Consider using the buyback engine for real-time pricing
        return buybackEngine.getIkigaiAmountForBera(_beraAmount);
    }
    
    /**
     * @notice Updates the sale phase
     * @param _phase New sale phase
     */
    function setSalePhase(SalePhase _phase) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        currentPhase = _phase;
        emit SalePhaseChanged(_phase);
    }
    
    /**
     * @notice Updates prices for different tiers
     * @param _beraHolderPrice New BERA holder price
     * @param _whitelistPrice New whitelist price
     * @param _publicPrice New public price
     */
    function setPrices(
        uint256 _beraHolderPrice,
        uint256 _whitelistPrice,
        uint256 _publicPrice
    ) external nonReentrant onlyRole(PRICE_MANAGER_ROLE) {
        require(_beraHolderPrice > 0, "Invalid BERA holder price");
        require(_whitelistPrice > 0, "Invalid whitelist price");
        require(_publicPrice > 0, "Invalid public price");
        
        beraHolderPrice = _beraHolderPrice;
        whitelistPrice = _whitelistPrice;
        publicPrice = _publicPrice;
        emit PriceUpdated(_beraHolderPrice, _whitelistPrice, _publicPrice);
    }
    
    /**
     * @notice Updates whitelist status for users
     * @param _users Array of user addresses
     * @param _beraHolderStatus Array of BERA holder statuses
     * @param _generalStatus Array of general whitelist statuses
     */
    function updateWhitelist(
        address[] calldata _users,
        bool[] calldata _beraHolderStatus,
        bool[] calldata _generalStatus
    ) external nonReentrant onlyRole(WHITELIST_MANAGER_ROLE) {
        require(_users.length == _beraHolderStatus.length && _users.length == _generalStatus.length, "Array length mismatch");
        require(_users.length <= 1000, "Batch too large"); // Prevent gas limit issues
        
        for (uint256 i = 0; i < _users.length; i++) {
            require(_users[i] != address(0), "Invalid address");
            beraHolderWhitelist[_users[i]] = _beraHolderStatus[i];
            generalWhitelist[_users[i]] = _generalStatus[i];
            emit WhitelistUpdated(_users[i], _beraHolderStatus[i], _generalStatus[i]);
        }
    }
    
    /**
     * @notice Updates the treasury address
     * @param _newTreasury New treasury address
     */
    function updateTreasury(address _newTreasury) external nonReentrant onlyRole(TREASURY_ROLE) {
        require(_newTreasury != address(0), "Invalid address");
        treasuryAddress = _newTreasury;
    }
    
    /**
     * @notice Updates the buyback engine address
     * @param _newBuybackEngine New buyback engine address
     */
    function updateBuybackEngine(address _newBuybackEngine) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newBuybackEngine != address(0), "Invalid address");
        buybackEngine = IBuybackEngine(_newBuybackEngine);
    }
    
    /**
     * @notice Emergency token recovery
     * @param _token Token address
     * @param _amount Amount to recover
     */
    function emergencyTokenRecovery(address _token, uint256 _amount) external nonReentrant onlyRole(EMERGENCY_ROLE) {
        require(_token != address(ikigaiToken) || 
                IERC20(_token).balanceOf(address(this)) > getTotalUnclaimedRewards(), 
                "Cannot withdraw reward tokens");
        
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }
    
    /**
     * @notice Gets total unclaimed rewards
     * @return Total unclaimed rewards
     */
    function getTotalUnclaimedRewards() public view returns (uint256) {
        // This is a simplified implementation
        // In production, you would track this more efficiently
        return ikigaiToken.balanceOf(address(this));
    }
    
    /**
     * @notice Sets limits for minting
     * @param _maxSupply Maximum total supply
     * @param _maxMintPerWallet Maximum mints per wallet
     * @param _maxMintPerTx Maximum mints per transaction
     */
    function setLimits(
        uint256 _maxSupply, 
        uint256 _maxMintPerWallet,
        uint256 _maxMintPerTx
    ) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_maxSupply > totalSupply(), "Max supply must be greater than current supply");
        require(_maxMintPerWallet > 0, "Max mint per wallet must be positive");
        require(_maxMintPerTx > 0 && _maxMintPerTx <= 100, "Invalid max mint per tx");
        
        maxSupply = _maxSupply;
        maxMintPerWallet = _maxMintPerWallet;
        maxMintPerTx = _maxMintPerTx;
    }

    /**
     * @notice Sets claim rate limits
     * @param _cooldown Time between claims for a user
     * @param _maxAmount Maximum amount per claim
     * @param _rateLimit Maximum total claimed in window
     * @param _windowDuration Duration of rate limiting window
     */
    function setClaimLimits(
        uint256 _cooldown,
        uint256 _maxAmount,
        uint256 _rateLimit,
        uint256 _windowDuration
    ) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_windowDuration > 0, "Window duration must be positive");
        require(_rateLimit >= _maxAmount, "Rate limit must be >= max amount");
        
        claimCooldown = _cooldown;
        maxClaimAmount = _maxAmount;
        claimRateLimit = _rateLimit;
        claimWindowDuration = _windowDuration;
        
        emit ClaimLimitsUpdated(_cooldown, _maxAmount, _rateLimit, _windowDuration);
    }
    
    /**
     * @notice Toggle emergency mode
     * @param _enabled Whether to enable emergency mode
     */
    function setEmergencyMode(bool _enabled) external onlyRole(EMERGENCY_ROLE) {
        emergencyMode = _enabled;
        emit EmergencyModeChanged(_enabled);
        
        // Automatically pause the contract in emergency mode
        if (_enabled) {
            _pause();
        } else {
            _unpause();
        }
    }
    
    /**
     * @notice Pause contract
     */
    function pause() external onlyRole(EMERGENCY_ROLE) {
        _pause();
    }
    
    /**
     * @notice Unpause contract
     */
    function unpause() external onlyRole(EMERGENCY_ROLE) {
        _unpause();
    }
    
    /**
     * @notice Grant a role to an account
     * @param _role Role to grant
     * @param _account Account to receive the role
     */
    function grantRole(bytes32 _role, address _account) 
        public 
        override 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        super.grantRole(_role, _account);
    }

    // Gas-optimized batch minting
    function batchMint(uint256 _quantity) external nonReentrant whenNotPaused {
        require(!emergencyMode, "Emergency mode: minting disabled");
        require(currentPhase != SalePhase.NotStarted && currentPhase != SalePhase.Ended, "Sale not active");
        require(_quantity > 0, "Invalid quantity");
        require(_quantity <= maxMintPerTx, "Exceeds max mint per transaction");
        
        // Check mint limits
        require(totalSupply().add(_quantity) <= maxSupply, "Exceeds max supply");
        require(mintedPerWallet[msg.sender].add(_quantity) <= maxMintPerWallet, "Exceeds wallet limit");
        
        // Calculate total price
        uint256 totalPrice = getCurrentPriceForUser(msg.sender).mul(_quantity);
        require(totalPrice > 0, "Price calculation error");
        
        // Transfer BERA from user
        beraToken.safeTransferFrom(msg.sender, address(this), totalPrice);
        
        // Process payment and rewards just once
        processPaymentAndRewards(totalPrice, msg.sender);
        
        // Mint NFTs efficiently
        uint256 startTokenId = _currentIndex;
        _safeMint(msg.sender, _quantity);
        
        // Update minted counter
        mintedPerWallet[msg.sender] = mintedPerWallet[msg.sender].add(_quantity);
        
        // Emit an event with range
        emit BatchMinted(msg.sender, startTokenId, _quantity);
    }

    // Helper to get current price for user
    function getCurrentPriceForUser(address _user) public view returns (uint256) {
        if (currentPhase == SalePhase.BeraHolders) {
            if (beraHolderWhitelist[_user]) return beraHolderPrice;
        } else if (currentPhase == SalePhase.Whitelist) {
            if (beraHolderWhitelist[_user]) return beraHolderPrice;
            if (generalWhitelist[_user]) return whitelistPrice;
        } else if (currentPhase == SalePhase.Public) {
            return publicPrice;
        }
        revert("Not eligible to mint");
    }

    // Helper to process payment and rewards
    function processPaymentAndRewards(uint256 _totalPrice, address _recipient) internal {
        // Calculate shares
        uint256 treasuryAmount = _totalPrice.mul(TREASURY_SHARE).div(10000);
        uint256 rewardsAmount = _totalPrice.sub(treasuryAmount);
        
        // Send treasury share
        beraToken.safeTransfer(treasuryAddress, treasuryAmount);
        emit TreasuryPayment(treasuryAmount);
        
        // Process rewards
        if (rewardsAmount > 0) {
            uint256 ikigaiRewardAmount = convertBeraToIkigaiReward(rewardsAmount);
            require(ikigaiRewardAmount > 0, "Invalid reward calculation");
            
            rewards[_recipient].totalAmount = rewards[_recipient].totalAmount.add(ikigaiRewardAmount);
            if (rewards[_recipient].vestingStart == 0) {
                rewards[_recipient].vestingStart = block.timestamp;
            }
            
            emit RewardAdded(_recipient, ikigaiRewardAmount);
        }
    }

    // Admin function to set URI information
    function setURIInfo(string memory _baseURI, string memory _notRevealedURI) external nonReentrant onlyRole(METADATA_ROLE) {
        baseURI = _baseURI;
        notRevealedURI = _notRevealedURI;
    }

    // Admin function to reveal collection
    function revealCollection(bool _revealed) external nonReentrant onlyRole(METADATA_ROLE) {
        revealed = _revealed;
    }

    // Override tokenURI function
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        
        if (!revealed) {
            return notRevealedURI;
        }
        
        // If token has custom URI, return it
        if (bytes(_tokenURIs[tokenId]).length > 0) {
            return _tokenURIs[tokenId];
        }
        
        // Otherwise return baseURI + tokenId
        return string(abi.encodePacked(baseURI, tokenId.toString()));
    }

    // Allow setting custom URI for specific tokens (for special editions)
    function setTokenURI(uint256 tokenId, string memory _tokenURI) external nonReentrant onlyRole(METADATA_ROLE) {
        require(_exists(tokenId), "Token does not exist");
        _tokenURIs[tokenId] = _tokenURI;
    }

    // Enhanced royalty handling
    function updateRoyaltyInfo(address _receiver, uint96 _royaltyFeesInBips) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_receiver != address(0), "Invalid receiver address");
        require(_royaltyFeesInBips <= 10000, "Royalty exceeds 100%");
        _setDefaultRoyaltyInfo(_receiver, _royaltyFeesInBips);
    }

    function setTokenRoyalty(
        uint256 _tokenId,
        address _receiver,
        uint96 _royaltyFeesInBips
    ) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_exists(_tokenId), "Token does not exist");
        require(_receiver != address(0), "Invalid receiver address");
        require(_royaltyFeesInBips <= 10000, "Royalty exceeds 100%");
        _setTokenRoyalty(_tokenId, _receiver, _royaltyFeesInBips);
    }
} 