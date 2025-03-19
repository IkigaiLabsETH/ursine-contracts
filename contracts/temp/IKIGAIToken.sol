// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@thirdweb-dev/contracts/base/ERC20Base.sol";
import "@thirdweb-dev/contracts/extension/PermissionsEnumerable.sol";

/**
 * @title IKIGAI Token
 * @notice ERC20 token for the IKIGAI Protocol with role-based permissions
 */
contract IKIGAIToken is ERC20Base, PermissionsEnumerable {
    // Role definitions
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    // Maximum supply of 1 billion tokens
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18;
    
    // Track total minted tokens to enforce max supply
    uint256 public totalMinted;

    constructor(
        address _defaultAdmin
    ) 
        ERC20Base(
            _defaultAdmin,
            "IKIGAI",
            "IKIGAI",
            0, // Initial supply is 0 for fair launch
            0  // No platform fees
        )
    {
        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _setupRole(MINTER_ROLE, _defaultAdmin);
        _setupRole(BURNER_ROLE, _defaultAdmin);
    }

    /**
     * @notice Mint new tokens to a recipient
     * @param _to The address to mint tokens to
     * @param _amount The amount of tokens to mint
     */
    function mintTo(address _to, uint256 _amount) 
        external 
        onlyRole(MINTER_ROLE) 
    {
        require(totalMinted + _amount <= MAX_SUPPLY, "Exceeds max supply");
        totalMinted += _amount;
        _mint(_to, _amount);
    }

    /**
     * @notice Burn tokens from a specific address
     * @param _from The address to burn tokens from
     * @param _amount The amount of tokens to burn
     */
    function burnFrom(address _from, uint256 _amount)
        external
        onlyRole(BURNER_ROLE)
    {
        _burn(_from, _amount);
    }
} 