// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IBuybackEngine.sol";

/**
 * @title ProtocolNFTVault
 * @notice Manages protocol-owned NFTs and revenue distribution
 * @dev Holds NFTs and distributes revenue to buyback and treasury
 */
contract ProtocolNFTVault is AccessControl, ERC721Holder, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // Roles
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    // Protocol-owned NFTs
    mapping(address => mapping(uint256 => bool)) public ownedNFTs;
    mapping(address => uint256[]) public collectionTokens;
    address[] public collections;
    mapping(address => bool) public registeredCollections;
    
    // Revenue sharing
    uint256 public buybackShareBps = 2000; // Default 20%
    uint256 public treasuryShareBps = 8000; // Default 80%
    uint256 public lastAllocationUpdate;
    uint256 public constant ALLOCATION_COOLDOWN = 7 days;
    
    // External contracts
    IBuybackEngine public buybackEngine;
    address public treasuryAddress;
    IERC20 public ikigaiToken;
    
    // Events
    event NFTAcquired(address indexed collection, uint256 indexed tokenId);
    event NFTSold(address indexed collection, uint256 indexed tokenId, uint256 price);
    event RevenueDistributed(uint256 buybackAmount, uint256 treasuryAmount);
    event CollectionRegistered(address indexed collection);
    event BuybackEngineUpdated(address indexed newEngine);
    event TreasuryUpdated(address indexed newTreasury);
    event BuybackAllocationUpdated(uint256 buybackShareBps, uint256 treasuryShareBps);
    
    constructor(
        address _buybackEngine,
        address _treasury,
        address _ikigaiToken
    ) {
        require(_buybackEngine != address(0), "Invalid buyback engine");
        require(_treasury != address(0), "Invalid treasury");
        require(_ikigaiToken != address(0), "Invalid token");
        
        buybackEngine = IBuybackEngine(_buybackEngine);
        treasuryAddress = _treasury;
        ikigaiToken = IERC20(_ikigaiToken);
        
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
    }
    
    /**
     * @notice Acquires an NFT for the protocol
     * @param _collection NFT collection address
     * @param _tokenId Token ID to acquire
     */
    function acquireNFT(address _collection, uint256 _tokenId) external nonReentrant {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Not operator");
        
        // Register collection if not already registered
        if (!registeredCollections[_collection]) {
            collections.push(_collection);
            registeredCollections[_collection] = true;
            emit CollectionRegistered(_collection);
        }
        
        // Transfer NFT to vault
        IERC721(_collection).safeTransferFrom(msg.sender, address(this), _tokenId);
        
        // Record ownership
        ownedNFTs[_collection][_tokenId] = true;
        collectionTokens[_collection].push(_tokenId);
        
        emit NFTAcquired(_collection, _tokenId);
    }
    
    /**
     * @notice Sells an NFT from the protocol
     * @param _collection NFT collection address
     * @param _tokenId Token ID to sell
     * @param _recipient Recipient of the NFT
     * @param _price Sale price in IKIGAI tokens
     */
    function sellNFT(
        address _collection,
        uint256 _tokenId,
        address _recipient,
        uint256 _price
    ) external nonReentrant {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Not operator");
        require(ownedNFTs[_collection][_tokenId], "NFT not owned");
        require(_recipient != address(0), "Invalid recipient");
        require(_price > 0, "Invalid price");
        
        // Transfer payment
        ikigaiToken.safeTransferFrom(_recipient, address(this), _price);
        
        // Transfer NFT
        IERC721(_collection).safeTransferFrom(address(this), _recipient, _tokenId);
        
        // Update ownership records
        ownedNFTs[_collection][_tokenId] = false;
        
        // Remove from collection tokens array
        _removeTokenFromCollection(_collection, _tokenId);
        
        // Distribute revenue
        _distributeRevenue(_price);
        
        emit NFTSold(_collection, _tokenId, _price);
    }
    
    /**
     * @notice Distributes revenue from NFT sales
     * @param _amount Amount to distribute
     */
    function _distributeRevenue(uint256 _amount) internal {
        uint256 buybackAmount = (_amount * buybackShareBps) / 10000;
        uint256 treasuryAmount = _amount - buybackAmount;
        
        // Send to buyback engine
        if (buybackAmount > 0) {
            ikigaiToken.safeApprove(address(buybackEngine), buybackAmount);
            buybackEngine.collectRevenue(keccak256("PROTOCOL_NFT"), buybackAmount);
        }
        
        // Send to treasury
        if (treasuryAmount > 0) {
            ikigaiToken.safeTransfer(treasuryAddress, treasuryAmount);
        }
        
        emit RevenueDistributed(buybackAmount, treasuryAmount);
    }
    
    /**
     * @notice Removes a token from the collection array
     * @param _collection Collection address
     * @param _tokenId Token ID to remove
     */
    function _removeTokenFromCollection(address _collection, uint256 _tokenId) internal {
        uint256[] storage tokens = collectionTokens[_collection];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == _tokenId) {
                // Replace with the last element and pop
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }
    }
    
    /**
     * @notice Gets all tokens owned in a collection
     * @param _collection Collection address
     * @return Array of token IDs
     */
    function getCollectionTokens(address _collection) external view returns (uint256[] memory) {
        return collectionTokens[_collection];
    }
    
    /**
     * @notice Gets all registered collections
     * @return Array of collection addresses
     */
    function getCollections() external view returns (address[] memory) {
        return collections;
    }
    
    /**
     * @notice Updates the buyback engine
     * @param _newEngine New buyback engine address
     */
    function updateBuybackEngine(address _newEngine) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(_newEngine != address(0), "Invalid address");
        
        buybackEngine = IBuybackEngine(_newEngine);
        emit BuybackEngineUpdated(_newEngine);
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
     * @notice Emergency function to recover tokens
     * @param _token Token address to recover
     */
    function recoverTokens(address _token) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(_token != address(ikigaiToken), "Cannot recover IKIGAI");
        
        IERC20 tokenToRecover = IERC20(_token);
        uint256 balance = tokenToRecover.balanceOf(address(this));
        tokenToRecover.safeTransfer(msg.sender, balance);
    }
    
    /**
     * @notice Updates the buyback allocation based on market conditions
     */
    function updateBuybackAllocation() external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Not operator");
        require(block.timestamp >= lastAllocationUpdate + ALLOCATION_COOLDOWN, "Cooldown active");
        
        // Get price data from buyback engine
        uint256 currentPrice = buybackEngine.getCurrentPrice();
        uint256 avg90DayPrice = buybackEngine.getLongTermAveragePrice();
        
        // Calculate price ratio (10000 = 100%)
        uint256 priceRatio = (currentPrice * 10000) / avg90DayPrice;
        
        // Adjust buyback allocation based on price
        if (priceRatio < 9000) { // Price < 90% of 90-day avg
            // Increase buyback to 40%
            buybackShareBps = 4000;
            treasuryShareBps = 6000;
        } else if (priceRatio > 11000) { // Price > 110% of 90-day avg
            // Decrease buyback to 10%
            buybackShareBps = 1000;
            treasuryShareBps = 9000;
        } else {
            // Reset to default
            buybackShareBps = 2000;
            treasuryShareBps = 8000;
        }
        
        lastAllocationUpdate = block.timestamp;
        emit BuybackAllocationUpdated(buybackShareBps, treasuryShareBps);
    }
} 