// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IIkigaiV2Factory
 * @notice Factory interface for deploying and managing the Ikigai V2 protocol system
 * @dev Handles deployment and initialization of all core protocol contracts
 */
interface IIkigaiV2Factory {
    /**
     * @notice Deploys a complete set of Ikigai V2 protocol contracts
     * @dev Sets up all necessary roles and permissions between contracts
     * @param name Token name for the Ikigai V2 token
     * @param symbol Token symbol for the Ikigai V2 token
     * @param stablecoin Address of the stablecoin used for protocol operations
     * @param operationsWallet Address that receives operations share of revenue
     * @param liquidityPool Address of the protocol's liquidity pool
     */
    function deployFullSystem(
        string memory name,
        string memory symbol,
        address stablecoin,
        address operationsWallet,
        address liquidityPool
    ) external;

    /**
     * @notice Returns the address of the deployed Ikigai V2 token
     * @return address The Ikigai V2 token contract address
     */
    function ikigaiToken() external view returns (address);

    /**
     * @notice Returns the address of the deployed staking contract
     * @return address The StakingV2 contract address
     */
    function stakingContract() external view returns (address);

    /**
     * @notice Returns the address of the deployed treasury contract
     * @return address The TreasuryV2 contract address
     */
    function treasuryContract() external view returns (address);

    /**
     * @notice Returns the address of the deployed rewards contract
     * @return address The RewardsV2 contract address
     */
    function rewardsContract() external view returns (address);

    /**
     * @notice Recovers any ERC20 tokens accidentally sent to the factory
     * @dev Only callable by factory owner
     * @param _token Address of the token to recover
     */
    function recoverTokens(address _token) external;

    /**
     * @notice Emitted when a complete system deployment is successful
     * @param ikigaiToken Address of the deployed Ikigai V2 token
     * @param stakingContract Address of the deployed staking contract
     * @param treasuryContract Address of the deployed treasury contract
     * @param rewardsContract Address of the deployed rewards contract
     */
    event SystemDeployed(
        address ikigaiToken,
        address stakingContract,
        address treasuryContract,
        address rewardsContract
    );
} 