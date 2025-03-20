// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ITreasuryV2
 * @notice Interface for the Ikigai V2 treasury management system
 * @dev Handles revenue distribution, liquidity management, and protocol reserves
 */
interface ITreasuryV2 {
    /**
     * @notice Distributes accumulated revenue according to protocol ratios
     * @dev Splits revenue between staking, liquidity, operations, and burns
     */
    function distributeRevenue() external;

    /**
     * @notice Updates critical protocol addresses
     * @dev Only callable by admin role
     * @param _stakingContract New staking contract address
     * @param _liquidityPool New liquidity pool address
     * @param _operationsWallet New operations wallet address
     */
    function updateAddresses(
        address _stakingContract,
        address _liquidityPool,
        address _operationsWallet
    ) external;

    /**
     * @notice Checks if liquidity rebalancing is needed
     * @dev Compares current ratio against target and threshold
     * @return bool Whether rebalancing is needed
     * @return bool Whether liquidity should be added (true) or removed (false)
     */
    function needsRebalancing() external view returns (bool, bool);

    /**
     * @notice Rebalances protocol liquidity to maintain target ratio
     * @dev Only callable by rebalancer role, has cooldown period
     */
    function rebalanceLiquidity() external;

    /**
     * @notice Gets current treasury statistics
     * @return _totalAssets Total assets under management
     * @return _liquidityBalance Current liquidity balance
     * @return _liquidityRatio Current liquidity ratio
     * @return _lastRebalance Timestamp of last rebalance
     */
    function getTreasuryStats() external view returns (
        uint256 _totalAssets,
        uint256 _liquidityBalance,
        uint256 _liquidityRatio,
        uint256 _lastRebalance
    );

    /**
     * @notice Gets total assets under management
     * @return uint256 Total asset value
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Gets current liquidity balance
     * @return uint256 Liquidity amount
     */
    function liquidityBalance() external view returns (uint256);

    /**
     * @notice Gets timestamp of last rebalance
     * @return uint256 Last rebalance timestamp
     */
    function lastRebalance() external view returns (uint256);

    /**
     * @notice Gets staking contract address
     * @return address Current staking contract
     */
    function stakingContract() external view returns (address);

    /**
     * @notice Gets liquidity pool address
     * @return address Current liquidity pool
     */
    function liquidityPool() external view returns (address);

    /**
     * @notice Gets operations wallet address
     * @return address Current operations wallet
     */
    function operationsWallet() external view returns (address);

    /**
     * @notice Gets burn address
     * @return address Current burn address
     */
    function burnAddress() external view returns (address);

    /**
     * @notice Pauses treasury operations
     * @dev Only callable by operator role
     */
    function pause() external;

    /**
     * @notice Resumes treasury operations
     * @dev Only callable by operator role
     */
    function unpause() external;

    /**
     * @notice Emitted when revenue is distributed
     * @param stakingAmount Amount sent to staking rewards
     * @param liquidityAmount Amount added to liquidity
     * @param operationsAmount Amount sent to operations
     * @param burnAmount Amount burned
     */
    event RevenueDistributed(
        uint256 stakingAmount,
        uint256 liquidityAmount,
        uint256 operationsAmount,
        uint256 burnAmount
    );

    /**
     * @notice Emitted when liquidity is rebalanced
     * @param amount Amount of liquidity adjusted
     * @param added Whether liquidity was added (true) or removed (false)
     */
    event LiquidityRebalanced(uint256 amount, bool added);

    /**
     * @notice Emitted when protocol addresses are updated
     * @param stakingContract New staking contract address
     * @param liquidityPool New liquidity pool address
     * @param operationsWallet New operations wallet address
     */
    event AddressesUpdated(
        address stakingContract,
        address liquidityPool,
        address operationsWallet
    );

    // Constants
    function TARGET_LIQUIDITY_RATIO() external pure returns (uint256);
    function REBALANCING_THRESHOLD() external pure returns (uint256);
    function MAX_SLIPPAGE() external pure returns (uint256);
    function MIN_LIQUIDITY() external pure returns (uint256);
    function STAKING_SHARE() external pure returns (uint256);
    function LIQUIDITY_SHARE() external pure returns (uint256);
    function OPERATIONS_SHARE() external pure returns (uint256);
    function BURN_SHARE() external pure returns (uint256);
} 