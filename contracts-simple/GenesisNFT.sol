// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@thirdweb-dev/contracts/base/ERC721Drop.sol";
import "@thirdweb-dev/contracts/extension/PermissionsEnumerable.sol";

/**
 * @title IKIGAI Genesis NFT
 * @notice ERC721 NFT collection for the IKIGAI Protocol with claim conditions
 */
contract GenesisNFT is ERC721Drop {
    // Token vesting duration in seconds (90 days)
    uint256 public constant VESTING_DURATION = 90 days;
    
    // Mapping to track vesting start time for each token
    mapping(uint256 => uint256) public vestingStart;
    
    // Reference to the IKIGAI token contract
    address public ikigaiToken;
    
    // Amount of IKIGAI tokens to be vested per NFT
    uint256 public tokensPerNFT;

    constructor(
        address _defaultAdmin,
        string memory _name,
        string memory _symbol,
        address _royaltyRecipient,
        uint16 _royaltyBps,
        address _primarySaleRecipient
    )
        ERC721Drop(
            _defaultAdmin,
            _name,
            _symbol,
            _royaltyRecipient,
            _royaltyBps,
            _primarySaleRecipient
        )
    {}
    
    /**
     * @notice Set the IKIGAI token contract address
     * @param _ikigaiToken Address of the IKIGAI token contract
     */
    function setIkigaiToken(address _ikigaiToken) external onlyOwner {
        ikigaiToken = _ikigaiToken;
    }
    
    /**
     * @notice Set the amount of IKIGAI tokens to be vested per NFT
     * @param _tokensPerNFT Amount of tokens per NFT
     */
    function setTokensPerNFT(uint256 _tokensPerNFT) external onlyOwner {
        tokensPerNFT = _tokensPerNFT;
    }
    
    /**
     * @notice Override _transferTokensOnClaim to start vesting
     * @param _receiver Address receiving the NFT
     * @param _quantity Quantity of NFTs claimed
     */
    function _transferTokensOnClaim(address _receiver, uint256 _quantity) internal override returns (uint256) {
        uint256 nextTokenIdToMint = nextTokenIdToClaim();
        
        for (uint256 i = 0; i < _quantity; i++) {
            uint256 tokenId = nextTokenIdToMint + i;
            vestingStart[tokenId] = block.timestamp;
        }
        
        return super._transferTokensOnClaim(_receiver, _quantity);
    }
    
    /**
     * @notice Calculate vested amount for a specific token
     * @param _tokenId Token ID to check vesting for
     * @return vestedAmount Amount of tokens vested so far
     */
    function getVestedAmount(uint256 _tokenId) public view returns (uint256 vestedAmount) {
        if (vestingStart[_tokenId] == 0) {
            return 0;
        }
        
        uint256 elapsedTime = block.timestamp - vestingStart[_tokenId];
        
        if (elapsedTime >= VESTING_DURATION) {
            return tokensPerNFT;
        }
        
        return (tokensPerNFT * elapsedTime) / VESTING_DURATION;
    }
    
    /**
     * @notice Claim vested tokens for a specific NFT
     * @param _tokenId Token ID to claim vested tokens for
     */
    function claimVestedTokens(uint256 _tokenId) external {
        require(ownerOf(_tokenId) == msg.sender, "Not token owner");
        
        uint256 vestedAmount = getVestedAmount(_tokenId);
        require(vestedAmount > 0, "No tokens vested yet");
        
        // Interface for minting IKIGAI tokens
        bytes memory data = abi.encodeWithSignature("mintTo(address,uint256)", msg.sender, vestedAmount);
        (bool success, ) = ikigaiToken.call(data);
        require(success, "Token minting failed");
        
        // Reset vesting to prevent double claims
        vestingStart[_tokenId] = block.timestamp;
    }
} 