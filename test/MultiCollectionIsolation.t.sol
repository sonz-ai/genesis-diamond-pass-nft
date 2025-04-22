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
    
    // Note: DiamondGenesisPass has fixed MINTER_SHARES (2000) and CREATOR_SHARES (8000)
    // These values are used during registration in the constructor
    uint256 constant EXPECTED_MINTER_SHARES = 2000; // 20% - hardcoded in DiamondGenesisPass
    uint256 constant EXPECTED_CREATOR_SHARES = 8000; // 80% - hardcoded in DiamondGenesisPass
    
    function setUp() public {
        // Deploy distributor and set up roles
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        
        // Deploy two different NFT collections
        // Note: DiamondGenesisPass constructor automatically registers the collection
        nft1 = new DiamondGenesisPass(address(distributor), royaltyFee1, creator1);
        nft2 = new DiamondGenesisPass(address(distributor), royaltyFee2, creator2);
        
        // No need to register again - already done in the constructor
        
        // Enable minting for both collections
        nft1.setPublicMintActive(true);
        nft2.setPublicMintActive(true);
        vm.stopPrank();
        
        // Fund accounts
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        // Fund creators for balance checks later
        vm.deal(creator1, 10 ether);
        vm.deal(creator2, 10 ether);
    }
    
    // Renamed test to reflect direct accrual
    function testCollectionIsolationWithDirectAccrual() public {
        // Mint tokens from both collections
        vm.startPrank(user1);
        nft1.mint{value: 0.1 ether}(user1); // Mint token 1 in collection 1
        vm.stopPrank();
        vm.startPrank(user2);
        nft2.mint{value: 0.1 ether}(user2); // Mint token 1 in collection 2
        vm.stopPrank();
        
        // Verify minting
        assertEq(nft1.ownerOf(1), user1);
        assertEq(nft2.ownerOf(1), user2);
        
        // Add funds to both collections' royalty pools
        uint256 pool1Amount = 1 ether;
        uint256 pool2Amount = 1.5 ether;
        vm.deal(admin, pool1Amount + pool2Amount); // Deal funds to admin to add
        vm.prank(admin);
        distributor.addCollectionRoyalties{value: pool1Amount}(address(nft1));
        vm.prank(admin);
        distributor.addCollectionRoyalties{value: pool2Amount}(address(nft2));
        
        // Verify royalties are tracked separately
        assertEq(distributor.getCollectionRoyalties(address(nft1)), pool1Amount);
        assertEq(distributor.getCollectionRoyalties(address(nft2)), pool2Amount);
        
        // Accrue claimable royalties for each creator in their respective collection
        uint256 claimAmount1 = 0.5 ether;
        uint256 claimAmount2 = 0.75 ether;
        
        address[] memory recipients1 = new address[](1); recipients1[0] = creator1;
        uint256[] memory amounts1 = new uint256[](1); amounts1[0] = claimAmount1;
        
        address[] memory recipients2 = new address[](1); recipients2[0] = creator2;
        uint256[] memory amounts2 = new uint256[](1); amounts2[0] = claimAmount2;
        
        vm.startPrank(service);
        distributor.updateAccruedRoyalties(address(nft1), recipients1, amounts1);
        distributor.updateAccruedRoyalties(address(nft2), recipients2, amounts2);
        vm.stopPrank();
        
        // Verify claimable amounts are set correctly for each collection
        assertEq(distributor.getClaimableRoyalties(address(nft1), creator1), claimAmount1);
        assertEq(distributor.getClaimableRoyalties(address(nft2), creator2), claimAmount2);
        assertEq(distributor.getClaimableRoyalties(address(nft1), creator2), 0, "Creator2 should have 0 claimable in NFT1");
        assertEq(distributor.getClaimableRoyalties(address(nft2), creator1), 0, "Creator1 should have 0 claimable in NFT2");
        
        // Creator1 claims from collection1
        uint256 c1BalanceBefore = creator1.balance;
        vm.prank(creator1);
        distributor.claimRoyalties(address(nft1), claimAmount1); // Use claimRoyalties
        assertApproxEqAbs(creator1.balance, c1BalanceBefore + claimAmount1, 1e15);
        
        // Verify balances after claim - only pool1 should change
        assertEq(distributor.getCollectionRoyalties(address(nft1)), pool1Amount - claimAmount1);
        assertEq(distributor.getCollectionRoyalties(address(nft2)), pool2Amount); // Pool 2 unchanged
        assertEq(distributor.getClaimableRoyalties(address(nft1), creator1), 0); // Claimable for creator1 is 0
        
        // Creator2 claims from collection2
        uint256 c2BalanceBefore = creator2.balance;
        vm.prank(creator2);
        distributor.claimRoyalties(address(nft2), claimAmount2); // Use claimRoyalties
        assertApproxEqAbs(creator2.balance, c2BalanceBefore + claimAmount2, 1e15);
        
        // Verify balances after second claim - only pool2 should change
        assertEq(distributor.getCollectionRoyalties(address(nft1)), pool1Amount - claimAmount1); // Pool 1 unchanged
        assertEq(distributor.getCollectionRoyalties(address(nft2)), pool2Amount - claimAmount2);
        assertEq(distributor.getClaimableRoyalties(address(nft2), creator2), 0); // Claimable for creator2 is 0
        
        // Verify collection configurations remain distinct
        (uint256 fee1, uint256 minterShares1Retrieved, uint256 creatorShares1Retrieved, address creatorAddr1) = 
            distributor.getCollectionConfig(address(nft1));
        (uint256 fee2, uint256 minterShares2Retrieved, uint256 creatorShares2Retrieved, address creatorAddr2) = 
            distributor.getCollectionConfig(address(nft2));
        
        assertEq(fee1, royaltyFee1);
        assertEq(fee2, royaltyFee2);
        assertEq(minterShares1Retrieved, EXPECTED_MINTER_SHARES); // Compare with hardcoded value from DiamondGenesisPass
        assertEq(minterShares2Retrieved, EXPECTED_MINTER_SHARES); // Compare with hardcoded value from DiamondGenesisPass
        assertEq(creatorShares1Retrieved, EXPECTED_CREATOR_SHARES); // Compare with hardcoded value from DiamondGenesisPass
        assertEq(creatorShares2Retrieved, EXPECTED_CREATOR_SHARES); // Compare with hardcoded value from DiamondGenesisPass
        assertEq(creatorAddr1, creator1);
        assertEq(creatorAddr2, creator2);
    }
}
