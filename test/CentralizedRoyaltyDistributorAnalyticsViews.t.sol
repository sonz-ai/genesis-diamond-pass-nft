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
        distributor.registerCollection(address(nft), royaltyFee, 2000, 8000, creator);
        
        // Set up NFT for minting
        nft.setPublicMintActive(true);
        vm.stopPrank();
        
        // Fund accounts
        vm.deal(minter, 10 ether);
        vm.deal(buyer, 10 ether);
    }
    
    function testInitialAnalyticsViewFunctions() public {
        // Initial values should be zero
        assertEq(distributor.totalAccrued(), 0);
        assertEq(distributor.totalClaimed(), 0);
        // Calculate unclaimed instead of using a function
        assertEq(distributor.totalAccrued() - distributor.totalClaimed(), 0);
        
        // Collection-specific royalty data should also be zero
        (uint256 volume, uint256 lastBlock, uint256 collected) = distributor.getCollectionRoyaltyData(address(nft));
        assertEq(volume, 0);
        assertEq(lastBlock, 0);
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
        uint256[] memory timestamps = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);
        
        tokenIds[0] = 1;
        minters[0] = minter;
        salePrices[0] = 1 ether;
        timestamps[0] = block.timestamp;
        txHashes[0] = keccak256(abi.encodePacked("sale1"));
        
        // Update royalty data
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            minters,
            salePrices,
            timestamps,
            txHashes
        );
        
        // Calculate expected royalty
        uint256 expectedRoyalty = (1 ether * royaltyFee) / 10000; // 7.5% of 1 ETH
        
        // Verify total accrued was updated
        assertEq(distributor.totalAccrued(), expectedRoyalty);
        assertEq(distributor.totalClaimed(), 0);
        assertEq(distributor.totalAccrued() - distributor.totalClaimed(), expectedRoyalty);
        
        // Add royalties to the distributor
        vm.deal(service, expectedRoyalty);
        vm.prank(service);
        distributor.addCollectionRoyalties{value: expectedRoyalty}(address(nft));
        
        // Verify collection data
        (uint256 volume, uint256 lastBlock, uint256 collected) = distributor.getCollectionRoyaltyData(address(nft));
        assertEq(volume, 1 ether); // Total sale volume
        assertEq(lastBlock, block.number);
        assertEq(collected, expectedRoyalty);
    }
    
    function testAnalyticsAfterMultipleSales() public {
        // Mint NFTs
        vm.startPrank(minter);
        nft.mint{value: 0.1 ether}(minter);
        nft.mint{value: 0.1 ether}(minter);
        vm.stopPrank();
        
        // Update royalty data for two sales
        uint256[] memory tokenIds = new uint256[](2);
        address[] memory minters = new address[](2);
        uint256[] memory salePrices = new uint256[](2);
        uint256[] memory timestamps = new uint256[](2);
        bytes32[] memory txHashes = new bytes32[](2);
        
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        minters[0] = minter;
        minters[1] = minter;
        salePrices[0] = 1 ether;
        salePrices[1] = 2 ether;
        timestamps[0] = block.timestamp;
        timestamps[1] = block.timestamp;
        txHashes[0] = keccak256(abi.encodePacked("sale1"));
        txHashes[1] = keccak256(abi.encodePacked("sale2"));
        
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            minters,
            salePrices,
            timestamps,
            txHashes
        );
        
        // Calculate expected royalties
        uint256 expectedRoyalty1 = (1 ether * royaltyFee) / 10000; // 7.5% of 1 ETH
        uint256 expectedRoyalty2 = (2 ether * royaltyFee) / 10000; // 7.5% of 2 ETH
        uint256 totalExpectedRoyalty = expectedRoyalty1 + expectedRoyalty2;
        
        // Verify analytics
        assertEq(distributor.totalAccrued(), totalExpectedRoyalty);
        assertEq(distributor.totalClaimed(), 0);
        assertEq(distributor.totalAccrued() - distributor.totalClaimed(), totalExpectedRoyalty);
        
        // Add royalties and submit Merkle root
        vm.deal(service, totalExpectedRoyalty);
        vm.prank(service);
        distributor.addCollectionRoyalties{value: totalExpectedRoyalty}(address(nft));
        
        // Create a Merkle root for minter to claim all royalties
        bytes32 leaf = keccak256(abi.encodePacked(minter, totalExpectedRoyalty));
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), leaf, totalExpectedRoyalty);
        
        // Check collection data after adding royalties
        (uint256 volume, uint256 lastBlock, uint256 collected) = distributor.getCollectionRoyaltyData(address(nft));
        assertEq(volume, 3 ether); // 1 ETH + 2 ETH total volume
        assertEq(lastBlock, block.number);
        assertEq(collected, totalExpectedRoyalty);
        
        // Minter claims royalties
        vm.prank(minter);
        distributor.claimRoyaltiesMerkle(address(nft), minter, totalExpectedRoyalty, new bytes32[](0));
        
        // Verify analytics after claim
        assertEq(distributor.totalAccrued(), totalExpectedRoyalty);
        assertEq(distributor.totalClaimed(), totalExpectedRoyalty);
        assertEq(distributor.totalAccrued() - distributor.totalClaimed(), 0);
    }
    
    function testAnalyticsWithPartialClaims() public {
        // Mint NFT
        vm.prank(minter);
        nft.mint{value: 0.1 ether}(minter);
        
        // Update royalty data
        uint256[] memory tokenIds = new uint256[](1);
        address[] memory minters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        uint256[] memory timestamps = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);
        
        tokenIds[0] = 1;
        minters[0] = minter;
        salePrices[0] = 1 ether;
        timestamps[0] = block.timestamp;
        txHashes[0] = keccak256(abi.encodePacked("sale1"));
        
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            minters,
            salePrices,
            timestamps,
            txHashes
        );
        
        // Calculate royalty and shares
        uint256 totalRoyalty = (1 ether * royaltyFee) / 10000;
        uint256 minterShare = (totalRoyalty * 2000) / 10000; // 20%
        uint256 creatorShare = (totalRoyalty * 8000) / 10000; // 80%
        
        // Add royalties
        vm.deal(service, totalRoyalty);
        vm.prank(service);
        distributor.addCollectionRoyalties{value: totalRoyalty}(address(nft));
        
        // Create Merkle tree with two leaves
        bytes32 minterLeaf = keccak256(abi.encodePacked(minter, minterShare));
        bytes32 creatorLeaf = keccak256(abi.encodePacked(creator, creatorShare));
        bytes32 merkleRoot = keccak256(abi.encodePacked(minterLeaf, creatorLeaf));
        
        // Submit Merkle root
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), merkleRoot, totalRoyalty);
        
        // Minter claims their share
        bytes32[] memory minterProof = new bytes32[](1);
        minterProof[0] = creatorLeaf;
        
        vm.prank(minter);
        distributor.claimRoyaltiesMerkle(address(nft), minter, minterShare, minterProof);
        
        // Verify analytics after partial claim
        assertEq(distributor.totalAccrued(), totalRoyalty);
        assertEq(distributor.totalClaimed(), minterShare);
        assertEq(distributor.totalAccrued() - distributor.totalClaimed(), creatorShare);
        
        // Creator claims their share
        bytes32[] memory creatorProof = new bytes32[](1);
        creatorProof[0] = minterLeaf;
        
        vm.prank(creator);
        distributor.claimRoyaltiesMerkle(address(nft), creator, creatorShare, creatorProof);
        
        // Verify analytics after all claims
        assertEq(distributor.totalAccrued(), totalRoyalty);
        assertEq(distributor.totalClaimed(), totalRoyalty);
        assertEq(distributor.totalAccrued() - distributor.totalClaimed(), 0);
    }
} 