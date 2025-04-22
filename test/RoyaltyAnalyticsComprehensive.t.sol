// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/DiamondGenesisPass.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";

contract RoyaltyAnalyticsComprehensiveTest is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass nft;
    
    address admin = address(0xA11CE);
    address service = address(0xBEEF);
    address creator = address(0xC0FFEE);
    address[] minters;
    
    uint256 constant NUM_MINTERS = 5;
    uint96 constant ROYALTY_FEE = 750; // 7.5%
    uint256 constant MINTER_SHARES = 2000; // 20%
    uint256 constant CREATOR_SHARES = 8000; // 80%
    
    event RoyaltyAttributed(
        address indexed collection,
        uint256 indexed tokenId,
        address indexed minter,
        uint256 salePrice,
        uint256 minterShareAttributed,
        uint256 creatorShareAttributed,
        bytes32 transactionHash 
    );
    
    function setUp() public {
        // Set up minters array
        for (uint256 i = 0; i < NUM_MINTERS; i++) {
            minters.push(address(uint160(0x1000 + i)));
            vm.deal(minters[i], 10 ether);
        }
        
        // Set up contracts
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        
        nft = new DiamondGenesisPass(address(distributor), ROYALTY_FEE, creator);
        
        // Explicitly register if not already registered
        if (!distributor.isCollectionRegistered(address(nft))) {
            distributor.registerCollection(
                address(nft),
                ROYALTY_FEE,
                MINTER_SHARES,
                CREATOR_SHARES,
                creator
            );
        }
        
        // Enable public minting
        nft.setPublicMintActive(true);
        vm.stopPrank();
        
        // Fund admin and service accounts
        vm.deal(admin, 100 ether);
        vm.deal(service, 100 ether);
        vm.deal(creator, 10 ether);
    }
    
    function testInitialAnalyticsState() public {
        // All metrics should start at zero
        assertEq(distributor.totalAccrued(), 0);
        assertEq(distributor.totalClaimed(), 0);
        assertEq(distributor.totalUnclaimed(), 0);
        assertEq(distributor.collectionUnclaimed(address(nft)), 0);
        assertEq(nft.totalUnclaimedRoyalties(), 0);
    }
    
    function testSingleSaleAnalytics() public {
        // Mint a token
        vm.prank(minters[0]);
        nft.mint{value: 0.1 ether}(minters[0]);
        
        // Record a sale
        uint256 salePrice = 1 ether;
        uint256 royaltyAmount = (salePrice * ROYALTY_FEE) / 10000;
        
        uint256[] memory tokenIds = new uint256[](1);
        address[] memory tokenMinters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);
        
        tokenIds[0] = 1;
        tokenMinters[0] = minters[0];
        salePrices[0] = salePrice;
        txHashes[0] = keccak256("sale1");
        
        // Process the sale
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            tokenMinters,
            salePrices,
            txHashes
        );
        
        // Check accrued royalties
        assertEq(distributor.totalAccrued(), royaltyAmount);
        assertEq(distributor.totalClaimed(), 0);
        assertEq(distributor.totalUnclaimed(), royaltyAmount);
        
        // Add the royalties to the pool
        vm.prank(service);
        distributor.addCollectionRoyalties{value: royaltyAmount}(address(nft));
        
        // Collection unclaimed should now show the amount
        assertEq(distributor.collectionUnclaimed(address(nft)), royaltyAmount);
        assertEq(nft.totalUnclaimedRoyalties(), royaltyAmount);
    }
    
    function testMultipleSalesAndClaims() public {
        // Mint multiple tokens
        for (uint256 i = 0; i < NUM_MINTERS; i++) {
            vm.prank(minters[i]);
            nft.mint{value: 0.1 ether}(minters[i]);
        }
        
        // Record multiple sales with different prices
        uint256[] memory tokenIds = new uint256[](NUM_MINTERS);
        address[] memory tokenMinters = new address[](NUM_MINTERS);
        uint256[] memory salePrices = new uint256[](NUM_MINTERS);
        bytes32[] memory txHashes = new bytes32[](NUM_MINTERS);
        
        uint256 totalRoyalty = 0;
        
        for (uint256 i = 0; i < NUM_MINTERS; i++) {
            tokenIds[i] = i + 1;
            tokenMinters[i] = minters[i];
            salePrices[i] = (i + 1) * 1 ether; // Different prices
            txHashes[i] = keccak256(abi.encodePacked("sale", i));
            
            uint256 saleRoyalty = (salePrices[i] * ROYALTY_FEE) / 10000;
            totalRoyalty += saleRoyalty;
        }
        
        // Process the sales
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            tokenMinters,
            salePrices,
            txHashes
        );
        
        // Check total accrued royalties
        assertEq(distributor.totalAccrued(), totalRoyalty);
        
        // Add funds to the distributor
        vm.prank(service);
        distributor.addCollectionRoyalties{value: totalRoyalty}(address(nft));
        
        // Check collection unclaimed is the total
        assertEq(distributor.collectionUnclaimed(address(nft)), totalRoyalty);
        assertEq(nft.totalUnclaimedRoyalties(), totalRoyalty);
        
        // Create claim data for the first minter
        uint256 minter0SalePrice = salePrices[0];
        uint256 minter0Royalty = (minter0SalePrice * ROYALTY_FEE) / 10000;
        uint256 minter0Share = (minter0Royalty * MINTER_SHARES) / 10000;
        
        // Submit Merkle root for the first minter claim
        bytes32 merkleRoot = keccak256(abi.encodePacked(minters[0], minter0Share));
        
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), merkleRoot, minter0Share);
        
        // Minter claims their share
        bytes32[] memory emptyProof = new bytes32[](0);
        vm.prank(minters[0]);
        distributor.claimRoyaltiesMerkle(address(nft), minters[0], minter0Share, emptyProof);
        
        // Check analytics after claim
        assertEq(distributor.totalClaimed(), minter0Share);
        assertEq(distributor.totalUnclaimed(), totalRoyalty - minter0Share);
        assertEq(distributor.collectionUnclaimed(address(nft)), totalRoyalty - minter0Share);
        assertEq(nft.totalUnclaimedRoyalties(), totalRoyalty - minter0Share);
    }
    
    function testPartialPoolFunding() public {
        // Mint a token
        vm.prank(minters[0]);
        nft.mint{value: 0.1 ether}(minters[0]);
        
        // Record a sale
        uint256 salePrice = 10 ether;
        uint256 royaltyAmount = (salePrice * ROYALTY_FEE) / 10000;
        
        uint256[] memory tokenIds = new uint256[](1);
        address[] memory tokenMinters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);
        
        tokenIds[0] = 1;
        tokenMinters[0] = minters[0];
        salePrices[0] = salePrice;
        txHashes[0] = keccak256("bigSale");
        
        // Process the sale
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            tokenMinters,
            salePrices,
            txHashes
        );
        
        // Add only half of the royalties to the pool
        uint256 halfRoyalty = royaltyAmount / 2;
        vm.prank(service);
        distributor.addCollectionRoyalties{value: halfRoyalty}(address(nft));
        
        // Check that accrued is the full amount but collection unclaimed is only what's funded
        assertEq(distributor.totalAccrued(), royaltyAmount);
        assertEq(distributor.collectionUnclaimed(address(nft)), halfRoyalty);
        assertEq(nft.totalUnclaimedRoyalties(), halfRoyalty);
        
        // Calculate the minter and creator shares
        uint256 minterShare = (royaltyAmount * MINTER_SHARES) / 10000;
        
        // Try to submit a merkle root for more than what's in the pool
        // This should revert only if minterShare > halfRoyalty
        bytes32 merkleRoot = keccak256(abi.encodePacked(minters[0], minterShare));
        
        // If minterShare is less than halfRoyalty, it won't revert, so we need to check
        if (minterShare > halfRoyalty) {
            vm.prank(service);
            vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__InsufficientBalanceForRoot.selector);
            distributor.submitRoyaltyMerkleRoot(address(nft), merkleRoot, minterShare);
            
            // Add the rest of the royalties
            vm.prank(service);
            distributor.addCollectionRoyalties{value: halfRoyalty}(address(nft));
            
            // Now we should be able to submit the root
            vm.prank(service);
            distributor.submitRoyaltyMerkleRoot(address(nft), merkleRoot, minterShare);
        } else {
            // Minter share is small enough to be covered by halfRoyalty
            vm.prank(service);
            distributor.submitRoyaltyMerkleRoot(address(nft), merkleRoot, minterShare);
            
            // Add the rest of the royalties for later claims
            vm.prank(service);
            distributor.addCollectionRoyalties{value: halfRoyalty}(address(nft));
        }
        
        // Claim should now work
        bytes32[] memory emptyProof = new bytes32[](0);
        vm.prank(minters[0]);
        distributor.claimRoyaltiesMerkle(address(nft), minters[0], minterShare, emptyProof);
        
        // Check updated analytics
        assertEq(distributor.totalClaimed(), minterShare);
        assertEq(distributor.totalUnclaimed(), royaltyAmount - minterShare);
    }
    
    function testAnalyticsWithMultipleCollections() public {
        // Deploy a second NFT collection
        vm.startPrank(admin);
        DiamondGenesisPass nft2 = new DiamondGenesisPass(address(distributor), ROYALTY_FEE, creator);
        if (!distributor.isCollectionRegistered(address(nft2))) {
            distributor.registerCollection(
                address(nft2),
                ROYALTY_FEE,
                MINTER_SHARES,
                CREATOR_SHARES,
                creator
            );
        }
        nft2.setPublicMintActive(true);
        vm.stopPrank();
        
        // Mint tokens in both collections
        vm.prank(minters[0]);
        nft.mint{value: 0.1 ether}(minters[0]);
        
        vm.prank(minters[1]);
        nft2.mint{value: 0.1 ether}(minters[1]);
        
        // Record sales for both collections
        uint256 salePrice1 = 1 ether;
        uint256 salePrice2 = 2 ether;
        
        uint256 royalty1 = (salePrice1 * ROYALTY_FEE) / 10000;
        uint256 royalty2 = (salePrice2 * ROYALTY_FEE) / 10000;
        
        // Process first sale
        uint256[] memory tokenIds = new uint256[](1);
        address[] memory tokenMinters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);
        
        tokenIds[0] = 1;
        tokenMinters[0] = minters[0];
        salePrices[0] = salePrice1;
        txHashes[0] = keccak256("sale1");
        
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            tokenMinters,
            salePrices,
            txHashes
        );
        
        // Process second sale
        tokenIds[0] = 1;
        tokenMinters[0] = minters[1];
        salePrices[0] = salePrice2;
        txHashes[0] = keccak256("sale2");
        
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft2),
            tokenIds,
            tokenMinters,
            salePrices,
            txHashes
        );
        
        // Add royalties to both collections
        vm.prank(service);
        distributor.addCollectionRoyalties{value: royalty1}(address(nft));
        
        vm.prank(service);
        distributor.addCollectionRoyalties{value: royalty2}(address(nft2));
        
        // Check global analytics
        assertEq(distributor.totalAccrued(), royalty1 + royalty2);
        assertEq(distributor.totalUnclaimed(), royalty1 + royalty2);
        
        // Check collection-specific analytics
        assertEq(distributor.collectionUnclaimed(address(nft)), royalty1);
        assertEq(nft.totalUnclaimedRoyalties(), royalty1);
        
        assertEq(distributor.collectionUnclaimed(address(nft2)), royalty2);
        assertEq(nft2.totalUnclaimedRoyalties(), royalty2);
    }
} 