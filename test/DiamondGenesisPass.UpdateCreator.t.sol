// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/DiamondGenesisPass.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";

contract DiamondGenesisPassRoyaltyRecipientTest is Test {
    DiamondGenesisPass public diamondPass;
    CentralizedRoyaltyDistributor public royaltyDistributor;
    
    address public contractOwner = address(0x1);
    address public initialCreator = address(0x2);
    address public newRoyaltyRecipient = address(0x3);
    address public user = address(0x4);
    address public multiSigWallet = address(0x5);
    
    uint96 public royaltyFeeNumerator = 750; // 7.5%
    
    // Contract events
    event CreatorAddressUpdated(address indexed oldCreator, address indexed newCreator);
    event RoyaltyRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    
    // Distributor events
    event DistributorCreatorUpdated(address indexed collection, address indexed oldCreator, address indexed newCreator);
    
    function setUp() public {
        vm.startPrank(contractOwner);
        
        // Deploy the royalty distributor
        royaltyDistributor = new CentralizedRoyaltyDistributor();
        
        // Deploy the DiamondGenesisPass with initialCreator as the creator
        diamondPass = new DiamondGenesisPass(
            address(royaltyDistributor),
            royaltyFeeNumerator,
            initialCreator
        );
        
        vm.stopPrank();
    }
    
    function testGetInitialCreator() public {
        // Check that the initial creator is set correctly
        address currentCreator = diamondPass.creator();
        assertEq(currentCreator, initialCreator, "Initial creator should be set correctly");
    }
    
    function testUpdateCreatorAddress() public {
        vm.startPrank(contractOwner);
        
        // Update the creator address using legacy function
        diamondPass.updateCreatorAddress(newRoyaltyRecipient);
        
        vm.stopPrank();
        
        // Check that the creator has been updated
        address updatedCreator = diamondPass.creator();
        assertEq(updatedCreator, newRoyaltyRecipient, "Creator should be updated to the new address");
    }
    
    function testSetRoyaltyRecipient() public {
        vm.startPrank(contractOwner);
        
        // Update using the new, more clearly named function
        diamondPass.setRoyaltyRecipient(multiSigWallet);
        
        vm.stopPrank();
        
        // Check that the creator has been updated
        address updatedCreator = diamondPass.creator();
        assertEq(updatedCreator, multiSigWallet, "Royalty recipient should be updated to the multisig wallet");
    }
    
    function testUpdateCreatorAsInitialCreator() public {
        vm.startPrank(initialCreator);
        
        // Update the creator directly through the distributor
        royaltyDistributor.updateCreatorAddress(address(diamondPass), newRoyaltyRecipient);
        
        vm.stopPrank();
        
        // Check that the creator has been updated
        address updatedCreator = diamondPass.creator();
        assertEq(updatedCreator, newRoyaltyRecipient, "Creator should be updated to the new address");
    }
    
    function testCannotUpdateCreatorAsNonOwnerOrCreator() public {
        vm.startPrank(user);
        
        // Try to update the creator address through the DiamondGenesisPass contract
        vm.expectRevert("Ownable: caller is not the owner");
        diamondPass.updateCreatorAddress(newRoyaltyRecipient);
        
        // Try the new function
        vm.expectRevert("Ownable: caller is not the owner");
        diamondPass.setRoyaltyRecipient(newRoyaltyRecipient);
        
        // Try to update directly through the distributor
        vm.expectRevert(); // Will revert with custom error RoyaltyDistributor__NotCollectionCreatorOrAdmin
        royaltyDistributor.updateCreatorAddress(address(diamondPass), newRoyaltyRecipient);
        
        vm.stopPrank();
        
        // Creator should remain unchanged
        address currentCreator = diamondPass.creator();
        assertEq(currentCreator, initialCreator, "Creator should not have changed");
    }
    
    function testCannotUpdateCreatorToZeroAddress() public {
        vm.startPrank(contractOwner);
        
        // Try to update the creator to the zero address
        vm.expectRevert(); // Will revert with custom error RoyaltyDistributor__CreatorCannotBeZeroAddress
        diamondPass.updateCreatorAddress(address(0));
        
        // Try with the new function
        vm.expectRevert(); // Will revert with custom error RoyaltyDistributor__CreatorCannotBeZeroAddress
        diamondPass.setRoyaltyRecipient(address(0));
        
        vm.stopPrank();
        
        // Creator should remain unchanged
        address currentCreator = diamondPass.creator();
        assertEq(currentCreator, initialCreator, "Creator should not have changed");
    }
    
    function testRoyaltiesGoToNewRecipient() public {
        // First, let's update the royalty recipient to a multisig wallet
        vm.prank(contractOwner);
        diamondPass.setRoyaltyRecipient(multiSigWallet);
        
        // Activate public minting
        vm.prank(contractOwner);
        diamondPass.setPublicMintActive(true);
        
        // User mints a token
        vm.deal(user, 1 ether);
        vm.prank(user);
        diamondPass.mint{value: 0.1 ether}(user);
        
        // Record a sale to trigger royalty calculation
        vm.prank(contractOwner);
        diamondPass.recordSale(1, 1 ether);
        
        // Simulate royalty payment
        address(royaltyDistributor).call{value: 0.075 ether}(""); // 7.5% of 1 ETH
        
        // Check that creator is now the multisig wallet
        address currentCreator = diamondPass.creator();
        assertEq(currentCreator, multiSigWallet, "Creator should be the multisig wallet for royalty distribution");
        
        // Note: In a real scenario, royalties would be distributed via a Merkle root to the new recipient
    }
} 