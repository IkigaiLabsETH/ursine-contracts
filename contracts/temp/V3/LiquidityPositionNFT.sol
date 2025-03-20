// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title LiquidityPositionNFT
 * @notice Tokenizes liquidity positions as NFTs
 * @dev Allows trading and composability of LP positions
 */
contract LiquidityPositionNFT is ERC721, ERC721Enumerable, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // Roles
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    // Liquidity position
    struct LiquidityPosition {
        address pair;
        uint256 liquidity;
        uint256 startTime;
        uint256 lockDuration;
        bool withdrawn;
    }
    
    // Storage
    mapping(uint256 => LiquidityPosition) public positions;
    uint256 public nextTokenId = 1;
    
    // Rewards
    mapping(address => uint256) public pairRewardRates;
    mapping(uint256 => uint256) public positionRewards;
    IERC20 public rewardToken;
    
    // Events
    event PositionCreated(uint256 indexed tokenId, address indexed owner, address pair, uint256 liquidity, uint256 lockDuration);
    event PositionWithdrawn(uint256 indexed tokenId, address indexed owner, uint256 liquidity);
    event RewardsClaimed(uint256 indexed tokenId, address indexed owner, uint256 amount);
    event RewardRateUpdated(address indexed pair, uint256 rate);
    
    constructor(string memory _name, string memory _symbol, address _rewardToken) ERC721(_name, _symbol) {
        require(_rewardToken != address(0), "Invalid reward token");
        rewardToken = IERC20(_rewardToken);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
    }
    
    /**
     * @notice Creates a new liquidity position NFT
     * @param _pair LP token address
     * @param _liquidity Amount of LP tokens
     * @param _lockDuration Lock duration in seconds
     * @return tokenId ID of the created NFT
     */
    function mintPositionNFT(
        address _pair,
        uint256 _liquidity,
        uint256 _lockDuration
    ) external nonReentrant returns (uint256) {
        require(_pair != address(0), "Invalid pair");
        require(_liquidity > 0, "Zero liquidity");
        require(_lockDuration >= 7 days, "Min 7 days lock");
        require(_lockDuration <= 365 days, "Max 365 days lock");
        
        // Transfer LP tokens to this contract
        IERC20(_pair).safeTransferFrom(msg.sender, address(this), _liquidity);
        
        // Create position
        uint256 tokenId = nextTokenId++;
        positions[tokenId] = LiquidityPosition({
            pair: _pair,
            liquidity: _liquidity,
            startTime: block.timestamp,
            lockDuration: _lockDuration,
            withdrawn: false
        });
        
        // Mint NFT
        _safeMint(msg.sender, tokenId);
        
        emit PositionCreated(tokenId, msg.sender, _pair, _liquidity, _lockDuration);
        
        return tokenId;
    }
    
    /**
     * @notice Withdraws liquidity from a position
     * @param _tokenId Token ID to withdraw
     */
    function withdrawPosition(uint256 _tokenId) external nonReentrant {
        require(_isApprovedOrOwner(msg.sender, _tokenId), "Not approved or owner");
        
        LiquidityPosition storage position = positions[_tokenId];
        require(!position.withdrawn, "Already withdrawn");
        require(block.timestamp >= position.startTime + position.lockDuration, "Still locked");
        
        // Mark as withdrawn
        position.withdrawn = true;
        
        // Transfer LP tokens back to owner
        IERC20(position.pair).safeTransfer(msg.sender, position.liquidity);
        
        // Transfer any rewards
        uint256 rewards = calculateRewards(_tokenId);
        if (rewards > 0) {
            positionRewards[_tokenId] = 0;
            rewardToken.safeTransfer(msg.sender, rewards);
            emit RewardsClaimed(_tokenId, msg.sender, rewards);
        }
        
        emit PositionWithdrawn(_tokenId, msg.sender, position.liquidity);
    }
    
    /**
     * @notice Claims rewards without withdrawing position
     * @param _tokenId Token ID to claim rewards for
     */
    function claimRewards(uint256 _tokenId) external nonReentrant {
        require(_isApprovedOrOwner(msg.sender, _tokenId), "Not approved or owner");
        
        LiquidityPosition storage position = positions[_tokenId];
        require(!position.withdrawn, "Position withdrawn");
        
        uint256 rewards = calculateRewards(_tokenId);
        require(rewards > 0, "No rewards");
        
        // Reset rewards
        positionRewards[_tokenId] = 0;
        
        // Transfer rewards
        rewardToken.safeTransfer(msg.sender, rewards);
        
        emit RewardsClaimed(_tokenId, msg.sender, rewards);
    }
    
    /**
     * @notice Calculates rewards for a position
     * @param _tokenId Token ID to calculate rewards for
     * @return Rewards amount
     */
    function calculateRewards(uint256 _tokenId) public view returns (uint256) {
        LiquidityPosition storage position = positions[_tokenId];
        if (position.withdrawn) return 0;
        
        uint256 rewardRate = pairRewardRates[position.pair];
        if (rewardRate == 0) return 0;
        
        uint256 timeStaked = block.timestamp - position.startTime;
        if (timeStaked > position.lockDuration) {
            timeStaked = position.lockDuration;
        }
        
        // Calculate time-weighted rewards
        uint256 baseReward = (position.liquidity * rewardRate * timeStaked) / (365 days * 10000);
        
        // Apply lock duration multiplier (longer locks get higher rewards)
        uint256 lockMultiplier = 10000 + (position.lockDuration * 5000 / 365 days); // Up to 1.5x for 1 year
        
        return (baseReward * lockMultiplier) / 10000;
    }
    
    /**
     * @notice Updates reward rate for a pair
     * @param _pair Pair address
     * @param _rewardRate New reward rate in basis points
     */
    function updateRewardRate(address _pair, uint256 _rewardRate) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Not operator");
        require(_pair != address(0), "Invalid pair");
        require(_rewardRate <= 5000, "Rate too high"); // Max 50% APY
        
        pairRewardRates[_pair] = _rewardRate;
        
        emit RewardRateUpdated(_pair, _rewardRate);
    }
    
    /**
     * @notice Gets all positions of an owner
     * @param _owner Owner address
     * @return Array of token IDs
     */
    function getPositionsOfOwner(address _owner) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](balance);
        
        for (uint256 i = 0; i < balance; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        
        return tokenIds;
    }
    
    /**
     * @notice Gets position details
     * @param _tokenId Token ID
     * @return pair Pair address
     * @return liquidity Liquidity amount
     * @return startTime Start time
     * @return lockDuration Lock duration
     * @return withdrawn Whether position is withdrawn
     * @return rewards Pending rewards
     */
    function getPositionDetails(uint256 _tokenId) external view returns (
        address pair,
        uint256 liquidity,
        uint256 startTime,
        uint256 lockDuration,
        bool withdrawn,
        uint256 rewards
    ) {
        LiquidityPosition storage position = positions[_tokenId];
        return (
            position.pair,
            position.liquidity,
            position.startTime,
            position.lockDuration,
            position.withdrawn,
            calculateRewards(_tokenId)
        );
    }
    
    /**
     * @notice Adds rewards to the contract
     * @param _amount Amount to add
     */
    function addRewards(uint256 _amount) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Not operator");
        require(_amount > 0, "Zero amount");
        
        rewardToken.safeTransferFrom(msg.sender, address(this), _amount);
    }
    
    /**
     * @notice Emergency function to recover tokens
     * @param _token Token address
     */
    function recoverTokens(address _token) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(_token != address(rewardToken), "Cannot recover reward token");
        
        IERC20 tokenToRecover = IERC20(_token);
        uint256 balance = tokenToRecover.balanceOf(address(this));
        tokenToRecover.safeTransfer(msg.sender, balance);
    }
    
    // Required overrides for ERC721Enumerable
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }
    
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
} 