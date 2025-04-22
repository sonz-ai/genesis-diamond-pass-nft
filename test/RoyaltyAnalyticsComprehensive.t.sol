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
        
        // Process the sale via batchUpdate
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            tokenMinters,
            salePrices,
            txHashes
        );
        
        // Check accrued royalties analytics (updated by batchUpdate)
        assertEq(distributor.totalAccrued(), royaltyAmount);
        assertEq(distributor.totalClaimed(), 0);
        assertEq(distributor.totalUnclaimed(), royaltyAmount);
        
        // Add the royalties to the pool (funding for claims)
        vm.prank(admin); // Use admin or any account with funds
        distributor.addCollectionRoyalties{value: royaltyAmount}(address(nft));
        
        // Collection unclaimed should now show the amount
        assertEq(distributor.collectionUnclaimed(address(nft)), royaltyAmount);
        assertEq(nft.totalUnclaimedRoyalties(), royaltyAmount);
    }
    
    function testMultipleSalesAndClaimsDirectAccrual() public {
        // Mint multiple tokens
        for (uint256 i = 0; i < NUM_MINTERS; i++) {
            vm.prank(minters[i]);
            nft.mint{value: 0.1 ether}(minters[i]);
        }
        
        // Record multiple sales with different prices via batchUpdate
        uint256[] memory tokenIds = new uint256[](NUM_MINTERS);
        address[] memory tokenMinters = new address[](NUM_MINTERS);
        uint256[] memory salePrices = new uint256[](NUM_MINTERS);
        bytes32[] memory txHashes = new bytes32[](NUM_MINTERS);
        
        uint256 totalRoyaltyAccruedViaBatch = 0;
        uint256[] memory minterShares = new uint256[](NUM_MINTERS);
        uint256[] memory creatorShares = new uint256[](NUM_MINTERS); // Track creator shares too
        uint256 totalRoyaltyForPool = 0;
        
        for (uint256 i = 0; i < NUM_MINTERS; i++) {
            tokenIds[i] = i + 1;
            tokenMinters[i] = minters[i];
            salePrices[i] = (i + 1) * 1 ether; // Different prices
            txHashes[i] = keccak256(abi.encodePacked("sale", i));
            
            uint256 saleRoyalty = (salePrices[i] * ROYALTY_FEE) / 10000;
            totalRoyaltyAccruedViaBatch += saleRoyalty;
            totalRoyaltyForPool += saleRoyalty; // Assume full amount sent to pool
            minterShares[i] = (saleRoyalty * MINTER_SHARES) / 10000;
            creatorShares[i] = (saleRoyalty * CREATOR_SHARES) / 10000;
        }
        
        // Process the sales via batchUpdate (updates analytics)
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            tokenMinters,
            salePrices,
            txHashes
        );
        
        // Check total accrued royalties analytics
        assertEq(distributor.totalAccrued(), totalRoyaltyAccruedViaBatch);
        
        // Add funds to the distributor pool
        vm.prank(admin);
        distributor.addCollectionRoyalties{value: totalRoyaltyForPool}(address(nft));
        
        // Check collection unclaimed is the total added to the pool
        assertEq(distributor.collectionUnclaimed(address(nft)), totalRoyaltyForPool);
        assertEq(nft.totalUnclaimedRoyalties(), totalRoyaltyForPool);
        
        // Accrue claimable amount for the first minter using updateAccruedRoyalties
        address[] memory minter0Recipient = new address[](1); minter0Recipient[0] = minters[0];
        uint256[] memory minter0Amount = new uint256[](1); minter0Amount[0] = minterShares[0];
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), minter0Recipient, minter0Amount);
        
        // Accrue claimable amount for the creator (sum of all creator shares from sales)
        uint256 totalCreatorShare = 0;
        for(uint i = 0; i < NUM_MINTERS; i++) { totalCreatorShare += creatorShares[i]; }
        address[] memory creatorRecipient = new address[](1); creatorRecipient[0] = creator;
        uint256[] memory creatorAmount = new uint256[](1); creatorAmount[0] = totalCreatorShare;
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), creatorRecipient, creatorAmount);

        // Verify totalAccrued has increased again due to direct updates
        uint256 totalDirectAccrual = minterShares[0] + totalCreatorShare;
        assertEq(distributor.totalAccrued(), totalRoyaltyAccruedViaBatch + totalDirectAccrual);
        assertEq(distributor.getClaimableRoyalties(address(nft), minters[0]), minterShares[0]);
        assertEq(distributor.getClaimableRoyalties(address(nft), creator), totalCreatorShare);
        
        // Minter 0 claims their share using claimRoyalties
        uint256 balanceBefore = minters[0].balance;
        vm.prank(minters[0]);
        distributor.claimRoyalties(address(nft), minterShares[0]);
        assertApproxEqAbs(minters[0].balance, balanceBefore + minterShares[0], 1e15);
        
        // Check analytics after claim
        assertEq(distributor.totalClaimed(), minterShares[0]);
        assertEq(distributor.totalUnclaimed(), totalRoyaltyAccruedViaBatch + totalDirectAccrual - minterShares[0]);
        assertEq(distributor.collectionUnclaimed(address(nft)), totalRoyaltyForPool - minterShares[0]);
        assertEq(nft.totalUnclaimedRoyalties(), totalRoyaltyForPool - minterShares[0]);

        // Creator claims their share using claimRoyalties
        balanceBefore = creator.balance;
        vm.prank(creator);
        distributor.claimRoyalties(address(nft), totalCreatorShare);
        assertApproxEqAbs(creator.balance, balanceBefore + totalCreatorShare, 1e15);

        // Check final analytics
        assertEq(distributor.totalClaimed(), minterShares[0] + totalCreatorShare);
        assertEq(distributor.collectionUnclaimed(address(nft)), totalRoyaltyForPool - minterShares[0] - totalCreatorShare);
        assertEq(nft.totalUnclaimedRoyalties(), totalRoyaltyForPool - minterShares[0] - totalCreatorShare);
    }
    
    function testPartialPoolFundingDirectAccrual() public {
        // Mint a token
        vm.prank(minters[0]);
        nft.mint{value: 0.1 ether}(minters[0]);
        
        // Record a sale via batchUpdate (updates totalAccrued analytic)
        uint256 salePrice = 10 ether;
        uint256 royaltyAmount = (salePrice * ROYALTY_FEE) / 10000;
        
        uint256[] memory tokenIds = new uint256[](1); tokenIds[0] = 1;
        address[] memory tokenMinters = new address[](1); tokenMinters[0] = minters[0];
        uint256[] memory salePrices = new uint256[](1); salePrices[0] = salePrice;
        bytes32[] memory txHashes = new bytes32[](1); txHashes[0] = keccak256("bigSale");
        
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            tokenMinters,
            salePrices,
            txHashes
        );
        assertEq(distributor.totalAccrued(), royaltyAmount); // Analytic updated
        
        // Add only half of the royalties to the pool
        uint256 halfRoyalty = royaltyAmount / 2;
        vm.prank(admin);
        distributor.addCollectionRoyalties{value: halfRoyalty}(address(nft));
        
        // Check that accrued analytic is the full amount but collection unclaimed is only what's funded
        assertEq(distributor.totalAccrued(), royaltyAmount); 
        assertEq(distributor.collectionUnclaimed(address(nft)), halfRoyalty);
        assertEq(nft.totalUnclaimedRoyalties(), halfRoyalty);
        
        // Calculate the minter and creator shares based on the full royalty amount
        uint256 minterShare = (royaltyAmount * MINTER_SHARES) / 10000;
        uint256 creatorShare = (royaltyAmount * CREATOR_SHARES) / 10000;
        
        // Accrue claimable amounts for minter and creator using updateAccruedRoyalties
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        recipients[0] = minters[0]; amounts[0] = minterShare;
        recipients[1] = creator; amounts[1] = creatorShare;
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // Verify claimable amounts
        assertEq(distributor.getClaimableRoyalties(address(nft), minters[0]), minterShare);
        assertEq(distributor.getClaimableRoyalties(address(nft), creator), creatorShare);
        // Verify totalAccrued includes both batch and direct updates
        assertEq(distributor.totalAccrued(), royaltyAmount + minterShare + creatorShare);

        // Minter tries to claim their full share
        // This should FAIL if minterShare > halfRoyalty (the funded amount)
        // This should SUCCEED if minterShare <= halfRoyalty
        uint256 balanceBefore = minters[0].balance;
        if (minterShare > halfRoyalty) {
            vm.prank(minters[0]);
            vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__NotEnoughEtherToDistributeForCollection.selector);
            distributor.claimRoyalties(address(nft), minterShare);
            
            // Add the rest of the royalties
            vm.prank(admin);
            distributor.addCollectionRoyalties{value: halfRoyalty}(address(nft));
            
            // Now claim should succeed
            vm.prank(minters[0]);
            distributor.claimRoyalties(address(nft), minterShare);
            assertApproxEqAbs(minters[0].balance, balanceBefore + minterShare, 1e15);
        } else {
            // Minter share is small enough to be covered by halfRoyalty, claim succeeds
            vm.prank(minters[0]);
            distributor.claimRoyalties(address(nft), minterShare);
            assertApproxEqAbs(minters[0].balance, balanceBefore + minterShare, 1e15);
            
            // Add the rest of the royalties for creator later
            vm.prank(admin);
            distributor.addCollectionRoyalties{value: halfRoyalty}(address(nft));
        }
        
        // Check updated analytics after successful minter claim
        assertEq(distributor.totalClaimed(), minterShare);
        assertEq(distributor.totalUnclaimed(), royaltyAmount + minterShare + creatorShare - minterShare);
        // collectionUnclaimed should reflect remaining physical funds
        assertEq(distributor.collectionUnclaimed(address(nft)), royaltyAmount - minterShare);
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
                creator // Using same creator for simplicity here
            );
        }
        nft2.setPublicMintActive(true);
        vm.stopPrank();
        
        // Mint tokens in both collections
        vm.prank(minters[0]);
        nft.mint{value: 0.1 ether}(minters[0]);
        
        vm.prank(minters[1]);
        nft2.mint{value: 0.1 ether}(minters[1]);
        
        // Record sales for both collections via batchUpdate (updates global totalAccrued)
        uint256 salePrice1 = 1 ether;
        uint256 salePrice2 = 2 ether;
        
        uint256 royalty1 = (salePrice1 * ROYALTY_FEE) / 10000;
        uint256 royalty2 = (salePrice2 * ROYALTY_FEE) / 10000;
        
        // Process first sale (nft1)
        uint256[] memory tokenIds = new uint256[](1); tokenIds[0] = 1;
        address[] memory tokenMinters = new address[](1); tokenMinters[0] = minters[0];
        uint256[] memory salePrices = new uint256[](1); salePrices[0] = salePrice1;
        bytes32[] memory txHashes = new bytes32[](1); txHashes[0] = keccak256("sale1");
        
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(address(nft), tokenIds, tokenMinters, salePrices, txHashes);
        
        // Process second sale (nft2)
        tokenIds[0] = 1; // Token ID 1 for nft2
        tokenMinters[0] = minters[1];
        salePrices[0] = salePrice2;
        txHashes[0] = keccak256("sale2");
        
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(address(nft2), tokenIds, tokenMinters, salePrices, txHashes);
        
        // Add funds to both collections' pools
        vm.prank(admin);
        distributor.addCollectionRoyalties{value: royalty1}(address(nft));
        
        vm.prank(admin);
        distributor.addCollectionRoyalties{value: royalty2}(address(nft2));
        
        // Check global analytics (only reflects batch updates so far)
        assertEq(distributor.totalAccrued(), royalty1 + royalty2);
        assertEq(distributor.totalUnclaimed(), royalty1 + royalty2);
        
        // Check collection-specific analytics (physical funds in pool)
        assertEq(distributor.collectionUnclaimed(address(nft)), royalty1);
        assertEq(nft.totalUnclaimedRoyalties(), royalty1);
        
        assertEq(distributor.collectionUnclaimed(address(nft2)), royalty2);
        assertEq(nft2.totalUnclaimedRoyalties(), royalty2);

        // Now, accrue directly for claims
        uint256 minter1Share = (royalty1 * MINTER_SHARES) / 10000;
        uint256 minter2Share = (royalty2 * MINTER_SHARES) / 10000;
        
        address[] memory r1 = new address[](1); r1[0] = minters[0];
        uint256[] memory a1 = new uint256[](1); a1[0] = minter1Share;
        address[] memory r2 = new address[](1); r2[0] = minters[1];
        uint256[] memory a2 = new uint256[](1); a2[0] = minter2Share;
        
        vm.startPrank(service);
        distributor.updateAccruedRoyalties(address(nft), r1, a1);
        distributor.updateAccruedRoyalties(address(nft2), r2, a2);
        vm.stopPrank();

        // Check global totalAccrued reflects both batch and direct updates
        assertEq(distributor.totalAccrued(), royalty1 + royalty2 + minter1Share + minter2Share);

        // Minter 0 claims from nft1
        vm.prank(minters[0]);
        distributor.claimRoyalties(address(nft), minter1Share);

        // Check global totalClaimed and collection-specific pool
        assertEq(distributor.totalClaimed(), minter1Share);
        assertEq(distributor.collectionUnclaimed(address(nft)), royalty1 - minter1Share);
        assertEq(distributor.collectionUnclaimed(address(nft2)), royalty2); // Unchanged
    }
} 