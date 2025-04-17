// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";
import "lib/murky/src/Merkle.sol";

struct ClaimData {
    address recipient;
    uint256 amount;
}

contract RoyaltyMerkleDistributionTest is Test {
    CentralizedRoyaltyDistributor public distributor;
    DiamondGenesisPass public nft;
    Merkle public merkle;
    
    address admin = address(0xA11CE);
    address service = address(0xBEEF);
    address creator = address(0xC0FFEE);
    
    // Multiple minters and collectors for more complex scenarios
    address[] minters;
    uint256[] amounts;
    bytes32[] hashes;
    
    function setUp() public {
        // Deploy distributor and NFT
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        nft = new DiamondGenesisPass(address(distributor), 750, creator);
        distributor.registerCollection(address(nft), 750, 2000, 8000, creator);
        nft.setPublicMintActive(true);
        vm.stopPrank();
        
        // Deploy Merkle library
        merkle = new Merkle();
        
        // Create test accounts
        uint256 numAccounts = 10;
        minters = new address[](numAccounts);
        for (uint256 i = 0; i < numAccounts; i++) {
            minters[i] = address(uint160(0x1000 + i));
            vm.deal(minters[i], 1 ether);
        }
    }
    
    // Helper function to calculate leaf hash
    function calculateLeaf(address recipient, uint256 amount) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(recipient, amount));
    }
    
    // Helper function to build a complete tree and proofs
    function buildMerkleTree(ClaimData[] memory claims) public view returns (bytes32 root, bytes32[][] memory proofs) {
        bytes32[] memory leaves = new bytes32[](claims.length);
        proofs = new bytes32[][](claims.length);
        
        // Create leaves
        for (uint256 i = 0; i < claims.length; i++) {
            leaves[i] = calculateLeaf(claims[i].recipient, claims[i].amount);
        }
        
        // Get root
        root = merkle.getRoot(leaves);
        
        // Generate proofs for each leaf
        for (uint256 i = 0; i < claims.length; i++) {
            proofs[i] = merkle.getProof(leaves, i);
        }
        
        return (root, proofs);
    }
    
    // Test 1: Complex Merkle tree with multiple recipients
    function testComplexMerkleTree() public {
        // Create 10 claim entries
        ClaimData[] memory claims = new ClaimData[](10);
        uint256 totalAmount = 0;
        
        for (uint256 i = 0; i < 10; i++) {
            claims[i] = ClaimData({
                recipient: minters[i],
                amount: 0.1 ether * (i + 1)
            });
            totalAmount += claims[i].amount;
        }
        
        // Fund distributor
        vm.deal(address(this), totalAmount);
        distributor.addCollectionRoyalties{value: totalAmount}(address(nft));
        
        // Build Merkle tree
        (bytes32 root, bytes32[][] memory proofs) = buildMerkleTree(claims);
        
        // Submit root
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), root, totalAmount);
        
        // Each recipient claims their amount
        for (uint256 i = 0; i < 10; i++) {
            uint256 balanceBefore = minters[i].balance;
            vm.prank(minters[i]);
            distributor.claimRoyaltiesMerkle(address(nft), minters[i], claims[i].amount, proofs[i]);
            uint256 balanceAfter = minters[i].balance;
            
            // Verify balance changed correctly
            assertEq(balanceAfter - balanceBefore, claims[i].amount);
        }
    }
    
    // Test 2: Verify proof integrity
    function testMerkleProofIntegrity() public {
        // Create claim data
        ClaimData[] memory claims = new ClaimData[](3);
        claims[0] = ClaimData({recipient: minters[0], amount: 0.5 ether});
        claims[1] = ClaimData({recipient: minters[1], amount: 0.3 ether});
        claims[2] = ClaimData({recipient: minters[2], amount: 0.2 ether});
        
        // Fund distributor
        vm.deal(address(this), 1 ether);
        distributor.addCollectionRoyalties{value: 1 ether}(address(nft));
        
        // Build Merkle tree
        (bytes32 root, bytes32[][] memory proofs) = buildMerkleTree(claims);
        
        // Submit root
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), root, 1 ether);
        
        // Verify correct proofs work
        vm.prank(minters[0]);
        distributor.claimRoyaltiesMerkle(address(nft), minters[0], claims[0].amount, proofs[0]);
        
        // Verify incorrect proof fails (using wrong amount)
        vm.prank(minters[1]);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__InvalidProof.selector);
        distributor.claimRoyaltiesMerkle(address(nft), minters[1], 0.4 ether, proofs[1]);
        
        // Verify incorrect proof fails (wrong recipient for proof)
        vm.prank(minters[1]);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__InvalidProof.selector);
        distributor.claimRoyaltiesMerkle(address(nft), minters[1], claims[1].amount, proofs[2]);
        
        // Verify proper claim works
        vm.prank(minters[1]);
        distributor.claimRoyaltiesMerkle(address(nft), minters[1], claims[1].amount, proofs[1]);
    }
    
    // Test 3: Fuzz testing with random Merkle trees
    function testFuzzedMerkleClaims(uint256 numClaims, uint256 seed) public {
        // Bound inputs to reasonable values
        numClaims = bound(numClaims, 2, 20);
        vm.assume(seed != 0);
        
        // Create random claim data
        ClaimData[] memory claims = new ClaimData[](numClaims);
        uint256 totalAmount = 0;
        
        for (uint256 i = 0; i < numClaims; i++) {
            // Generate deterministic but "random" values
            uint256 amount = (uint256(keccak256(abi.encodePacked(seed, i))) % 1 ether) + 0.01 ether;
            claims[i] = ClaimData({
                recipient: address(uint160(0x1000 + i)),
                amount: amount
            });
            totalAmount += amount;
            vm.deal(claims[i].recipient, 0.1 ether); // Give some initial balance
        }
        
        // Fund distributor
        vm.deal(address(this), totalAmount);
        distributor.addCollectionRoyalties{value: totalAmount}(address(nft));
        
        // Build Merkle tree
        (bytes32 root, bytes32[][] memory proofs) = buildMerkleTree(claims);
        
        // Submit root
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), root, totalAmount);
        
        // Each recipient claims their amount in random order
        uint256[] memory indices = new uint256[](numClaims);
        for (uint256 i = 0; i < numClaims; i++) {
            indices[i] = i;
        }
        
        // Fisher-Yates shuffle for random order
        for (uint256 i = 0; i < numClaims; i++) {
            uint256 j = i + (uint256(keccak256(abi.encodePacked(seed, "shuffle", i))) % (numClaims - i));
            (indices[i], indices[j]) = (indices[j], indices[i]);
        }
        
        // Claim in shuffled order
        for (uint256 i = 0; i < numClaims; i++) {
            uint256 idx = indices[i];
            address recipient = claims[idx].recipient;
            uint256 amount = claims[idx].amount;
            
            uint256 balanceBefore = recipient.balance;
            vm.prank(recipient);
            distributor.claimRoyaltiesMerkle(address(nft), recipient, amount, proofs[idx]);
            uint256 balanceAfter = recipient.balance;
            
            // Verify balance changed correctly
            assertEq(balanceAfter - balanceBefore, amount);
        }
        
        // Verify total claimed matches total submitted
        assertEq(distributor.totalClaimed(), totalAmount);
    }
    
    // Test 4: Sequential roots and claims
    function testSequentialRoots() public {
        // Create first batch of claims
        ClaimData[] memory claims1 = new ClaimData[](3);
        claims1[0] = ClaimData({recipient: minters[0], amount: 0.1 ether});
        claims1[1] = ClaimData({recipient: minters[1], amount: 0.2 ether});
        claims1[2] = ClaimData({recipient: minters[2], amount: 0.3 ether});
        
        // Create second batch of claims
        ClaimData[] memory claims2 = new ClaimData[](3);
        claims2[0] = ClaimData({recipient: minters[3], amount: 0.15 ether});
        claims2[1] = ClaimData({recipient: minters[4], amount: 0.25 ether});
        claims2[2] = ClaimData({recipient: minters[0], amount: 0.1 ether}); // Repeated recipient
        
        // Fund distributor
        vm.deal(address(this), 1.1 ether);
        distributor.addCollectionRoyalties{value: 1.1 ether}(address(nft));
        
        // Build first Merkle tree
        (bytes32 root1, bytes32[][] memory proofs1) = buildMerkleTree(claims1);
        
        // Submit first root
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), root1, 0.6 ether);
        
        // First recipient claims
        vm.prank(minters[0]);
        distributor.claimRoyaltiesMerkle(address(nft), minters[0], 0.1 ether, proofs1[0]);
        
        // Submit second root (overwriting first)
        (bytes32 root2, bytes32[][] memory proofs2) = buildMerkleTree(claims2);
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), root2, 0.5 ether);
        
        // Verify unclaimed amounts from first root are no longer claimable
        vm.prank(minters[1]);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__InvalidProof.selector);
        distributor.claimRoyaltiesMerkle(address(nft), minters[1], 0.2 ether, proofs1[1]);
        
        // Verify can claim from second root
        vm.prank(minters[3]);
        distributor.claimRoyaltiesMerkle(address(nft), minters[3], 0.15 ether, proofs2[0]);
        
        // Verify repeated recipient can claim from new root
        vm.prank(minters[0]);
        distributor.claimRoyaltiesMerkle(address(nft), minters[0], 0.1 ether, proofs2[2]);
    }
    
    // Test 5: Minter plus creator royalty split
    function testMinterCreatorSplit() public {
        // Create realistic scenario with minter and creator
        address minter = minters[0];
        
        // Mint token to minter
        vm.prank(minter);
        nft.mint{value: 0.1 ether}(minter);
        
        // Simulate royalty payment (7.5% of 1 ETH sale price)
        uint256 salePrice = 1 ether;
        uint256 royaltyAmount = (salePrice * 750) / 10000; // 0.075 ETH
        
        // Calculate shares
        uint256 minterShare = (royaltyAmount * 2000) / 10000; // 20% = 0.015 ETH
        uint256 creatorShare = (royaltyAmount * 8000) / 10000; // 80% = 0.06 ETH
        
        // Fund distributor
        vm.deal(address(this), royaltyAmount);
        distributor.addCollectionRoyalties{value: royaltyAmount}(address(nft));
        
        // Create claim data for both recipients
        ClaimData[] memory claims = new ClaimData[](2);
        claims[0] = ClaimData({recipient: minter, amount: minterShare});
        claims[1] = ClaimData({recipient: creator, amount: creatorShare});
        
        // Build Merkle tree
        (bytes32 root, bytes32[][] memory proofs) = buildMerkleTree(claims);
        
        // Submit Merkle root
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), root, royaltyAmount);
        
        // Both claim their shares
        vm.prank(minter);
        distributor.claimRoyaltiesMerkle(address(nft), minter, minterShare, proofs[0]);
        
        vm.prank(creator);
        distributor.claimRoyaltiesMerkle(address(nft), creator, creatorShare, proofs[1]);
        
        // Verify analytics
        assertEq(distributor.totalClaimed(), royaltyAmount);
    }
    
    // Test 6: Validate chain of operations from batch update to claims
    function testBatchUpdateToClaimsFlow() public {
        // Set up full flow
        // 1. Mint tokens
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(minters[i]);
            nft.mint{value: 0.1 ether}(minters[i]);
        }
        
        // 2. Record sales data via batch update
        uint256[] memory tokenIds = new uint256[](3);
        address[] memory originalMinters = new address[](3);
        uint256[] memory salePrices = new uint256[](3);
        uint256[] memory timestamps = new uint256[](3);
        bytes32[] memory txHashes = new bytes32[](3);
        
        for (uint256 i = 0; i < 3; i++) {
            tokenIds[i] = i + 1;
            originalMinters[i] = minters[i];
            salePrices[i] = 1 ether;
            timestamps[i] = block.timestamp;
            txHashes[i] = keccak256(abi.encodePacked("tx", i));
        }
        
        // Batch update
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            originalMinters,
            salePrices,
            timestamps,
            txHashes
        );
        
        // 3. Add royalties to pool (simulating marketplace payments)
        uint256 totalRoyalty = 0;
        for (uint256 i = 0; i < 3; i++) {
            totalRoyalty += (salePrices[i] * 750) / 10000;
        }
        
        vm.deal(address(this), totalRoyalty);
        distributor.addCollectionRoyalties{value: totalRoyalty}(address(nft));
        
        // 4. Create claim data based on 20/80 split
        ClaimData[] memory claims = new ClaimData[](4); // 3 minters + 1 creator
        uint256 runningTotal = 0;
        
        for (uint256 i = 0; i < 3; i++) {
            uint256 saleRoyalty = (salePrices[i] * 750) / 10000;
            uint256 minterAmount = (saleRoyalty * 2000) / 10000;
            claims[i] = ClaimData({
                recipient: originalMinters[i],
                amount: minterAmount
            });
            runningTotal += minterAmount;
        }
        
        // Creator gets the remainder
        claims[3] = ClaimData({
            recipient: creator,
            amount: totalRoyalty - runningTotal
        });
        
        // 5. Build and submit Merkle tree
        (bytes32 root, bytes32[][] memory proofs) = buildMerkleTree(claims);
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), root, totalRoyalty);
        
        // 6. All claim their shares
        for (uint256 i = 0; i < 4; i++) {
            vm.prank(claims[i].recipient);
            distributor.claimRoyaltiesMerkle(address(nft), claims[i].recipient, claims[i].amount, proofs[i]);
        }
        
        // 7. Verify all royalties claimed
        assertEq(distributor.totalAccrued(), totalRoyalty);
        assertEq(distributor.totalClaimed(), totalRoyalty);
        assertEq(distributor.getCollectionRoyalties(address(nft)), 0);
    }
} 