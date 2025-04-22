// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "src/DiamondGenesisPass.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";

contract SimpleTransferTest is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass pass;

    address creator = address(0xC0FFEE);
    address minter = address(0xBEEF);
    address buyer = address(0xD00D);

    function setUp() public {
        vm.deal(minter, 1 ether);
        vm.deal(buyer, 1 ether);

        // Deploy contracts
        distributor = new CentralizedRoyaltyDistributor();
        pass = new DiamondGenesisPass(address(distributor), 750, creator);
        
        // Grant SERVICE_ACCOUNT_ROLE to this test contract to allow updating owner data
        bytes32 SERVICE_ACCOUNT_ROLE = keccak256("SERVICE_ACCOUNT_ROLE");
        distributor.grantRole(SERVICE_ACCOUNT_ROLE, address(this));
        
        // Mint a token to the minter
        pass.mintOwner(minter);
    }

    function testManualOwnerUpdate() public {
        // First verify the initial state
        address initialOwner = pass.ownerOf(1);
        console.log("Initial owner in NFT:", initialOwner);
        assertEq(initialOwner, minter);
        
        // Get the current token holder from the distributor
        (
            ,               
            address tokenHolder,
            ,               
            ,               
            ,               
            
        ) = distributor.getTokenRoyaltyData(address(pass), 1);
        console.log("Initial token holder in distributor:", tokenHolder);
        assertEq(tokenHolder, minter);
        
        // Simulate a transfer by directly updating the token holder
        console.log("Manually updating the token holder in distributor");
        distributor.updateTokenHolder(address(pass), 1, buyer);
        
        // Verify the update was successful
        (
            ,               
            address updatedHolder,
            ,               
            ,               
            ,               
            
        ) = distributor.getTokenRoyaltyData(address(pass), 1);
        console.log("Updated token holder in distributor:", updatedHolder);
        assertEq(updatedHolder, buyer);
    }
} 