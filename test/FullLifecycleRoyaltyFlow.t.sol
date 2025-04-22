// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FullLifecycleRoyaltyFlowTest is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass nft;
    
    address admin = address(0xA11CE);
    address service = address(0xBEEF);
    address creator = address(0xC0FFEE);
    address buyer1 = address(0x1);
    address buyer2 = address(0x2);
    
    uint96 royaltyFee = 750; // 7.5%
    uint256 mintPrice = 0.1 ether;
    uint256 salePrice = 1 ether;
    
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
        
        // Set up NFT for minting
        nft.setPublicMintActive(true);
        vm.stopPrank();
        
        // Fund accounts
        vm.deal(buyer1, 10 ether);
        vm.deal(buyer2, 10 ether);
        vm.deal(admin, 10 ether);
    }
    
    function testFullLifecycle() public {
        // Step 1: Mint NFT to buyer1
        vm.prank(buyer1);
        nft.mint{value: mintPrice}(buyer1);
        
        // Verify mint was successful
        assertEq(nft.ownerOf(1), buyer1);
        
        // Step 2: Secondary sale (buyer1 -> buyer2)
        // First approve the transfer
        vm.prank(buyer1);
        nft.approve(buyer2, 1);
        
        // Simulate the sale by transferring the NFT using safeTransferFrom
        vm.prank(buyer1);
        nft.safeTransferFrom(buyer1, buyer2, 1);
        
        // Verify transfer was successful
        assertEq(nft.ownerOf(1), buyer2);
        
        // Step 3: Record the sale for royalty tracking
        vm.prank(service);
        nft.recordSale(1, salePrice);
        
        // Step 4: Simulate marketplace sending royalty payment to distributor
        uint256 royaltyAmount = (salePrice * royaltyFee) / 10000;
        vm.deal(address(this), royaltyAmount);
        distributor.addCollectionRoyalties{value: royaltyAmount}(address(nft));
        
        // Step 5: Service account processes royalty data
        uint256[] memory tokenIds = new uint256[](1);
        address[] memory minters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);
        
        tokenIds[0] = 1;
        minters[0] = buyer1; // Original minter
        salePrices[0] = salePrice;
        txHashes[0] = keccak256(abi.encodePacked("sale1"));
        
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            minters,
            salePrices,
            txHashes
        );
        
        // Step 6: Generate and submit Merkle root for claims
        // Calculate expected royalty shares
        uint256 minterShare = (royaltyAmount * 2000) / 10000; // 20% to minter
        uint256 creatorShare = (royaltyAmount * 8000) / 10000; // 80% to creator
        
        // Create simple Merkle tree with two leaves (one for minter, one for creator)
        bytes32 minterLeaf = keccak256(abi.encodePacked(address(buyer1), minterShare));
        bytes32 creatorLeaf = keccak256(abi.encodePacked(address(creator), creatorShare));
        
        // For simplicity, we're using a very basic Merkle tree
        bytes32 merkleRoot = keccak256(abi.encodePacked(minterLeaf, creatorLeaf));
        
        // Submit the Merkle root
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), merkleRoot, royaltyAmount);
        
        // Step 7: Minter claims their share
        bytes32[] memory minterProof = new bytes32[](1);
        minterProof[0] = creatorLeaf;
        
        uint256 minterBalanceBefore = buyer1.balance;
        vm.prank(buyer1);
        distributor.claimRoyaltiesMerkle(address(nft), buyer1, minterShare, minterProof);
        
        // Verify minter received their share
        assertEq(buyer1.balance - minterBalanceBefore, minterShare);
        
        // Step 8: Creator claims their share
        bytes32[] memory creatorProof = new bytes32[](1);
        creatorProof[0] = minterLeaf;
        
        uint256 creatorBalanceBefore = creator.balance;
        vm.prank(creator);
        distributor.claimRoyaltiesMerkle(address(nft), creator, creatorShare, creatorProof);
        
        // Verify creator received their share
        assertEq(creator.balance - creatorBalanceBefore, creatorShare);
        
        // Verify analytics
        assertEq(distributor.totalAccrued(), royaltyAmount);
        assertEq(distributor.totalClaimed(), royaltyAmount);
    }
}
