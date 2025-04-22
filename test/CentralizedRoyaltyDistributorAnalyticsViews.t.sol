// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";

contract CentralizedRoyaltyDistributorAnalyticsViewsTest is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass nft;
    
    address admin = address(0xA11CE);
    address service = address(0xBEEF);
    address creator = address(0xC0FFEE);
    address minter = address(0x1);
    address buyer = address(0x2);
    
    uint96 royaltyFee = 750; // 7.5%
    
    function setUp() public {
        // Deploy distributor and set up roles
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        
        // Deploy NFT contract and register with distributor
        nft = new DiamondGenesisPass(address(distributor), royaltyFee, creator);
        if (!distributor.isCollectionRegistered(address(nft))) {
            distributor.registerCollection(address(nft), royaltyFee, 2000, 8000, creator);
        }
        // Set up NFT for minting (must be done by owner)
        nft.setPublicMintActive(true);
        vm.stopPrank();
        
        // Fund accounts
        vm.deal(minter, 10 ether);
        vm.deal(buyer, 10 ether);
    }
    
    function testInitialAnalyticsViewFunctions() public view {
        // Initial values should be zero
        assertEq(distributor.totalAccrued(), 0);
        assertEq(distributor.totalClaimed(), 0);
        
        // Collection-specific royalty data should also be zero
        (uint256 volume, , uint256 collected) = distributor.getCollectionRoyaltyData(address(nft));
        assertEq(volume, 0);
        assertEq(collected, 0);
    }
    
    function testAnalyticsAfterSales() public {
        // Mint NFT
        vm.prank(minter);
        nft.mint{value: 0.1 ether}(minter);
        
        // Set up sale data
        uint256[] memory tokenIds = new uint256[](1);
        address[] memory minters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);
        
        tokenIds[0] = 1;
        minters[0] = minter;
        salePrices[0] = 1 ether;
        txHashes[0] = keccak256(abi.encodePacked("sale1"));
        
        // Update royalty data - this will accrue royalties in totalAccruedRoyalty
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            minters,
            salePrices,
            txHashes
        );
        
        // Calculate expected royalty (7.5% of 1 ETH)
        uint256 expectedRoyalty = (1 ether * royaltyFee) / 10_000;
        
        // Check the actual accrued royalty amount from the contract
        uint256 actualRoyaltyAccrued = distributor.totalAccrued();
        
        // Verify the accrued amount matches our expectation
        assertEq(actualRoyaltyAccrued, expectedRoyalty);
        
        // Add royalties to the distributor
        vm.deal(service, actualRoyaltyAccrued);
        vm.prank(service);
        distributor.addCollectionRoyalties{value: actualRoyaltyAccrued}(address(nft));
        
        // Verify collection data
        (uint256 volume, uint256 lastBlock, uint256 collected) = distributor.getCollectionRoyaltyData(address(nft));
        assertEq(volume, 1 ether); // Total sale volume
        assertEq(lastBlock, block.number);
        assertEq(collected, actualRoyaltyAccrued);
    }
    
    function testAnalyticsAfterMultipleSales() public {
        // Mint NFTs
        vm.startPrank(minter);
        nft.mint{value: 0.1 ether}(minter);
        nft.mint{value: 0.1 ether}(minter);
        vm.stopPrank();
        
        // Update royalty data for two sales - this will accrue royalties in totalAccruedRoyalty
        uint256[] memory tokenIds = new uint256[](2);
        address[] memory minters = new address[](2);
        uint256[] memory salePrices = new uint256[](2);
        bytes32[] memory txHashes = new bytes32[](2);
        
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        minters[0] = minter;
        minters[1] = minter;
        salePrices[0] = 1 ether;
        salePrices[1] = 2 ether;
        txHashes[0] = keccak256(abi.encodePacked("sale1"));
        txHashes[1] = keccak256(abi.encodePacked("sale2"));
        
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            minters,
            salePrices,
            txHashes
        );
        
        // Calculate expected royalty for both sales (7.5% of 3 ETH total)
        uint256 expectedRoyalty = (3 ether * royaltyFee) / 10_000; // 0.225 ETH
        
        // Get the actual accrued royalty from the contract
        uint256 actualRoyaltyAccrued = distributor.totalAccrued();
        
        // Verify the accrued amount matches our expectation
        assertEq(actualRoyaltyAccrued, expectedRoyalty);
        
        // Add royalties to the distributor
        vm.deal(service, actualRoyaltyAccrued);
        vm.prank(service);
        distributor.addCollectionRoyalties{value: actualRoyaltyAccrued}(address(nft));
        
        // Store the current totalAccrued before direct updates
        uint256 accruedBeforeDirectUpdates = distributor.totalAccrued();
        
        // Calculate minter and creator shares
        uint256 minterShare = (actualRoyaltyAccrued * 2000) / 10000; // 20%
        uint256 creatorShare = (actualRoyaltyAccrued * 8000) / 10000; // 80%
        
        // Create recipients and amounts arrays for direct accrual
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        recipients[0] = minter;
        recipients[1] = creator;
        amounts[0] = minterShare;
        amounts[1] = creatorShare;
        
        // Update accrued royalties directly - this also updates totalAccruedRoyalty
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // The totalAccrued is now increased by the sum of minterShare and creatorShare
        uint256 expectedTotalAfterDirectUpdates = accruedBeforeDirectUpdates + minterShare + creatorShare;
        
        // Verify totalAccrued was updated with both sets of royalties
        assertEq(distributor.totalAccrued(), expectedTotalAfterDirectUpdates);
        
        // Check collection data after adding royalties
        (uint256 volume, uint256 lastBlock, uint256 collected) = distributor.getCollectionRoyaltyData(address(nft));
        assertEq(volume, 3 ether); // 1 ETH + 2 ETH total volume
        assertEq(lastBlock, block.number);
        assertEq(collected, actualRoyaltyAccrued);
        
        // Minter claims their share
        vm.prank(minter);
        distributor.claimRoyalties(address(nft), minterShare);
        
        // Verify analytics after partial claim - totalAccrued stays the same, only totalClaimed changes
        assertEq(distributor.totalAccrued(), expectedTotalAfterDirectUpdates);
        assertEq(distributor.totalClaimed(), minterShare);
        
        // Creator claims their share
        vm.prank(creator);
        distributor.claimRoyalties(address(nft), creatorShare);
        
        // Verify analytics after all claims - totalAccrued stays the same, totalClaimed increases
        assertEq(distributor.totalAccrued(), expectedTotalAfterDirectUpdates);
        assertEq(distributor.totalClaimed(), minterShare + creatorShare);
    }
    
    function testAnalyticsWithPartialClaims() public {
        // Mint NFT
        vm.prank(minter);
        nft.mint{value: 0.1 ether}(minter);
        
        // Update royalty data
        uint256[] memory tokenIds = new uint256[](1);
        address[] memory minters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);
        
        tokenIds[0] = 1;
        minters[0] = minter;
        salePrices[0] = 1 ether;
        txHashes[0] = keccak256(abi.encodePacked("sale1"));
        
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            minters,
            salePrices,
            txHashes
        );
        
        // Calculate expected royalty (7.5% of 1 ETH)
        uint256 expectedRoyalty = (1 ether * royaltyFee) / 10_000; // 0.075 ETH
        
        // Get actual royalty accrued after batchUpdate
        uint256 actualRoyaltyAccrued = distributor.totalAccrued();
        
        // Verify the accrued amount matches our expectation
        assertEq(actualRoyaltyAccrued, expectedRoyalty);
        
        // Calculate shares based on actual royalty
        uint256 minterShare = (actualRoyaltyAccrued * 2000) / 10000; // 20%
        uint256 creatorShare = (actualRoyaltyAccrued * 8000) / 10000; // 80%
        
        // Add royalties
        vm.deal(service, actualRoyaltyAccrued);
        vm.prank(service);
        distributor.addCollectionRoyalties{value: actualRoyaltyAccrued}(address(nft));
        
        // Store the accrued amount before direct accrual updates
        uint256 accruedBeforeDirectUpdates = distributor.totalAccrued();
        
        // Create recipients and amounts arrays for direct accrual
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        recipients[0] = minter;
        recipients[1] = creator;
        amounts[0] = minterShare;
        amounts[1] = creatorShare;
        
        // Update accrued royalties directly - this also updates totalAccruedRoyalty
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // The totalAccrued is now increased by the sum of minterShare and creatorShare
        uint256 expectedTotalAfterDirectUpdates = accruedBeforeDirectUpdates + minterShare + creatorShare;
        
        // Verify totalAccrued was updated with both sets of royalties
        assertEq(distributor.totalAccrued(), expectedTotalAfterDirectUpdates);
        
        // Minter claims their share
        vm.prank(minter);
        distributor.claimRoyalties(address(nft), minterShare);
        
        // Verify analytics after partial claim - totalAccrued stays the same, only totalClaimed changes
        assertEq(distributor.totalAccrued(), expectedTotalAfterDirectUpdates);
        assertEq(distributor.totalClaimed(), minterShare);
        
        // Creator claims their share
        vm.prank(creator);
        distributor.claimRoyalties(address(nft), creatorShare);
        
        // Verify analytics after all claims - totalAccrued stays the same, totalClaimed increases
        assertEq(distributor.totalAccrued(), expectedTotalAfterDirectUpdates);
        assertEq(distributor.totalClaimed(), minterShare + creatorShare);
    }
    
    function testTokenLevelRoyaltyData() public {
        // Mint NFT
        vm.prank(minter);
        nft.mint{value: 0.1 ether}(minter);
        
        // Set up sale data
        uint256[] memory tokenIds = new uint256[](1);
        address[] memory minters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);
        
        tokenIds[0] = 1;
        minters[0] = minter;
        salePrices[0] = 1 ether;
        txHashes[0] = keccak256(abi.encodePacked("sale1"));
        
        // Update royalty data
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            minters,
            salePrices,
            txHashes
        );
        
        // Get token royalty data
        (address tokenMinter, address tokenHolder, uint256 txCount, uint256 volume, uint256 minterEarned, uint256 creatorEarned) = 
            distributor.getTokenRoyaltyData(address(nft), 1);
        
        // Calculate expected royalty
        uint256 totalRoyalty = (1 ether * royaltyFee) / 10_000;
        uint256 expectedMinterShare = (totalRoyalty * 2000) / 10_000;
        uint256 expectedCreatorShare = (totalRoyalty * 8000) / 10_000;
        
        // Verify token data
        assertEq(tokenMinter, minter);
        assertEq(tokenHolder, minter); // Still held by minter
        assertEq(txCount, 1);
        assertEq(volume, 1 ether);
        assertEq(minterEarned, expectedMinterShare);
        assertEq(creatorEarned, expectedCreatorShare);
        
        // Verify through adapter methods
        assertEq(nft.minterOf(1), minter);
        assertEq(nft.getTokenHolder(1), minter);
        assertEq(nft.getTokenTransactionCount(1), 1);
        assertEq(nft.getTokenTotalVolume(1), 1 ether);
        assertEq(nft.getMinterRoyaltyEarned(1), expectedMinterShare);
        assertEq(nft.getCreatorRoyaltyEarned(1), expectedCreatorShare);
    }
} 