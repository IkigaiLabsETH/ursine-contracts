// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title IV2
 * @notice Interface for the Ikigai V2 token contract
 * @dev Extends ERC20 functionality with governance features and controlled minting
 */
interface IV2 is IERC20, IAccessControl {
    /**
     * @notice Mints new tokens
     * @dev Only callable by addresses with MINTER_ROLE
     * @param to Address to receive the minted tokens
     * @param amount Amount of tokens to mint
     * @return bool true if the operation was successful
     */
    function mint(address to, uint256 amount) external returns (bool);

    /**
     * @notice Burns tokens from caller's address
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) external;

    /**
     * @notice Burns tokens from a specified account
     * @dev Requires approval from the account
     * @param account Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burnFrom(address account, uint256 amount) external;

    /**
     * @notice Returns the address that receives primary sale proceeds
     * @return address The primary sale recipient address
     */
    function primarySaleRecipient() external view returns (address);

    /**
     * @notice Updates the primary sale recipient address
     * @dev Only callable by addresses with DEFAULT_ADMIN_ROLE
     * @param _saleRecipient New primary sale recipient address
     */
    function setPrimarySaleRecipient(address _saleRecipient) external;

    /**
     * @notice Gets the current votes balance for an account
     * @param account Address to get votes for
     * @return uint256 The number of current votes for `account`
     */
    function getVotes(address account) external view returns (uint256);

    /**
     * @notice Gets the prior votes balance for an account at a specific block number
     * @dev Block number must be in the past
     * @param account Address to get votes for
     * @param blockNumber Block number to get votes at
     * @return uint256 The number of votes the account had at the given block
     */
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256);

    /**
     * @notice Retrieves the total supply at a past block number
     * @param blockNumber Block number to get total supply at
     * @return uint256 The total supply at the given block
     */
    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256);

    /**
     * @notice Gets the delegate for an account
     * @param account Address to get delegate for
     * @return address The delegate address for the given account
     */
    function delegates(address account) external view returns (address);

    /**
     * @notice Delegates votes from sender to delegatee
     * @param delegatee Address to delegate votes to
     */
    function delegate(address delegatee) external;

    /**
     * @notice Delegates votes from signer to delegatee using signature
     * @param delegatee Address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @notice Emitted when primary sale recipient is updated
     * @param recipient The new primary sale recipient address
     */
    event PrimarySaleRecipientUpdated(address indexed recipient);

    /**
     * @notice Emitted when an account changes their delegate
     * @param delegator The account that is delegating votes
     * @param fromDelegate The previous delegate
     * @param toDelegate The new delegate
     */
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /**
     * @notice Emitted when a delegate account's vote balance changes
     * @param delegate The delegate account whose votes are changing
     * @param previousBalance The previous balance of votes
     * @param newBalance The new balance of votes
     */
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);
} 