// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";
import "lib/murky/src/Merkle.sol";

contract CentralizedRoyaltyDistributorAnalyticsViewsTest is Test {
    Merkle merkle;
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass nft;
    
    address admin = address(0xA11CE);
    address service = address(0xBEEF);
    address creator = address(0xC0FFEE);
    address minter = address(0x1);
    address buyer = address(0x2);
    
    uint96 royaltyFee = 750; // 7.5%
    
    function setUp() public {
        // Deploy Merkle library for proof generation
        merkle = new Merkle();

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
        uint256[] memory timestamps = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);
        
        tokenIds[0] = 1;
        minters[0] = minter;
        salePrices[0] = 1 ether;
        timestamps[0] = block.timestamp;
        txHashes[0] = keccak256(abi.encodePacked("sale1"));
        
        // Update royalty data - this will accrue royalties
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            minters,
            salePrices,
            timestamps,
            txHashes
        );
        
        // Check the actual accrued royalty amount from the contract
        uint256 actualRoyaltyAccrued = distributor.totalAccrued();
        
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
        
        // Update royalty data for two sales - this will accrue royalties
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
        
        // Get the actual accrued royalty from the contract
        uint256 actualRoyaltyAccrued = distributor.totalAccrued();
        
        // Add royalties to the distributor
        vm.deal(service, actualRoyaltyAccrued);
        vm.prank(service);
        distributor.addCollectionRoyalties{value: actualRoyaltyAccrued}(address(nft));
        
        // Store the current totalAccrued before submitting the Merkle root
        uint256 accruedBeforeMerkleRoot = distributor.totalAccrued();
        
        // Create a simple Merkle root for minter to claim all royalties
        bytes32 leaf = keccak256(abi.encodePacked(minter, actualRoyaltyAccrued));
        
        // Submit the Merkle root - this will accrue royalties AGAIN
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), leaf, actualRoyaltyAccrued);
        
        // Verify totalAccrued was updated again (doubled)
        assertEq(distributor.totalAccrued(), accruedBeforeMerkleRoot + actualRoyaltyAccrued);
        
        // Check collection data after adding royalties
        (uint256 volume, uint256 lastBlock, uint256 collected) = distributor.getCollectionRoyaltyData(address(nft));
        assertEq(volume, 3 ether); // 1 ETH + 2 ETH total volume
        assertEq(lastBlock, block.number);
        assertEq(collected, actualRoyaltyAccrued);
        
        // Minter claims royalties
        vm.prank(minter);
        distributor.claimRoyaltiesMerkle(address(nft), minter, actualRoyaltyAccrued, new bytes32[](0));
        
        // Verify analytics after claim (note: totalAccrued now includes BOTH accruals)
        assertEq(distributor.totalAccrued(), accruedBeforeMerkleRoot + actualRoyaltyAccrued);
        assertEq(distributor.totalClaimed(), actualRoyaltyAccrued);
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
        
        // Get actual royalty accrued after batchUpdate
        uint256 actualRoyaltyAccrued = distributor.totalAccrued();
        
        // Calculate shares based on actual royalty
        uint256 minterShare = (actualRoyaltyAccrued * 2000) / 10000; // 20%
        uint256 creatorShare = (actualRoyaltyAccrued * 8000) / 10000; // 80%
        
        // Add royalties
        vm.deal(service, actualRoyaltyAccrued);
        vm.prank(service);
        distributor.addCollectionRoyalties{value: actualRoyaltyAccrued}(address(nft));
        
        // Store the accrued amount before submitting Merkle root
        uint256 accruedBeforeMerkleRoot = distributor.totalAccrued();
        
        // Create proper Merkle tree with two leaves
        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(minter, minterShare));
        data[1] = keccak256(abi.encodePacked(creator, creatorShare));
        
        bytes32 root = merkle.getRoot(data);
        bytes32[] memory minterProof = merkle.getProof(data, 0);
        bytes32[] memory creatorProof = merkle.getProof(data, 1);
        
        // Submit the Merkle root - this will accrue royalties AGAIN
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), root, actualRoyaltyAccrued);
        
        // Verify double accrual
        assertEq(distributor.totalAccrued(), accruedBeforeMerkleRoot + actualRoyaltyAccrued);
        
        // Minter claims their share
        vm.prank(minter);
        distributor.claimRoyaltiesMerkle(address(nft), minter, minterShare, minterProof);
        
        // Verify analytics after partial claim
        assertEq(distributor.totalAccrued(), accruedBeforeMerkleRoot + actualRoyaltyAccrued);
        assertEq(distributor.totalClaimed(), minterShare);
        
        // Creator claims their share
        vm.prank(creator);
        distributor.claimRoyaltiesMerkle(address(nft), creator, creatorShare, creatorProof);
        
        // Verify analytics after all claims
        assertEq(distributor.totalAccrued(), accruedBeforeMerkleRoot + actualRoyaltyAccrued);
        assertEq(distributor.totalClaimed(), actualRoyaltyAccrued);
    }
} 