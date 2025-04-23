// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Mock ConfirmedOwner
 * @notice A simple mock implementation of Chainlink's ConfirmedOwner
 */
abstract contract ConfirmedOwner {
    address private s_owner;
    
    event OwnershipTransferred(address indexed from, address indexed to);
    
    error NotOwner();
    
    constructor(address owner) {
        s_owner = owner;
        emit OwnershipTransferred(address(0), owner);
    }
    
    modifier onlyOwner() {
        if (msg.sender != s_owner) revert NotOwner();
        _;
    }
    
    function owner() public view returns (address) {
        return s_owner;
    }
    
    function transferOwnership(address to) public onlyOwner {
        if (to == address(0)) revert NotOwner();
        address oldOwner = s_owner;
        s_owner = to;
        emit OwnershipTransferred(oldOwner, to);
    }
} 