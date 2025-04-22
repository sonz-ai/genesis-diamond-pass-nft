// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "src/DiamondGenesisPass.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";

contract TransferSyncTest is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass            pass;

    address creator = address(0xC0FFEE);
    address owner   = address(0xDEAD);
    address minter  = address(0xBEEF);
    address buyer   = address(0xD00D);

    function setUp() public {
        vm.deal(owner, 10 ether);
        vm.deal(minter, 10 ether);
        vm.deal(buyer,  10 ether);

        distributor = new CentralizedRoyaltyDistributor();
        pass        = new DiamondGenesisPass(address(distributor), 750, creator);
        
        // Transfer ownership
        pass.transferOwnership(owner);
        
        // Grant SERVICE_ACCOUNT_ROLE to the DiamondGenesisPass contract
        bytes32 SERVICE_ACCOUNT_ROLE = keccak256("SERVICE_ACCOUNT_ROLE");
        distributor.grantRole(SERVICE_ACCOUNT_ROLE, address(pass));
        
        // Also grant the role to this test contract to allow manual updates
        distributor.grantRole(SERVICE_ACCOUNT_ROLE, address(this));

        // Owner mints a token to minter
        vm.prank(owner);
        pass.mintOwner(minter);
    }

    function testTokenHolderUpdatesManually() public {
        // Check initial state
        address tokenOwner = pass.ownerOf(1);
        address tokenMinter = pass.getMinterOf(1);
        
        console.log("Current token owner in NFT contract:", tokenOwner);
        console.log("Current token minter:", tokenMinter);
        
        assertEq(tokenOwner, minter);
        assertEq(tokenMinter, minter);
        
        // Manually update the token holder in the distributor
        console.log("Manually updating token holder in distributor");
        distributor.updateTokenHolder(address(pass), 1, buyer);
        
        // Check that the update was successful
        (
            ,               
            address updatedHolder,
            ,               
            ,               
            ,               
        ) = distributor.getTokenRoyaltyData(address(pass), 1);
        
        console.log("Updated token holder in distributor:", updatedHolder);
        console.log("Expected token holder in distributor:", buyer);
        
        // Verify the update worked
        assertEq(updatedHolder, buyer);
        
        // Verify owner and minter didn't change in the NFT contract
        assertEq(pass.ownerOf(1), minter, "Token owner should not have changed");
        assertEq(pass.getMinterOf(1), minter, "Token minter should not have changed");
    }
    
    function testOwnerAssignMinterStatus() public {
        // Verify the initial state
        address initialMinter = pass.getMinterOf(1);
        address initialOwner = pass.ownerOf(1);
        
        assertEq(initialMinter, minter, "Initial minter should be minter");
        assertEq(initialOwner, minter, "Initial owner should be minter");
        
        // Let the owner assign a new minter
        vm.prank(owner);
        pass.setMinterStatus(1, buyer);
        
        // Verify minter changed but ownership didn't
        address newMinter = pass.getMinterOf(1);
        address newOwner = pass.ownerOf(1);
        
        assertEq(newMinter, buyer, "Minter should be updated to buyer");
        assertEq(newOwner, minter, "Owner should still be the original minter");
    }
}