// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "src/DiamondGenesisPass.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";

contract AutoTokenHolderUpdateTest is Test {
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
        
        // Mint a token to the minter
        pass.mintOwner(minter);
        
        // Disable the transfer validator by setting it to address(0)
        pass.setTransferValidator(address(0));
    }

    function testAutoTokenHolderUpdate() public {
        // Verify initial token holder
        (
            ,               
            address initialHolder,
            ,               
            ,               
            ,               
        ) = distributor.getTokenRoyaltyData(address(pass), 1);
        console.log("Initial token holder:", initialHolder);
        assertEq(initialHolder, minter);
        
        // Verify NFT owner
        address nftOwner = pass.ownerOf(1);
        console.log("Initial NFT owner:", nftOwner);
        assertEq(nftOwner, minter);
        
        // Perform the transfer
        vm.prank(minter);
        pass.transferFrom(minter, buyer, 1);
        
        // Verify NFT owner changed
        address newNftOwner = pass.ownerOf(1);
        console.log("New NFT owner after transfer:", newNftOwner);
        assertEq(newNftOwner, buyer);
        
        // Verify token holder was automatically updated
        (
            ,               
            address updatedHolder,
            ,               
            ,               
            ,               
        ) = distributor.getTokenRoyaltyData(address(pass), 1);
        console.log("Updated token holder after transfer:", updatedHolder);
        assertEq(updatedHolder, buyer);
    }
} 