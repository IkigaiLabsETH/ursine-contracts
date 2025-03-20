// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./GenesisNFTStorage.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title GenesisNFTLogic
 * @notice Implementation contract for GenesisNFT with upgradeable pattern
 * @dev Implements UUPS upgradeable pattern with ERC721 standard
 */
contract GenesisNFTLogic is 
    GenesisNFTStorage, 
    ERC721, 
    ERC721Enumerable, 
    ERC721URIStorage,
    ERC2981,
    ReentrancyGuard, 
    Pausable,
    UUPSUpgradeable 
{
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
    event ContractUpgraded(address newImplementation);

    /**
     * @notice Initializer function (replaces constructor for upgradeable contracts)
     * @param _defaultAdmin Default admin address
     * @param _name Token name
     * @param _symbol Token symbol
     * @param _royaltyRecipient Royalty recipient address
     * @param _royaltyBps Royalty basis points
     * @param _beraToken BERA token address
     * @param _ikigaiToken IKIGAI token address
     * @param _treasuryAddress Treasury address
     * @param _buybackEngine Buyback engine address
     * @param _beraHolderPrice Price for BERA holders
     * @param _whitelistPrice Price for whitelisted users
     * @param _publicPrice Public sale price
     */
    function initialize(
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
    ) public initializer {
        require(_beraToken != address(0), "Invalid BERA token");
        require(_ikigaiToken != address(0), "Invalid IKIGAI token");
        require(_treasuryAddress != address(0), "Invalid treasury");
        require(_buybackEngine != address(0), "Invalid buyback engine");
        
        // Initialize ERC721
        ERC721_init(_name, _symbol);
        
        // Set token metadata
        name = _name;
        symbol = _symbol;
        
        // Set token references
        beraToken = IERC20(_beraToken);
        ikigaiToken = IERC20(_ikigaiToken);
        treasuryAddress = _treasuryAddress;
        buybackEngine = IBuybackEngine(_buybackEngine);
        
        // Set pricing
        beraHolderPrice = _beraHolderPrice;
        whitelistPrice = _whitelistPrice;
        publicPrice = _publicPrice;
        
        // Setup royalties
        royaltyRecipient = _royaltyRecipient;
        royaltyBps = _royaltyBps;
        _setDefaultRoyalty(_royaltyRecipient, _royaltyBps);
        
        // Set default sale phase
        currentPhase = SalePhase.NotStarted;
        
        // Set claim rate limits
        claimCooldown = 1 days;
        maxClaimAmount = 1000 * 10**18; // 1000 tokens max claim per user
        claimRateLimit = 10000 * 10**18; // 10,000 tokens max per day across all users
        claimWindowDuration = 1 days;
        claimWindowStart = block.timestamp;
        
        // Set minting limits
        maxMintPerTx = 20;
        
        // Setup AccessControl roles
        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _setupRole(TREASURY_ROLE, _defaultAdmin);
        _setupRole(WHITELIST_MANAGER_ROLE, _defaultAdmin);
        _setupRole(PRICE_MANAGER_ROLE, _defaultAdmin);
        _setupRole(EMERGENCY_ROLE, _defaultAdmin);
        _setupRole(METADATA_ROLE, _defaultAdmin);
        _setupRole(UPGRADE_ROLE, _defaultAdmin);
    }
    
    /**
     * @notice Initialize ERC721 separately
     * @dev This function enables proper initialization of the ERC721 implementation
     */
    function ERC721_init(string memory _name, string memory _symbol) internal {
        __ERC721_init(_name, _symbol);
    }
    
    /**
     * @notice Authorization function for upgrades
     * @dev Required by UUPSUpgradeable
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADE_ROLE) {
        emit ContractUpgraded(newImplementation);
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
        
        // Process the payment and add rewards
        processPaymentAndRewards(totalPrice, msg.sender);
        
        // Mint NFT
        uint256 startTokenId = _currentIndex;
        for (uint256 i = 0; i < _quantity; i++) {
            uint256 tokenId = _currentIndex;
            _safeMint(msg.sender, tokenId);
            _currentIndex++;
        }
        
        // Update minted counter
        mintedPerWallet[msg.sender] = mintedPerWallet[msg.sender].add(_quantity);
        
        // Emit batch minted event
        emit BatchMinted(msg.sender, startTokenId, _quantity);
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
        // Use buyback engine for real-time pricing
        return buybackEngine.getIkigaiAmountForBera(_beraAmount);
    }

    /**
     * @notice Process payment and rewards
     * @param _totalPrice Total price in BERA
     * @param _recipient Recipient address
     */
    function processPaymentAndRewards(uint256 _totalPrice, address _recipient) internal {
        // Transfer BERA from user
        beraToken.safeTransferFrom(_recipient, address(this), _totalPrice);
        
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
     * @notice Gets current price for user
     * @param _user User address
     * @return Current price
     */
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

    /**
     * @notice Set URI information
     * @param _baseURI Base URI
     * @param _notRevealedURI Not revealed URI
     */
    function setURIInfo(string memory _baseURI, string memory _notRevealedURI) external nonReentrant onlyRole(METADATA_ROLE) {
        baseURI = _baseURI;
        notRevealedURI = _notRevealedURI;
    }

    /**
     * @notice Reveal collection
     * @param _revealed Whether to reveal the collection
     */
    function revealCollection(bool _revealed) external nonReentrant onlyRole(METADATA_ROLE) {
        revealed = _revealed;
    }

    /**
     * @notice Set token URI for a specific token
     * @param tokenId Token ID
     * @param _tokenURI Token URI
     */
    function setTokenURI(uint256 tokenId, string memory _tokenURI) external nonReentrant onlyRole(METADATA_ROLE) {
        require(_exists(tokenId), "Token does not exist");
        _tokenURIs[tokenId] = _tokenURI;
    }

    /**
     * @notice Update royalty info
     * @param _receiver Receiver address
     * @param _royaltyFeesInBips Royalty fees in basis points
     */
    function updateRoyaltyInfo(address _receiver, uint96 _royaltyFeesInBips) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_receiver != address(0), "Invalid receiver address");
        require(_royaltyFeesInBips <= 10000, "Royalty exceeds 100%");
        royaltyRecipient = _receiver;
        royaltyBps = _royaltyFeesInBips;
        _setDefaultRoyalty(_receiver, _royaltyFeesInBips);
    }

    /**
     * @notice Set accepted tokens for payment
     * @param _token Token address
     * @param _accepted Whether the token is accepted
     * @param _priceMultiplier Price multiplier (1000 = 1x)
     */
    function setAcceptedToken(address _token, bool _accepted, uint256 _priceMultiplier) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_token != address(0), "Invalid token address");
        require(_priceMultiplier > 0, "Price multiplier must be positive");
        acceptedTokens[_token] = _accepted;
        tokenPriceMultipliers[_token] = _priceMultiplier;
    }

    /**
     * @notice Get total supply
     * @return Total supply
     */
    function totalSupply() public view returns (uint256) {
        return _currentIndex;
    }

    /**
     * @notice Check if token exists
     * @param tokenId Token ID
     * @return Whether token exists
     */
    function _exists(uint256 tokenId) internal view returns (bool) {
        return tokenId < _currentIndex && _owners[tokenId] != address(0);
    }

    /**
     * @notice Get token URI
     * @param tokenId Token ID
     * @return Token URI
     */
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");
        
        if (!revealed) {
            return notRevealedURI;
        }
        
        if (bytes(_tokenURIs[tokenId]).length > 0) {
            return _tokenURIs[tokenId];
        }
        
        return string(abi.encodePacked(baseURI, tokenId.toString()));
    }

    /**
     * @notice Get owner of token
     * @param tokenId Token ID
     * @return Owner address
     */
    function ownerOf(uint256 tokenId) public view override(ERC721) returns (address) {
        require(_exists(tokenId), "Owner query for nonexistent token");
        return _owners[tokenId];
    }

    // Required overrides for ERC721, ERC721Enumerable, and ERC721URIStorage
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable, ERC2981, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // ERC721 initialization function
    function __ERC721_init(string memory _name, string memory _symbol) internal {
        // Empty implementation as we're manually setting name and symbol
    }
} 