// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";

/**
 * @title AnalyticsDoubleCountingFix
 * @notice Test to verify the fix for double-counting in analytics
 * @dev This test specifically checks that royalties are not double-counted
 *      between batchUpdateRoyaltyData and submitRoyaltyMerkleRoot
 */
contract AnalyticsDoubleCountingFix is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass nft;
    address admin = address(0x1);
    address service = address(0x2);
    address creator = address(0x3);
    address minter = address(0x4);
    address buyer = address(0x5);

    uint256 constant SALE_PRICE = 1 ether;
    uint256 constant ROYALTY_FEE = 1000; // 10% in basis points
    bytes32 constant TRANSACTION_HASH = keccak256("transaction1");

    function setUp() public {
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        nft = new DiamondGenesisPass(address(distributor), ROYALTY_FEE, creator);
        nft.setPublicMintActive(true);
        vm.stopPrank();

        // Mint a token
        vm.deal(minter, 1 ether);
        vm.prank(minter);
        nft.mint{value: 0.1 ether}(minter);
    }

    function testNoDoubleCountingInAnalytics() public {
        // 1. First, record a sale and update royalty data
        address[] memory collections = new address[](1);
        collections[0] = address(nft);
        
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        
        uint256[] memory salePrices = new uint256[](1);
        salePrices[0] = SALE_PRICE;
        
        bytes32[] memory txHashes = new bytes32[](1);
        txHashes[0] = TRANSACTION_HASH;

        // Record the sale via batch update
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            collections,
            tokenIds,
            salePrices,
            txHashes
        );

        // Check initial accrued royalty
        uint256 expectedRoyalty = (SALE_PRICE * ROYALTY_FEE) / 10000;
        assertEq(distributor.totalAccruedRoyalty(), expectedRoyalty, "Accrued royalty should match expected amount after batch update");

        // 2. Now simulate receiving the actual royalty payment
        vm.deal(address(this), expectedRoyalty);
        (bool success, ) = address(distributor).call{value: expectedRoyalty}("");
        require(success, "Transfer failed");

        // 3. Create and submit a Merkle root
        bytes32 merkleRoot = keccak256("testMerkleRoot");
        
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), merkleRoot, expectedRoyalty);

        // 4. Verify that the totalAccruedRoyalty hasn't been double-counted
        // If double-counting is fixed, the total should still be expectedRoyalty
        // If double-counting occurs, it would be 2 * expectedRoyalty
        assertEq(distributor.totalAccruedRoyalty(), expectedRoyalty, "Accrued royalty should not be double-counted");
    }

    function testClaimUpdatesAnalytics() public {
        // 1. Setup: Record sale, receive royalty, and submit Merkle root
        address[] memory collections = new address[](1);
        collections[0] = address(nft);
        
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        
        uint256[] memory salePrices = new uint256[](1);
        salePrices[0] = SALE_PRICE;
        
        bytes32[] memory txHashes = new bytes32[](1);
        txHashes[0] = TRANSACTION_HASH;

        // Record the sale
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(collections, tokenIds, salePrices, txHashes);

        // Simulate royalty payment
        uint256 royaltyAmount = (SALE_PRICE * ROYALTY_FEE) / 10000;
        vm.deal(address(this), royaltyAmount);
        (bool success, ) = address(distributor).call{value: royaltyAmount}("");
        require(success, "Transfer failed");

        // Create a simple Merkle tree with just the minter claim
        bytes32 merkleRoot = keccak256(abi.encodePacked(minter, royaltyAmount));
        
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), merkleRoot, royaltyAmount);

        // Initial claimed should be 0
        assertEq(distributor.totalClaimedRoyalty(), 0, "Initial claimed royalty should be 0");

        // 2. Create a mock proof for the minter
        bytes32[] memory proof = new bytes32[](0); // Empty proof for this simple test
        
        // 3. Claim royalties
        vm.prank(minter);
        distributor.claimRoyaltiesMerkle(address(nft), minter, royaltyAmount, proof);

        // 4. Verify claimed analytics updated correctly
        assertEq(distributor.totalClaimedRoyalty(), royaltyAmount, "Claimed royalty should be updated after claim");
    }

    // Test role-based access for analytics functions
    function testAnalyticsViewFunctionsAccessibility() public {
        // Anyone should be able to view analytics
        uint256 accrued = distributor.totalAccrued();
        uint256 claimed = distributor.totalClaimed();
        
        // These should match the public state variables
        assertEq(accrued, distributor.totalAccruedRoyalty());
        assertEq(claimed, distributor.totalClaimedRoyalty());
        
        // Test as different users
        vm.prank(minter);
        accrued = distributor.totalAccrued();
        
        vm.prank(buyer);
        claimed = distributor.totalClaimed();
        
        // Values should be consistent regardless of caller
        assertEq(accrued, distributor.totalAccruedRoyalty());
        assertEq(claimed, distributor.totalClaimedRoyalty());
    }
}
