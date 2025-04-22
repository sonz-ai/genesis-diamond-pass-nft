// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";

contract MultiCollectionIsolationTest is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass nft1;
    DiamondGenesisPass nft2;
    
    address admin = address(0xA11CE);
    address service = address(0xBEEF);
    address creator1 = address(0xC0FFEE);
    address creator2 = address(0xDECAF);
    address user1 = address(0x1);
    address user2 = address(0x2);
    
    uint96 royaltyFee1 = 750; // 7.5%
    uint96 royaltyFee2 = 500; // 5.0%
    
    uint256 minterShares1 = 2000; // 20%
    uint256 creatorShares1 = 8000; // 80% 
    uint256 minterShares2 = 3000; // 30%
    uint256 creatorShares2 = 7000; // 70%
    
    function setUp() public {
        // Deploy distributor and set up roles
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        
        // Deploy two different NFT collections
        nft1 = new DiamondGenesisPass(address(distributor), royaltyFee1, creator1);
        nft2 = new DiamondGenesisPass(address(distributor), royaltyFee2, creator2);
        
        // Register both collections with their specific sharing configurations
        if (!distributor.isCollectionRegistered(address(nft1))) {
            distributor.registerCollection(address(nft1), royaltyFee1, minterShares1, creatorShares1, creator1);
        }
        
        if (!distributor.isCollectionRegistered(address(nft2))) {
            distributor.registerCollection(address(nft2), royaltyFee2, minterShares2, creatorShares2, creator2);
        }
        
        // Enable minting for both collections
        nft1.setPublicMintActive(true);
        nft2.setPublicMintActive(true);
        vm.stopPrank();
        
        // Fund accounts
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
    }
    
    function testCollectionIsolation() public {
        // Mint tokens from both collections
        vm.startPrank(user1);
        nft1.mint{value: 0.1 ether}(user1);
        nft2.mint{value: 0.1 ether}(user1);
        vm.stopPrank();
        
        // Verify minting
        assertEq(nft1.ownerOf(1), user1);
        assertEq(nft2.ownerOf(1), user1);
        
        // Add royalties to both collections
        vm.deal(address(this), 2 ether);
        distributor.addCollectionRoyalties{value: 1 ether}(address(nft1));
        distributor.addCollectionRoyalties{value: 1 ether}(address(nft2));
        
        // Verify royalties are tracked separately
        assertEq(distributor.getCollectionRoyalties(address(nft1)), 1 ether);
        assertEq(distributor.getCollectionRoyalties(address(nft2)), 1 ether);
        
        // Create Merkle roots for each collection
        bytes32 root1 = keccak256(abi.encodePacked(address(creator1), uint256(0.5 ether)));
        bytes32 root2 = keccak256(abi.encodePacked(address(creator2), uint256(0.75 ether)));
        
        // Submit roots
        vm.startPrank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft1), root1, 0.5 ether);
        distributor.submitRoyaltyMerkleRoot(address(nft2), root2, 0.75 ether);
        vm.stopPrank();
        
        // Verify roots are set correctly for each collection
        assertEq(distributor.getActiveMerkleRoot(address(nft1)), root1);
        assertEq(distributor.getActiveMerkleRoot(address(nft2)), root2);
        
        // Creator1 claims from collection1
        vm.prank(creator1);
        distributor.claimRoyaltiesMerkle(address(nft1), creator1, 0.5 ether, new bytes32[](0));
        
        // Verify balances after claim
        assertEq(distributor.getCollectionRoyalties(address(nft1)), 0.5 ether);
        assertEq(distributor.getCollectionRoyalties(address(nft2)), 1 ether);
        
        // Creator2 claims from collection2
        vm.prank(creator2);
        distributor.claimRoyaltiesMerkle(address(nft2), creator2, 0.75 ether, new bytes32[](0));
        
        // Verify balances after second claim
        assertEq(distributor.getCollectionRoyalties(address(nft1)), 0.5 ether);
        assertEq(distributor.getCollectionRoyalties(address(nft2)), 0.25 ether);
        
        // Verify collection configurations remain distinct
        (uint256 fee1, uint256 minterShares1Retrieved, uint256 creatorShares1Retrieved, address creatorAddr1) = 
            distributor.getCollectionConfig(address(nft1));
        (uint256 fee2, uint256 minterShares2Retrieved, uint256 creatorShares2Retrieved, address creatorAddr2) = 
            distributor.getCollectionConfig(address(nft2));
        
        assertEq(fee1, royaltyFee1);
        assertEq(fee2, royaltyFee2);
        assertEq(minterShares1Retrieved, minterShares1);
        assertEq(minterShares2Retrieved, minterShares2);
        assertEq(creatorShares1Retrieved, creatorShares1);
        assertEq(creatorShares2Retrieved, creatorShares2);
        assertEq(creatorAddr1, creator1);
        assertEq(creatorAddr2, creator2);
    }
}
