// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./GenesisNFTLogic.sol";

/**
 * @title GenesisNFTDeployer
 * @notice Helper contract for deploying and initializing GenesisNFT
 * @dev Provides functions to encode initialization data for the proxy
 */
contract GenesisNFTDeployer {
    /**
     * @notice Encodes initialization data for the proxy
     * @param _defaultAdmin Default admin address
     * @param _name Token name
     * @param _symbol Token symbol
     * @param _royaltyRecipient Royalty recipient address
     * @param _royaltyBps Royalty basis points
     * @param _beraToken BERA token address
     * @param _ikigaiToken IKIGAI token address
     * @param _treasuryAddress Treasury address
     * @param _buybackEngine Buyback engine address
     * @param _beraHolderPrice Price for BERA holders
     * @param _whitelistPrice Price for whitelisted users
     * @param _publicPrice Public sale price
     * @return Encoded initialization data
     */
    function getInitializationData(
        address _defaultAdmin,
        string memory _name,
        string memory _symbol,
        address _royaltyRecipient,
        uint128 _royaltyBps,
        address _beraToken,
        address _ikigaiToken,
        address _treasuryAddress,
        address _buybackEngine,
        uint256 _beraHolderPrice,
        uint256 _whitelistPrice,
        uint256 _publicPrice
    ) external pure returns (bytes memory) {
        return abi.encodeWithSelector(
            GenesisNFTLogic.initialize.selector,
            _defaultAdmin,
            _name,
            _symbol,
            _royaltyRecipient,
            _royaltyBps,
            _beraToken,
            _ikigaiToken,
            _treasuryAddress,
            _buybackEngine,
            _beraHolderPrice,
            _whitelistPrice,
            _publicPrice
        );
    }
} 