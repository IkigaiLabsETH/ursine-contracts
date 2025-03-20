// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./interfaces/IBuybackEngine.sol";

/**
 * @title GenesisNFTStorage
 * @notice Storage contract for GenesisNFT - provides persistent storage layer for proxy
 * @dev All state variables should be defined here to maintain storage layout for upgrades
 */
abstract contract GenesisNFTStorage is Initializable, AccessControl {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Strings for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Access control roles
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    bytes32 public constant WHITELIST_MANAGER_ROLE = keccak256("WHITELIST_MANAGER_ROLE");
    bytes32 public constant PRICE_MANAGER_ROLE = keccak256("PRICE_MANAGER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant METADATA_ROLE = keccak256("METADATA_ROLE");
    bytes32 public constant UPGRADE_ROLE = keccak256("UPGRADE_ROLE");
    
    // Token references
    IERC20 public beraToken;
    IERC20 public ikigaiToken;
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
    SalePhase public currentPhase;

    // Circuit breaker
    bool public emergencyMode;
    
    // Rate limiting
    uint256 public claimCooldown;
    uint256 public maxClaimAmount;
    uint256 public claimRateLimit;
    uint256 public totalClaimedInWindow;
    uint256 public claimWindowStart;
    uint256 public claimWindowDuration;
    
    // NFT collection parameters
    string public name;
    string public symbol;
    address public royaltyRecipient;
    uint128 public royaltyBps;
    uint256 public maxSupply;
    uint256 public maxMintPerWallet;
    uint256 public maxMintPerTx;
    mapping(address => uint256) public mintedPerWallet;
    uint256 internal _currentIndex;
    mapping(uint256 => address) internal _owners;
    
    // Metadata and reveal features
    mapping(uint256 => string) internal _tokenURIs;
    bool public revealed;
    string public notRevealedURI;
    string public baseURI;
    
    // Multi-token support
    mapping(address => bool) public acceptedTokens;
    mapping(address => uint256) public tokenPriceMultipliers; // 1000 = 1x, 1100 = 1.1x
    
    // Additional storage gap for future upgrades
    uint256[50] private __gap;
} 