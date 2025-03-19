// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title SimpleContract
 * @notice A simple contract to test compilation
 */
contract SimpleContract {
    string public greeting;
    
    constructor(string memory _greeting) {
        greeting = _greeting;
    }
    
    function setGreeting(string memory _greeting) external {
        greeting = _greeting;
    }
    
    function getGreeting() external view returns (string memory) {
        return greeting;
    }
} 