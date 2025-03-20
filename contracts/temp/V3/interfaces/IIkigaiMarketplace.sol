// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IIkigaiMarketplace
 * @notice Interface for the Ikigai NFT marketplace with advanced trading features
 * @dev Supports conditional orders, floor price tracking, and staking requirements
 */
interface IIkigaiMarketplace {
    /**
     * @notice Types of orders that can be created in the marketplace
     * @param BASIC Standard buy/sell order
     * @param CONDITIONAL Order that executes based on market conditions
     * @param FLOOR_SWEEP Order to buy at or below floor price
     */
    enum OrderType { BASIC, CONDITIONAL, FLOOR_SWEEP }

    /**
     * @notice Possible states of an order
     * @param ACTIVE Order is live and can be filled
     * @param FILLED Order has been executed
     * @param CANCELLED Order has been cancelled by the maker
     */
    enum OrderStatus { ACTIVE, FILLED, CANCELLED }

    /**
     * @notice Structure containing all order information
     * @param orderId Unique identifier for the order
     * @param maker Address that created the order
     * @param collection NFT collection contract address
     * @param tokenId ID of the specific NFT
     * @param price Price in IKIGAI tokens
     * @param orderType Type of order (BASIC, CONDITIONAL, FLOOR_SWEEP)
     * @param status Current status of the order
     * @param expiry Timestamp when the order expires
     * @param minFloorPrice Minimum floor price for conditional execution
     * @param maxFloorPrice Maximum floor price for conditional execution
     * @param volumeThreshold Required trading volume for execution
     * @param requiresStaking Whether the taker must be staking IKIGAI
     */
    struct Order {
        uint256 orderId;
        address maker;
        address collection;
        uint256 tokenId;
        uint256 price;
        OrderType orderType;
        OrderStatus status;
        uint256 expiry;
        uint256 minFloorPrice;
        uint256 maxFloorPrice;
        uint256 volumeThreshold;
        bool requiresStaking;
    }

    /**
     * @notice Creates a new order in the marketplace
     * @dev Validates order parameters and handles token approvals
     * @param collection NFT collection address
     * @param tokenId Token ID to trade
     * @param price Price in IKIGAI tokens
     * @param orderType Type of order to create
     * @param expiry Order expiration timestamp
     * @param minFloorPrice Minimum floor price for conditional orders
     * @param maxFloorPrice Maximum floor price for conditional orders
     * @param volumeThreshold Required volume for conditional orders
     * @param requiresStaking Whether taker must be staking
     */
    function createOrder(
        address collection,
        uint256 tokenId,
        uint256 price,
        OrderType orderType,
        uint256 expiry,
        uint256 minFloorPrice,
        uint256 maxFloorPrice,
        uint256 volumeThreshold,
        bool requiresStaking
    ) external;

    /**
     * @notice Executes an existing order
     * @dev Handles token transfers and updates market state
     * @param orderId ID of the order to fill
     */
    function fillOrder(uint256 orderId) external;

    /**
     * @notice Cancels an active order
     * @dev Only callable by the order maker
     * @param orderId ID of the order to cancel
     */
    function cancelOrder(uint256 orderId) external;

    /**
     * @notice Updates the floor price for a collection
     * @dev Only callable by authorized operators
     * @param collection NFT collection address
     * @param price New floor price in IKIGAI tokens
     */
    function updateFloorPrice(address collection, uint256 price) external;

    /**
     * @notice Retrieves all order IDs created by a user
     * @param user Address to query orders for
     * @return uint256[] Array of order IDs
     */
    function getUserOrders(address user) external view returns (uint256[] memory);

    /**
     * @notice Gets detailed information about an order
     * @param orderId ID of the order to query
     * @return Order Complete order information
     */
    function getOrder(uint256 orderId) external view returns (Order memory);

    /**
     * @notice Gets detailed information about an order (struct components)
     * @param orderId ID of the order to query
     * @return orderId_ Order ID
     * @return maker Order creator address
     * @return collection NFT collection address
     * @return tokenId NFT token ID
     * @return price Order price
     * @return orderType Type of order
     * @return status Order status
     * @return expiry Order expiration
     * @return minFloorPrice Minimum floor price
     * @return maxFloorPrice Maximum floor price
     * @return volumeThreshold Required volume
     * @return requiresStaking Staking requirement
     */
    function orders(uint256 orderId) external view returns (
        uint256 orderId_,
        address maker,
        address collection,
        uint256 tokenId,
        uint256 price,
        OrderType orderType,
        OrderStatus status,
        uint256 expiry,
        uint256 minFloorPrice,
        uint256 maxFloorPrice,
        uint256 volumeThreshold,
        bool requiresStaking
    );

    /**
     * @notice Gets the current floor price for a collection
     * @param collection NFT collection address
     * @return uint256 Current floor price in IKIGAI tokens
     */
    function floorPrices(address collection) external view returns (uint256);

    /**
     * @notice Gets the trading volume for a collection
     * @param collection NFT collection address
     * @return uint256 Total trading volume in IKIGAI tokens
     */
    function collectionVolumes(address collection) external view returns (uint256);

    /**
     * @notice Gets the next available order ID
     * @return uint256 Next order ID to be assigned
     */
    function nextOrderId() external view returns (uint256);

    /**
     * @notice Pauses all marketplace operations
     * @dev Only callable by authorized operators
     */
    function pause() external;

    /**
     * @notice Resumes marketplace operations
     * @dev Only callable by authorized operators
     */
    function unpause() external;

    /**
     * @notice Emitted when a new order is created
     * @param orderId Unique identifier for the order
     * @param maker Address that created the order
     * @param collection NFT collection address
     * @param tokenId NFT token ID
     * @param price Order price in IKIGAI tokens
     * @param orderType Type of order created
     */
    event OrderCreated(
        uint256 indexed orderId,
        address indexed maker,
        address indexed collection,
        uint256 tokenId,
        uint256 price,
        OrderType orderType
    );

    /**
     * @notice Emitted when an order is filled
     * @param orderId ID of the filled order
     * @param maker Order creator address
     * @param taker Address that filled the order
     * @param price Execution price in IKIGAI tokens
     */
    event OrderFilled(
        uint256 indexed orderId,
        address indexed maker,
        address indexed taker,
        uint256 price
    );

    /**
     * @notice Emitted when an order is cancelled
     * @param orderId ID of the cancelled order
     */
    event OrderCancelled(uint256 indexed orderId);

    /**
     * @notice Emitted when a collection's floor price is updated
     * @param collection NFT collection address
     * @param price New floor price in IKIGAI tokens
     */
    event FloorPriceUpdated(address indexed collection, uint256 price);

    /**
     * @notice Emitted when a collection's trading volume is updated
     * @param collection NFT collection address
     * @param volume New total trading volume
     */
    event VolumeUpdated(address indexed collection, uint256 volume);
} 