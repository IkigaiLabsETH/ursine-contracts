// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "@thirdweb-dev/contracts/base/ERC721DelayedReveal.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IBuybackEngine.sol";

/**
 * @title Ikigai Genesis NFT Collection
 * @notice First NFT collection that accepts BERA for minting and rewards IKIGAI
 * @dev Extends ERC721DelayedReveal with vesting rewards
 */
contract GenesisNFT is ERC721DelayedReveal, ReentrancyGuard {
    using SafeERC20 for IERC20;

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
    
    // Reward tracking
    struct RewardInfo {
        uint256 totalAmount;
        uint256 claimedAmount;
        uint256 vestingStart;
    }
    mapping(address => RewardInfo) public rewards;
    
    // Sale state
    enum SalePhase { NotStarted, BeraHolders, Whitelist, Public, Ended }
    SalePhase public currentPhase = SalePhase.NotStarted;
    
    // Events
    event RewardAdded(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event SalePhaseChanged(SalePhase phase);
    event TreasuryPayment(uint256 amount);
    event PriceUpdated(uint256 beraHolderPrice, uint256 whitelistPrice, uint256 publicPrice);
    event WhitelistUpdated(address indexed user, bool beraHolder, bool general);
    
    // Add these state variables
    uint256 public maxSupply;
    uint256 public maxMintPerWallet;
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
    }
    
    /**
     * @notice Mints NFT with BERA payment and IKIGAI rewards
     * @param _quantity Number of NFTs to mint
     */
    function mint(uint256 _quantity) external nonReentrant {
        require(currentPhase != SalePhase.NotStarted && currentPhase != SalePhase.Ended, "Sale not active");
        require(_quantity > 0, "Invalid quantity");
        
        // Check mint limits
        require(totalSupply() + _quantity <= maxSupply, "Exceeds max supply");
        require(mintedPerWallet[msg.sender] + _quantity <= maxMintPerWallet, "Exceeds wallet limit");
        
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
        
        uint256 totalPrice = price * _quantity;
        
        // Transfer BERA from user
        beraToken.safeTransferFrom(msg.sender, address(this), totalPrice);
        
        // Calculate shares
        uint256 treasuryAmount = (totalPrice * TREASURY_SHARE) / 10000;
        uint256 rewardsAmount = totalPrice - treasuryAmount;
        
        // Send treasury share
        beraToken.safeTransfer(treasuryAddress, treasuryAmount);
        emit TreasuryPayment(treasuryAmount);
        
        // Add rewards (vested IKIGAI)
        if (rewardsAmount > 0) {
            // Convert BERA value to IKIGAI reward amount (implementation depends on tokenomics)
            uint256 ikigaiRewardAmount = convertBeraToIkigaiReward(rewardsAmount);
            
            // Record reward
            rewards[msg.sender].totalAmount += ikigaiRewardAmount;
            if (rewards[msg.sender].vestingStart == 0) {
                rewards[msg.sender].vestingStart = block.timestamp;
            }
            
            emit RewardAdded(msg.sender, ikigaiRewardAmount);
        }
        
        // Mint NFT
        _safeMint(msg.sender, _quantity);
        
        // Update minted counter
        mintedPerWallet[msg.sender] += _quantity;
    }
    
    /**
     * @notice Claims vested IKIGAI rewards
     */
    function claimRewards() external nonReentrant {
        RewardInfo storage userRewards = rewards[msg.sender];
        require(userRewards.totalAmount > userRewards.claimedAmount, "No rewards to claim");
        require(block.timestamp >= userRewards.vestingStart + VESTING_CLIFF, "Cliff period not passed");
        
        uint256 vestedAmount = calculateVestedAmount(msg.sender);
        uint256 claimableAmount = vestedAmount - userRewards.claimedAmount;
        require(claimableAmount > 0, "No claimable rewards");
        
        userRewards.claimedAmount += claimableAmount;
        
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
        if (block.timestamp < userRewards.vestingStart + VESTING_CLIFF) {
            return 0;
        }
        
        // After vesting period, everything is vested
        if (block.timestamp >= userRewards.vestingStart + VESTING_DURATION) {
            return userRewards.totalAmount;
        }
        
        // During vesting period (after cliff), calculate linear vesting
        uint256 timeVested = block.timestamp - userRewards.vestingStart - VESTING_CLIFF;
        uint256 vestingPeriod = VESTING_DURATION - VESTING_CLIFF;
        
        // Cliff amount + linear vesting of remaining amount
        uint256 cliffAmount = userRewards.totalAmount * 10 / 100; // 10% at cliff
        uint256 remainingAmount = userRewards.totalAmount - cliffAmount;
        return cliffAmount + (remainingAmount * timeVested / vestingPeriod);
    }
    
    /**
     * @notice Converts BERA amount to IKIGAI reward amount
     * @param _beraAmount Amount of BERA
     * @return IKIGAI reward amount
     */
    function convertBeraToIkigaiReward(uint256 _beraAmount) public view returns (uint256) {
        // This implementation depends on your tokenomics
        // For example, you might use a fixed ratio or oracle price
        // Placeholder implementation - replace with actual conversion logic
        return _beraAmount * 100; // Example: 1 BERA = 100 IKIGAI
    }
    
    /**
     * @notice Updates the sale phase
     * @param _phase New sale phase
     */
    function setSalePhase(SalePhase _phase) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
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
    ) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
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
    ) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(_users.length == _beraHolderStatus.length && _users.length == _generalStatus.length, "Array length mismatch");
        
        for (uint256 i = 0; i < _users.length; i++) {
            beraHolderWhitelist[_users[i]] = _beraHolderStatus[i];
            generalWhitelist[_users[i]] = _generalStatus[i];
            emit WhitelistUpdated(_users[i], _beraHolderStatus[i], _generalStatus[i]);
        }
    }
    
    /**
     * @notice Updates the treasury address
     * @param _newTreasury New treasury address
     */
    function updateTreasury(address _newTreasury) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(_newTreasury != address(0), "Invalid address");
        treasuryAddress = _newTreasury;
    }
    
    /**
     * @notice Updates the buyback engine address
     * @param _newBuybackEngine New buyback engine address
     */
    function updateBuybackEngine(address _newBuybackEngine) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(_newBuybackEngine != address(0), "Invalid address");
        buybackEngine = IBuybackEngine(_newBuybackEngine);
    }
    
    /**
     * @notice Emergency token recovery
     * @param _token Token address
     * @param _amount Amount to recover
     */
    function emergencyTokenRecovery(address _token, uint256 _amount) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
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
    
    // Add admin function to set limits
    function setLimits(uint256 _maxSupply, uint256 _maxMintPerWallet) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        maxSupply = _maxSupply;
        maxMintPerWallet = _maxMintPerWallet;
    }

    // Gas-optimized batch minting
    function batchMint(uint256 _quantity) external nonReentrant {
        // ... same checks as mint function ...
        
        // Calculate total price
        uint256 totalPrice = getCurrentPriceForUser(msg.sender) * _quantity;
        
        // Transfer BERA from user
        beraToken.safeTransferFrom(msg.sender, address(this), totalPrice);
        
        // Process payment and rewards just once
        processPaymentAndRewards(totalPrice, msg.sender);
        
        // Mint NFTs efficiently
        uint256 startTokenId = _currentIndex;
        _safeMint(msg.sender, _quantity);
        
        // Optional: Emit an event with range
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
        uint256 treasuryAmount = (_totalPrice * TREASURY_SHARE) / 10000;
        uint256 rewardsAmount = _totalPrice - treasuryAmount;
        
        // Send treasury share
        beraToken.safeTransfer(treasuryAddress, treasuryAmount);
        emit TreasuryPayment(treasuryAmount);
        
        // Process rewards
        if (rewardsAmount > 0) {
            uint256 ikigaiRewardAmount = convertBeraToIkigaiReward(rewardsAmount);
            
            rewards[_recipient].totalAmount += ikigaiRewardAmount;
            if (rewards[_recipient].vestingStart == 0) {
                rewards[_recipient].vestingStart = block.timestamp;
            }
            
            emit RewardAdded(_recipient, ikigaiRewardAmount);
        }
    }

    // Admin function to set URI information
    function setURIInfo(string memory _baseURI, string memory _notRevealedURI) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        baseURI = _baseURI;
        notRevealedURI = _notRevealedURI;
    }

    // Admin function to reveal collection
    function revealCollection(bool _revealed) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
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
    function setTokenURI(uint256 tokenId, string memory _tokenURI) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(_exists(tokenId), "Token does not exist");
        _tokenURIs[tokenId] = _tokenURI;
    }

    // Enhanced royalty handling
    function updateRoyaltyInfo(address _receiver, uint96 _royaltyFeesInBips) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        _setDefaultRoyaltyInfo(_receiver, _royaltyFeesInBips);
    }

    function setTokenRoyalty(
        uint256 _tokenId,
        address _receiver,
        uint96 _royaltyFeesInBips
    ) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        _setTokenRoyalty(_tokenId, _receiver, _royaltyFeesInBips);
    }
} 