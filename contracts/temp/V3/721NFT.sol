// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "@thirdweb-dev/contracts/base/ERC721DelayedReveal.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IBuybackEngine.sol";
import "./interfaces/IStakingV2.sol";

/**
 * @title Ikigai NFT Collection
 * @notice ERC721 NFT collection with buyback integration and revenue sharing
 * @dev Extends ERC721DelayedReveal with buyback mechanics and staking requirements
 */
contract IkigaiNFT is ERC721DelayedReveal, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Buyback integration
    IBuybackEngine public buybackEngine;
    IERC20 public ikigaiToken;
    IStakingV2 public stakingContract;
    
    // Revenue allocation
    uint256 public NFT_SALES_BUYBACK = 3500; // 35% to buyback
    uint256 public CREATOR_SHARE = 5000;     // 50% to creator
    uint256 public TREASURY_SHARE = 1500;    // 15% to treasury
    
    // Addresses
    address public treasuryAddress;
    address public defaultCreator;
    mapping(uint256 => address) public tokenCreators;
    
    // Staking requirements
    uint256 public minStakeAmount = 5000 * 1e18; // 5,000 IKIGAI default
    uint256 public minStakeDuration = 7 days;    // 7 days default
    
    // Discount tiers
    struct DiscountTier {
        uint256 stakeAmount;
        uint256 discountBps; // Basis points (100 = 1%)
    }
    DiscountTier[] public discountTiers;
    
    // Whitelist
    mapping(address => bool) public whitelist;
    uint256 public whitelistDiscountBps = 500; // 5% additional discount
    
    // Collection info
    uint256 public mintPrice;
    uint256 public maxSupply;
    bool public requiresStaking = true;
    
    // Collection synergy
    address[] public registeredCollections;
    mapping(address => bool) public isRegisteredCollection;
    uint256 public collectionBonusBps = 250; // 2.5% per collection
    uint256 public maxCollectionBonus = 1500; // Increased to 15% max
    
    // Referral system
    struct ReferralTier {
        uint256 minReferrals;
        uint256 rewardBps;
    }

    // Tiered referral rewards (5% for 1-5 referrals, 7% for 6-15, 10% for 16+)
    ReferralTier[] public referralTiers;
    mapping(address => uint256) public referralCount;
    uint256 public maxReferralReward = 10000; // 100,000 IKIGAI cap per referrer
    
    // Enhance collection synergies with rarity-based bonuses
    mapping(address => uint256) public collectionRarityMultiplier; // 100 = 1x
    
    // Events
    event BuybackContribution(uint256 amount);
    event CreatorPayment(address indexed creator, uint256 amount);
    event TreasuryPayment(uint256 amount);
    event BuybackEngineUpdated(address indexed newEngine);
    event TreasuryUpdated(address indexed newTreasury);
    event DefaultCreatorUpdated(address indexed newCreator);
    event RevenueSharesUpdated(
        uint256 buybackShare,
        uint256 creatorShare,
        uint256 treasuryShare
    );
    event StakingRequirementsUpdated(uint256 minAmount, uint256 minDuration);
    event DiscountTierAdded(uint256 stakeAmount, uint256 discountBps);
    event WhitelistUpdated(address indexed user, bool status);
    event MintPriceUpdated(uint256 price);
    event StakingRequirementToggled(bool required);
    event CollectionRegistered(address indexed collection);
    event CollectionBonusUpdated(uint256 bonusBps, uint256 maxBonus);
    event ReferralRecorded(address indexed user, address indexed referrer, uint256 amount);
    event ReferralRewardsClaimed(address indexed referrer, uint256 amount);
    event ReferralRewardUpdated(uint256 rewardBps);
    
    constructor(
        address _defaultAdmin,
        string memory _name,
        string memory _symbol,
        address _royaltyRecipient,
        uint128 _royaltyBps,
        address _buybackEngine,
        address _ikigaiToken,
        address _treasuryAddress,
        address _defaultCreator,
        address _stakingContract,
        uint256 _mintPrice,
        uint256 _maxSupply
    ) ERC721DelayedReveal(_defaultAdmin, _name, _symbol, _royaltyRecipient, _royaltyBps) {
        require(_buybackEngine != address(0), "Invalid buyback engine");
        require(_ikigaiToken != address(0), "Invalid token");
        require(_treasuryAddress != address(0), "Invalid treasury");
        require(_defaultCreator != address(0), "Invalid creator");
        require(_stakingContract != address(0), "Invalid staking contract");
        
        buybackEngine = IBuybackEngine(_buybackEngine);
        ikigaiToken = IERC20(_ikigaiToken);
        treasuryAddress = _treasuryAddress;
        defaultCreator = _defaultCreator;
        stakingContract = IStakingV2(_stakingContract);
        mintPrice = _mintPrice;
        maxSupply = _maxSupply;
        
        // Set up default discount tiers
        discountTiers.push(DiscountTier(5000 * 1e18, 1000));  // 5,000 IKIGAI = 10% discount
        discountTiers.push(DiscountTier(10000 * 1e18, 2000)); // 10,000 IKIGAI = 20% discount
        discountTiers.push(DiscountTier(25000 * 1e18, 3000)); // 25,000 IKIGAI = 30% discount
        
        // Initialize referral tiers
        referralTiers.push(ReferralTier({minReferrals: 0, rewardBps: 500}));  // 5% for 1-5
        referralTiers.push(ReferralTier({minReferrals: 6, rewardBps: 700}));  // 7% for 6-15
        referralTiers.push(ReferralTier({minReferrals: 16, rewardBps: 1000})); // 10% for 16+
    }
    
    /**
     * @notice Mints NFT with staking requirements
     * @param _quantity Number of NFTs to mint
     */
    function mint(uint256 _quantity) external nonReentrant {
        require(_quantity > 0, "Invalid quantity");
        require(totalSupply() + _quantity <= maxSupply, "Exceeds max supply");
        
        // Check staking requirements if enabled
        uint256 discountBps = 0;
        if (requiresStaking) {
            (uint256 stakedAmount, uint256 lockDuration) = stakingContract.getUserStakeInfo(msg.sender);
            require(stakedAmount >= minStakeAmount, "Insufficient stake");
            require(lockDuration >= minStakeDuration, "Insufficient lock duration");
            
            // Calculate discount based on stake amount
            discountBps = getStakingDiscount(stakedAmount);
        }
        
        // Add whitelist discount if applicable
        if (whitelist[msg.sender]) {
            discountBps += whitelistDiscountBps;
        }
        
        // Add collection bonus if applicable
        discountBps += getCollectionBonus(msg.sender);
        
        // Cap discount at 50%
        if (discountBps > 5000) {
            discountBps = 5000;
        }
        
        // Calculate final price with discount
        uint256 discountedPrice = mintPrice - ((mintPrice * discountBps) / 10000);
        uint256 totalPrice = discountedPrice * _quantity;
        
        // Transfer payment from sender
        ikigaiToken.safeTransferFrom(msg.sender, address(this), totalPrice);
        
        // Process payment distribution
        _processPayment(totalPrice);
        
        // Mint NFT
        _safeMint(msg.sender, _quantity);
    }
    
    /**
     * @notice Processes payment and distributes revenue
     * @param _paymentAmount Amount of payment in IKIGAI tokens
     */
    function _processPayment(uint256 _paymentAmount) internal {
        // Calculate shares
        uint256 buybackAmount = (NFT_SALES_BUYBACK * _paymentAmount) / 10000;
        uint256 creatorAmount = (CREATOR_SHARE * _paymentAmount) / 10000;
        uint256 treasuryAmount = _paymentAmount - buybackAmount - creatorAmount;
        
        // Process buyback contribution
        if (buybackAmount > 0) {
            ikigaiToken.safeApprove(address(buybackEngine), buybackAmount);
            buybackEngine.collectRevenue(keccak256("NFT_SALES"), buybackAmount);
            emit BuybackContribution(buybackAmount);
        }
        
        // Pay creator
        if (creatorAmount > 0) {
            ikigaiToken.safeTransfer(defaultCreator, creatorAmount);
            emit CreatorPayment(defaultCreator, creatorAmount);
        }
        
        // Pay treasury
        if (treasuryAmount > 0) {
            ikigaiToken.safeTransfer(treasuryAddress, treasuryAmount);
            emit TreasuryPayment(treasuryAmount);
        }
    }
    
    /**
     * @notice Processes payment for a specific token
     * @param _paymentAmount Amount of payment in IKIGAI tokens
     * @param _tokenId NFT token ID for creator attribution
     */
    function processPayment(uint256 _paymentAmount, uint256 _tokenId) external nonReentrant {
        require(_paymentAmount > 0, "Zero payment");
        
        // Transfer payment from sender
        ikigaiToken.safeTransferFrom(msg.sender, address(this), _paymentAmount);
        
        // Calculate shares
        uint256 buybackAmount = (NFT_SALES_BUYBACK * _paymentAmount) / 10000;
        uint256 creatorAmount = (CREATOR_SHARE * _paymentAmount) / 10000;
        uint256 treasuryAmount = _paymentAmount - buybackAmount - creatorAmount;
        
        // Get creator address
        address creator = tokenCreators[_tokenId];
        if (creator == address(0)) {
            creator = defaultCreator;
        }
        
        // Process buyback contribution
        if (buybackAmount > 0) {
            ikigaiToken.safeApprove(address(buybackEngine), buybackAmount);
            buybackEngine.collectRevenue(keccak256("NFT_SALES"), buybackAmount);
            emit BuybackContribution(buybackAmount);
        }
        
        // Pay creator
        if (creatorAmount > 0) {
            ikigaiToken.safeTransfer(creator, creatorAmount);
            emit CreatorPayment(creator, creatorAmount);
        }
        
        // Pay treasury
        if (treasuryAmount > 0) {
            ikigaiToken.safeTransfer(treasuryAddress, treasuryAmount);
            emit TreasuryPayment(treasuryAmount);
        }
    }
    
    /**
     * @notice Processes batch payments for multiple NFTs
     * @param _paymentAmounts Array of payment amounts
     * @param _tokenIds Array of token IDs
     */
    function processBatchPayments(
        uint256[] calldata _paymentAmounts,
        uint256[] calldata _tokenIds
    ) external nonReentrant {
        require(_paymentAmounts.length == _tokenIds.length, "Array length mismatch");
        require(_paymentAmounts.length <= 50, "Batch too large"); // Prevent gas limit issues
        
        uint256 totalPayment = 0;
        for (uint256 i = 0; i < _paymentAmounts.length; i++) {
            require(_paymentAmounts[i] > 0, "Zero payment");
            totalPayment += _paymentAmounts[i];
        }
        
        // Transfer total payment from sender
        ikigaiToken.safeTransferFrom(msg.sender, address(this), totalPayment);
        
        // Process each payment
        for (uint256 i = 0; i < _paymentAmounts.length; i++) {
            uint256 paymentAmount = _paymentAmounts[i];
            uint256 tokenId = _tokenIds[i];
            
            // Calculate shares
            uint256 buybackAmount = (NFT_SALES_BUYBACK * paymentAmount) / 10000;
            uint256 creatorAmount = (CREATOR_SHARE * paymentAmount) / 10000;
            uint256 treasuryAmount = paymentAmount - buybackAmount - creatorAmount;
            
            // Get creator address
            address creator = tokenCreators[tokenId];
            if (creator == address(0)) {
                creator = defaultCreator;
            }
            
            // Process payments
            if (buybackAmount > 0) {
                ikigaiToken.safeApprove(address(buybackEngine), buybackAmount);
                buybackEngine.collectRevenue(keccak256("NFT_SALES"), buybackAmount);
                emit BuybackContribution(buybackAmount);
            }
            
            if (creatorAmount > 0) {
                ikigaiToken.safeTransfer(creator, creatorAmount);
                emit CreatorPayment(creator, creatorAmount);
            }
            
            if (treasuryAmount > 0) {
                ikigaiToken.safeTransfer(treasuryAddress, treasuryAmount);
                emit TreasuryPayment(treasuryAmount);
            }
        }
    }
    
    /**
     * @notice Gets staking discount based on staked amount
     * @param _stakedAmount Amount staked
     * @return Discount in basis points
     */
    function getStakingDiscount(uint256 _stakedAmount) public view returns (uint256) {
        uint256 discount = 0;
        
        for (uint256 i = 0; i < discountTiers.length; i++) {
            if (_stakedAmount >= discountTiers[i].stakeAmount && 
                discountTiers[i].discountBps > discount) {
                discount = discountTiers[i].discountBps;
            }
        }
        
        return discount;
    }
    
    /**
     * @notice Sets creator for a specific token
     * @param _tokenId Token ID
     * @param _creator Creator address
     */
    function setTokenCreator(uint256 _tokenId, address _creator) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(_creator != address(0), "Invalid creator");
        tokenCreators[_tokenId] = _creator;
    }
    
    /**
     * @notice Updates the buyback engine address
     * @param _newBuybackEngine New buyback engine address
     */
    function updateBuybackEngine(address _newBuybackEngine) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(_newBuybackEngine != address(0), "Invalid address");
        buybackEngine = IBuybackEngine(_newBuybackEngine);
        emit BuybackEngineUpdated(_newBuybackEngine);
    }
    
    /**
     * @notice Updates the treasury address
     * @param _newTreasury New treasury address
     */
    function updateTreasury(address _newTreasury) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(_newTreasury != address(0), "Invalid address");
        treasuryAddress = _newTreasury;
        emit TreasuryUpdated(_newTreasury);
    }
    
    /**
     * @notice Updates the default creator address
     * @param _newCreator New default creator address
     */
    function updateDefaultCreator(address _newCreator) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(_newCreator != address(0), "Invalid address");
        defaultCreator = _newCreator;
        emit DefaultCreatorUpdated(_newCreator);
    }
    
    /**
     * @notice Adjusts revenue allocation percentages
     * @param _buybackShare New buyback share (in basis points)
     * @param _creatorShare New creator share (in basis points)
     * @param _treasuryShare New treasury share (in basis points)
     */
    function updateRevenueShares(
        uint256 _buybackShare,
        uint256 _creatorShare,
        uint256 _treasuryShare
    ) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(_buybackShare + _creatorShare + _treasuryShare == 10000, "Must total 100%");
        
        // Update revenue shares
        NFT_SALES_BUYBACK = _buybackShare;
        CREATOR_SHARE = _creatorShare;
        TREASURY_SHARE = _treasuryShare;
        
        emit RevenueSharesUpdated(_buybackShare, _creatorShare, _treasuryShare);
    }
    
    /**
     * @notice Updates staking requirements
     * @param _minStakeAmount Minimum stake amount
     * @param _minStakeDuration Minimum stake duration
     */
    function updateStakingRequirements(uint256 _minStakeAmount, uint256 _minStakeDuration) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        minStakeAmount = _minStakeAmount;
        minStakeDuration = _minStakeDuration;
        emit StakingRequirementsUpdated(_minStakeAmount, _minStakeDuration);
    }
    
    /**
     * @notice Adds or updates a discount tier
     * @param _index Index of tier (use array length for new tier)
     * @param _stakeAmount Stake amount for tier
     * @param _discountBps Discount in basis points
     */
    function setDiscountTier(uint256 _index, uint256 _stakeAmount, uint256 _discountBps) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(_discountBps <= 5000, "Max discount is 50%");
        
        if (_index >= discountTiers.length) {
            discountTiers.push(DiscountTier(_stakeAmount, _discountBps));
        } else {
            discountTiers[_index] = DiscountTier(_stakeAmount, _discountBps);
        }
        
        emit DiscountTierAdded(_stakeAmount, _discountBps);
    }
    
    /**
     * @notice Updates whitelist status for users
     * @param _users Array of user addresses
     * @param _statuses Array of whitelist statuses
     */
    function updateWhitelist(address[] calldata _users, bool[] calldata _statuses) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(_users.length == _statuses.length, "Array length mismatch");
        
        for (uint256 i = 0; i < _users.length; i++) {
            whitelist[_users[i]] = _statuses[i];
            emit WhitelistUpdated(_users[i], _statuses[i]);
        }
    }
    
    /**
     * @notice Updates the mint price
     * @param _mintPrice New mint price
     */
    function updateMintPrice(uint256 _mintPrice) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        mintPrice = _mintPrice;
        emit MintPriceUpdated(_mintPrice);
    }
    
    /**
     * @notice Toggles staking requirement
     * @param _required Whether staking is required
     */
    function toggleStakingRequirement(bool _required) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        requiresStaking = _required;
        emit StakingRequirementToggled(_required);
    }
    
    /**
     * @notice Updates the staking contract
     * @param _stakingContract New staking contract address
     */
    function updateStakingContract(address _stakingContract) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(_stakingContract != address(0), "Invalid address");
        stakingContract = IStakingV2(_stakingContract);
    }
    
    /**
     * @notice Emergency token recovery
     * @param _token Token address
     * @param _amount Amount to recover
     */
    function emergencyTokenRecovery(address _token, uint256 _amount) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }
    
    /**
     * @notice Override to add creator tracking
     */
    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual override {
        super._beforeTokenTransfers(from, to, startTokenId, quantity);
        
        // If this is a mint (from == 0) and no creator is set, set the recipient as creator
        if (from == address(0)) {
            for (uint256 i = 0; i < quantity; i++) {
                uint256 tokenId = startTokenId + i;
                if (tokenCreators[tokenId] == address(0)) {
                    tokenCreators[tokenId] = to;
                }
            }
        }
    }
    
    /**
     * @notice Gets collection bonus for a user
     * @param _user User address
     * @return Bonus in basis points
     */
    function getCollectionBonus(address _user) public view returns (uint256) {
        uint256 bonus = 0;
        uint256 rareCollections = 0;
        
        for (uint i = 0; i < registeredCollections.length; i++) {
            address collection = registeredCollections[i];
            if (IERC721(collection).balanceOf(_user) > 0) {
                // Apply rarity multiplier (default 100 = 1x)
                uint256 multiplier = collectionRarityMultiplier[collection];
                if (multiplier == 0) multiplier = 100;
                
                bonus += (collectionBonusBps * multiplier) / 100;
                rareCollections++;
            }
        }
        
        // Add special bonus for holding 3+ collections
        if (rareCollections >= 3) {
            bonus += 250; // Extra 2.5% for 3+ collections
        }
        
        return bonus > maxCollectionBonus ? maxCollectionBonus : bonus;
    }
    
    /**
     * @notice Registers a collection for synergy bonuses
     * @param _collection Collection address
     */
    function registerCollection(address _collection) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(_collection != address(0), "Invalid address");
        require(!isRegisteredCollection[_collection], "Already registered");
        
        registeredCollections.push(_collection);
        isRegisteredCollection[_collection] = true;
        
        emit CollectionRegistered(_collection);
    }
    
    /**
     * @notice Updates collection bonus parameters
     * @param _bonusBps Bonus per collection in basis points
     * @param _maxBonus Maximum bonus in basis points
     */
    function updateCollectionBonus(uint256 _bonusBps, uint256 _maxBonus) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(_bonusBps <= 500, "Max 5% per collection");
        require(_maxBonus <= 2000, "Max 20% total");
        
        collectionBonusBps = _bonusBps;
        maxCollectionBonus = _maxBonus;
        
        emit CollectionBonusUpdated(_bonusBps, _maxBonus);
    }
    
    /**
     * @notice Mints NFT with referral
     * @param _quantity Number of NFTs to mint
     * @param _referrer Address of the referrer
     */
    function mintWithReferral(uint256 _quantity, address _referrer) external nonReentrant {
        require(_quantity > 0, "Invalid quantity");
        require(totalSupply() + _quantity <= maxSupply, "Exceeds max supply");
        require(_referrer != msg.sender, "Cannot refer yourself");
        require(_referrer != address(0), "Invalid referrer");
        
        // Set referrer if not already set
        if (referrers[msg.sender] == address(0)) {
            referrers[msg.sender] = _referrer;
        }
        
        // Check staking requirements if enabled
        uint256 discountBps = 0;
        if (requiresStaking) {
            (uint256 stakedAmount, uint256 lockDuration) = stakingContract.getUserStakeInfo(msg.sender);
            require(stakedAmount >= minStakeAmount, "Insufficient stake");
            require(lockDuration >= minStakeDuration, "Insufficient lock duration");
            
            // Calculate discount based on stake amount
            discountBps = getStakingDiscount(stakedAmount);
        }
        
        // Add whitelist discount if applicable
        if (whitelist[msg.sender]) {
            discountBps += whitelistDiscountBps;
        }
        
        // Add collection bonus if applicable
        discountBps += getCollectionBonus(msg.sender);
        
        // Cap discount at 50%
        if (discountBps > 5000) {
            discountBps = 5000;
        }
        
        // Calculate final price with discount
        uint256 discountedPrice = mintPrice - ((mintPrice * discountBps) / 10000);
        uint256 totalPrice = discountedPrice * _quantity;
        
        // Calculate referral reward
        uint256 referralAmount = (totalPrice * getReferralRewardBps(msg.sender)) / 10000;
        referralCount[_referrer]++;
        
        // Transfer payment from sender
        ikigaiToken.safeTransferFrom(msg.sender, address(this), totalPrice - referralAmount);
        
        // Process payment distribution
        _processPayment(totalPrice - referralAmount);
        
        // Mint NFT
        _safeMint(msg.sender, _quantity);
        
        emit ReferralRecorded(msg.sender, _referrer, referralAmount);
    }
    
    /**
     * @notice Claims referral rewards
     */
    function claimReferralRewards() external nonReentrant {
        uint256 rewards = referralCount[msg.sender];
        require(rewards > 0, "No rewards to claim");
        
        referralCount[msg.sender] = 0;
        ikigaiToken.safeTransfer(msg.sender, rewards);
        
        emit ReferralRewardsClaimed(msg.sender, rewards);
    }
    
    /**
     * @notice Updates referral reward percentage
     * @param _rewardBps New reward percentage in basis points
     */
    function updateReferralReward(uint256 _rewardBps) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(_rewardBps <= 1000, "Max 10%");
        
        referralTiers.push(ReferralTier({minReferrals: 0, rewardBps: _rewardBps}));
        emit ReferralRewardUpdated(_rewardBps);
    }
    
    /**
     * @notice Gets referral reward percentage for a referrer
     * @param _referrer Address of the referrer
     * @return Reward percentage in basis points
     */
    function getReferralRewardBps(address _referrer) public view returns (uint256) {
        uint256 count = referralCount[_referrer];
        
        // Find appropriate tier
        for (int i = int(referralTiers.length) - 1; i >= 0; i--) {
            if (count >= referralTiers[uint(i)].minReferrals) {
                return referralTiers[uint(i)].rewardBps;
            }
        }
        
        return referralTiers[0].rewardBps; // Default to first tier
    }
}
}