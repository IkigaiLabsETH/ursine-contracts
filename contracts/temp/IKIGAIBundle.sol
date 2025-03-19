// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@thirdweb-dev/contracts/prebuilts/multiwrap/Multiwrap.sol";

/**
 * @title IKIGAI Bundle
 * @notice Bundle contract for wrapping IKIGAI tokens, NFTs, and other assets
 */
contract IKIGAIBundle is Multiwrap {
    // Bundle types
    enum BundleType { GENESIS, COLLECTION, CUSTOM }
    
    // Bundle info
    struct IKIGAIBundleInfo {
        BundleType bundleType;
        uint256 createdAt;
        address creator;
    }
    
    // User's bundle count by type
    mapping(address => mapping(BundleType => uint256)) public userBundleCount;
    
    // Bundle info by token ID
    mapping(uint256 => IKIGAIBundleInfo) public bundleInfo;
    
    // Fee percentage for bundle creation (in basis points, e.g. 250 = 2.5%)
    uint256 public bundleFeePercentage;
    
    // Fee recipient
    address public feeRecipient;
    
    // Events
    event GenesisBundle(uint256 indexed tokenId, address indexed creator);
    event CollectionBundle(uint256 indexed tokenId, address indexed creator);
    event CustomBundle(uint256 indexed tokenId, address indexed creator);
    event BundleFeeUpdated(uint256 newFeePercentage);
    event FeeRecipientUpdated(address newFeeRecipient);

    /**
     * @notice Constructor
     * @param _defaultAdmin Default admin address
     * @param _name NFT name
     * @param _symbol NFT symbol
     * @param _royaltyRecipient Royalty recipient address
     * @param _royaltyBps Royalty basis points
     */
    constructor(
        address _defaultAdmin,
        string memory _name,
        string memory _symbol,
        address _royaltyRecipient,
        uint128 _royaltyBps
    ) {
        initialize(
            _defaultAdmin,
            _name,
            _symbol,
            "",  // contractURI
            new address[](0),  // trustedForwarders
            _royaltyRecipient,
            _royaltyBps
        );
    }
    
    /**
     * @notice Set the bundle fee percentage
     * @param _feePercentage New fee percentage in basis points
     */
    function setBundleFeePercentage(uint256 _feePercentage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_feePercentage <= 1000, "Fee too high"); // Max 10%
        bundleFeePercentage = _feePercentage;
        emit BundleFeeUpdated(_feePercentage);
    }
    
    /**
     * @notice Set the fee recipient
     * @param _feeRecipient New fee recipient address
     */
    function setFeeRecipient(address _feeRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_feeRecipient != address(0), "Zero address");
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }
    
    /**
     * @notice Create a Genesis bundle
     * @param _contents Contents to wrap
     * @param _uriForWrappedToken URI for the wrapped token
     * @return tokenId ID of the created bundle
     */
    function createGenesisBundle(
        Token[] calldata _contents,
        string calldata _uriForWrappedToken
    ) external payable returns (uint256 tokenId) {
        // Wrap tokens
        tokenId = wrap(_contents, _uriForWrappedToken, msg.sender);
        
        // Store bundle info
        bundleInfo[tokenId] = IKIGAIBundleInfo({
            bundleType: BundleType.GENESIS,
            createdAt: block.timestamp,
            creator: msg.sender
        });
        
        // Emit event
        emit GenesisBundle(tokenId, msg.sender);
        
        // Update user bundle count
        userBundleCount[msg.sender][BundleType.GENESIS] += 1;
        
        return tokenId;
    }
    
    /**
     * @notice Create a Collection bundle
     * @param _contents Contents to wrap
     * @param _uriForWrappedToken URI for the wrapped token
     * @return tokenId ID of the created bundle
     */
    function createCollectionBundle(
        Token[] calldata _contents,
        string calldata _uriForWrappedToken
    ) external payable returns (uint256 tokenId) {
        // Wrap tokens
        tokenId = wrap(_contents, _uriForWrappedToken, msg.sender);
        
        // Store bundle info
        bundleInfo[tokenId] = IKIGAIBundleInfo({
            bundleType: BundleType.COLLECTION,
            createdAt: block.timestamp,
            creator: msg.sender
        });
        
        // Emit event
        emit CollectionBundle(tokenId, msg.sender);
        
        // Update user bundle count
        userBundleCount[msg.sender][BundleType.COLLECTION] += 1;
        
        return tokenId;
    }
    
    /**
     * @notice Create a Custom bundle
     * @param _contents Contents to wrap
     * @param _uriForWrappedToken URI for the wrapped token
     * @return tokenId ID of the created bundle
     */
    function createCustomBundle(
        Token[] calldata _contents,
        string calldata _uriForWrappedToken
    ) external payable returns (uint256 tokenId) {
        // Wrap tokens
        tokenId = wrap(_contents, _uriForWrappedToken, msg.sender);
        
        // Store bundle info
        bundleInfo[tokenId] = IKIGAIBundleInfo({
            bundleType: BundleType.CUSTOM,
            createdAt: block.timestamp,
            creator: msg.sender
        });
        
        // Emit event
        emit CustomBundle(tokenId, msg.sender);
        
        // Update user bundle count
        userBundleCount[msg.sender][BundleType.CUSTOM] += 1;
        
        return tokenId;
    }
    
    /**
     * @notice Override wrap to collect fees
     */
    function wrap(
        Token[] calldata _tokensToWrap,
        string calldata _uriForWrappedToken,
        address _recipient
    ) public payable override returns (uint256 tokenId) {
        // Call parent wrap function
        return super.wrap(_tokensToWrap, _uriForWrappedToken, _recipient);
    }
    
    /**
     * @notice Get bundle info
     * @param _tokenId Token ID of the bundle
     * @return Bundle info
     */
    function getBundleInfo(uint256 _tokenId) external view returns (IKIGAIBundleInfo memory) {
        return bundleInfo[_tokenId];
    }
    
    /**
     * @notice Get user's bundle count by type
     * @param _user User address
     * @param _bundleType Bundle type
     * @return Bundle count
     */
    function getUserBundleCount(address _user, BundleType _bundleType) external view returns (uint256) {
        return userBundleCount[_user][_bundleType];
    }
} 