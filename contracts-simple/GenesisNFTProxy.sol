// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title GenesisNFTProxy
 * @notice Proxy contract for GenesisNFT that delegates calls to implementation
 * @dev Uses ERC1967Proxy to establish a proxy with UUPS upgradeability
 */
contract GenesisNFTProxy is ERC1967Proxy {
    /**
     * @notice Constructor
     * @param _logic Address of the implementation contract
     * @param _data Initialization data to pass to the implementation
     */
    constructor(address _logic, bytes memory _data) ERC1967Proxy(_logic, _data) {
        // Constructor just calls the parent contract
    }
} 