// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title DeploymentAndLifecycleFlow
 * @notice Full deployment and lifecycle flow test for the DiamondGenesisPass NFT and royalty system
 * @dev This test covers the entire flow from deploying contracts to claiming royalties
 */
contract DeploymentAndLifecycleFlowTest is Test {
    // Contracts
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass nft;
    
    // Actors
    address deployer = address(0xDEAD);
    address service = address(0xBEEF);
    address creator = address(0xC0FFEE);
    address whitelistedUser = address(0xABC);
    address publicMinter = address(0xDEF);
    address buyer = address(0x123);
    
    // Constants
    uint96 constant ROYALTY_FEE = 750; // 7.5% in basis points
    uint256 constant MINTER_SHARES = 2000; // 20% in basis points
    uint256 constant CREATOR_SHARES = 8000; // 80% in basis points
    uint256 constant PUBLIC_MINT_PRICE = 0.1 ether;
    uint256 constant SALE_PRICE = 1 ether;
    bytes32 merkleRoot;
    
    /**
     * @notice Configure test actors and initial balances
     */
    function setUp() public {
        // No contracts deployed yet - we'll do that as part of the test
        
        // Fund accounts
        vm.deal(deployer, 10 ether);
        vm.deal(whitelistedUser, 10 ether);
        vm.deal(publicMinter, 10 ether);
        vm.deal(buyer, 10 ether);
    }
    
    /**
     * @notice Create a simple merkle tree with one whitelisted address
     * @param user The whitelisted user address
     * @param quantity The allowed mint quantity
     * @return root The merkle root
     * @return proof The merkle proof for the user
     */
    function createSimpleMerkleTree(address user, uint256 quantity) internal pure returns (bytes32 root, bytes32[] memory proof) {
        // Create leaf for the user
        bytes32 leaf = keccak256(abi.encodePacked(user, quantity));
        
        // For simplicity, we're creating a tree with a single entry
        // In a real scenario, you'd have multiple entries and build a proper tree
        root = keccak256(abi.encodePacked(leaf, bytes32(0)));
        
        // The proof for our simple tree
        proof = new bytes32[](1);
        proof[0] = bytes32(0); // This will trigger the fallback in the contract
        
        return (root, proof);
    }
    
    /**
     * @notice Helper to generate simple Merkle root and proofs for royalty distributions
     */
    function generateRoyaltyMerkleTree(
        address minter,
        address creatorAddr,
        uint256 minterAmount,
        uint256 creatorAmount
    ) internal pure returns (
        bytes32 root,
        bytes32[][] memory proofs
    ) {
        // Create leaves
        bytes32 minterLeaf = keccak256(abi.encodePacked(minter, minterAmount));
        bytes32 creatorLeaf = keccak256(abi.encodePacked(creatorAddr, creatorAmount));
        
        // Create root
        root = keccak256(abi.encodePacked(minterLeaf, creatorLeaf));
        
        // Create proofs
        proofs = new bytes32[][](2);
        
        proofs[0] = new bytes32[](1);
        proofs[0][0] = creatorLeaf; // Proof for minter is creator's leaf
        
        proofs[1] = new bytes32[](1);
        proofs[1][0] = minterLeaf; // Proof for creator is minter's leaf
        
        return (root, proofs);
    }
    
    /**
     * @notice End-to-end test covering the full deployment and lifecycle
     */
    function testFullDeploymentAndLifecycle() public {
        // =====================================================================
        // STEP 1: DEPLOYMENT 
        // =====================================================================
        vm.startPrank(deployer);
        
        // Deploy the distributor
        distributor = new CentralizedRoyaltyDistributor();
        console.log("Deployed CentralizedRoyaltyDistributor at:", address(distributor));
        
        // Grant service role to the service account
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        
        // Deploy the NFT contract with the distributor address
        nft = new DiamondGenesisPass(address(distributor), ROYALTY_FEE, creator);
        console.log("Deployed DiamondGenesisPass at:", address(nft));
        
        // Set base URI
        nft.setBaseURI("https://api.example.com/metadata/");
        
        // Set suffix (e.g., ".json")
        nft.setSuffixURI(".json");
        
        vm.stopPrank();
        
        // Verify the NFT contract was registered with the distributor
        assertTrue(distributor.isCollectionRegistered(address(nft)), "NFT should be registered with distributor");
        
        // =====================================================================
        // STEP 2: TEST INITIAL STATE
        // =====================================================================
        
        // Initially public mint should be inactive
        vm.prank(publicMinter);
        vm.expectRevert(DiamondGenesisPass.PublicMintNotActive.selector);
        nft.mint{value: PUBLIC_MINT_PRICE}(publicMinter);
        
        // Owner should be able to mint
        vm.prank(deployer);
        nft.mintOwner(deployer);
        
        // Verify ownership and token URI
        assertEq(nft.ownerOf(1), deployer);
        assertEq(nft.tokenURI(1), "https://api.example.com/metadata/1.json");
        
        // Also verify minter was recorded in distributor
        assertEq(distributor.getMinter(address(nft), 1), deployer);
        
        // Without merkle root, whitelisted users cannot mint
        vm.prank(whitelistedUser);
        vm.expectRevert(DiamondGenesisPass.MerkleRootNotSet.selector);
        nft.whitelistMint{value: PUBLIC_MINT_PRICE}(1, new bytes32[](0));
        
        // =====================================================================
        // STEP 3: SETUP FOR WHITELIST MINTING
        // =====================================================================
        
        // Create merkle tree for whitelist
        (merkleRoot, ) = createSimpleMerkleTree(whitelistedUser, 1);
        
        // Set merkle root
        vm.prank(deployer);
        nft.setMerkleRoot(merkleRoot);
        
        // Verify merkle root was set
        assertEq(nft.getMerkleRoot(), merkleRoot);
        
        // =====================================================================
        // STEP 4: WHITELIST MINTING
        // =====================================================================
        
        // Get proof for whitelisted user
        (, bytes32[] memory proof) = createSimpleMerkleTree(whitelistedUser, 1);
        
        // Mint with whitelist
        vm.prank(whitelistedUser);
        nft.whitelistMint{value: PUBLIC_MINT_PRICE}(1, proof);
        
        // Verify token was minted
        assertEq(nft.ownerOf(2), whitelistedUser);
        assertEq(nft.totalSupply(), 2);
        
        // Verify minter was recorded in distributor
        assertEq(distributor.getMinter(address(nft), 2), whitelistedUser);
        
        // Try to mint again with same address (should fail)
        vm.prank(whitelistedUser);
        vm.expectRevert(DiamondGenesisPass.AddressAlreadyClaimed.selector);
        nft.whitelistMint{value: PUBLIC_MINT_PRICE}(1, proof);
        
        // =====================================================================
        // STEP 5: PUBLIC MINTING
        // =====================================================================
        
        // Enable public minting
        vm.prank(deployer);
        nft.setPublicMintActive(true);
        
        // Mint as a regular user
        vm.prank(publicMinter);
        nft.mint{value: PUBLIC_MINT_PRICE}(publicMinter);
        
        // Verify token ownership
        assertEq(nft.ownerOf(3), publicMinter);
        assertEq(nft.totalSupply(), 3);
        
        // =====================================================================
        // STEP 6: SECONDARY SALES & ROYALTIES
        // =====================================================================
        
        // Secondary sale: public minter sells token to buyer
        vm.prank(publicMinter);
        nft.approve(buyer, 3);
        
        vm.prank(publicMinter);
        nft.transferFrom(publicMinter, buyer, 3);
        
        // Verify new owner
        assertEq(nft.ownerOf(3), buyer);
        
        // Record sale for analytics
        vm.prank(service);
        nft.recordSale(3, SALE_PRICE);
        
        // Service account updates royalty data
        uint256[] memory tokenIds = new uint256[](1);
        address[] memory minters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);
        
        tokenIds[0] = 3;
        minters[0] = publicMinter; // Original minter
        salePrices[0] = SALE_PRICE;
        txHashes[0] = keccak256(abi.encodePacked("sale1"));
        
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            minters,
            salePrices,
            txHashes
        );
        
        // Simulate marketplace sending royalty payment to distributor
        uint256 royaltyAmount = (SALE_PRICE * ROYALTY_FEE) / 10000;
        address marketplace = address(0x789);
        vm.deal(marketplace, royaltyAmount);
        vm.prank(marketplace);
        distributor.addCollectionRoyalties{value: royaltyAmount}(address(nft));
        
        // Verify royalty pool was updated
        assertEq(distributor.getCollectionRoyalties(address(nft)), royaltyAmount);
        assertEq(distributor.totalAccrued(), royaltyAmount);
        
        // =====================================================================
        // STEP 7: ROYALTY DISTRIBUTION & CLAIMS
        // =====================================================================
        
        // Calculate expected shares
        uint256 minterRoyalty = (royaltyAmount * MINTER_SHARES) / 10000;
        uint256 creatorRoyalty = (royaltyAmount * CREATOR_SHARES) / 10000;
        
        // Create merkle tree for royalty distribution
        (bytes32 royaltyRoot, bytes32[][] memory royaltyProofs) = generateRoyaltyMerkleTree(
            publicMinter,
            creator,
            minterRoyalty,
            creatorRoyalty
        );
        
        // Submit the royalty merkle root
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), royaltyRoot, royaltyAmount);
        
        // Verify merkle root was set
        assertEq(distributor.getActiveMerkleRoot(address(nft)), royaltyRoot);
        
        // Minter claims their royalty share
        uint256 minterBalanceBefore = publicMinter.balance;
        vm.prank(publicMinter);
        distributor.claimRoyaltiesMerkle(address(nft), publicMinter, minterRoyalty, royaltyProofs[0]);
        
        // Verify minter got paid
        assertEq(publicMinter.balance - minterBalanceBefore, minterRoyalty);
        
        // Creator claims their royalty share
        uint256 creatorBalanceBefore = creator.balance;
        vm.prank(creator);
        distributor.claimRoyaltiesMerkle(address(nft), creator, creatorRoyalty, royaltyProofs[1]);
        
        // Verify creator got paid
        assertEq(creator.balance - creatorBalanceBefore, creatorRoyalty);
        
        // Verify analytics
        assertEq(distributor.totalAccrued(), royaltyAmount);
        assertEq(distributor.totalClaimed(), royaltyAmount);
        assertEq(distributor.totalUnclaimed(), 0);
        
        // =====================================================================
        // STEP 8: VERIFY TOKEN ROYALTY DATA
        // =====================================================================
        
        // Check token royalty data in distributor
        (
            address storedMinter,
            address currentOwner,
            uint256 transactionCount,
            uint256 totalVolume,
            uint256 minterRoyaltyEarned,
            uint256 creatorRoyaltyEarned
        ) = distributor.getTokenRoyaltyData(address(nft), 3);
        
        assertEq(storedMinter, publicMinter);
        assertEq(currentOwner, buyer);
        assertEq(transactionCount, 1);
        assertEq(totalVolume, SALE_PRICE);
        
        // Calculate expected royalties
        uint256 expectedMinterRoyalty = (royaltyAmount * MINTER_SHARES) / 10000;
        uint256 expectedCreatorRoyalty = (royaltyAmount * CREATOR_SHARES) / 10000;
        
        assertEq(minterRoyaltyEarned, expectedMinterRoyalty);
        assertEq(creatorRoyaltyEarned, expectedCreatorRoyalty);
        
        // =====================================================================
        // STEP 9: CHECK ROYALTY INFO VIA ERC2981
        // =====================================================================
        
        // Check royalty info via the ERC2981 interface
        (address receiver, uint256 royaltyPayment) = IERC2981(address(nft)).royaltyInfo(3, SALE_PRICE);
        
        // Verify correct royalty info
        assertEq(receiver, address(distributor));
        assertEq(royaltyPayment, royaltyAmount);
        
        console.log("Full deployment and lifecycle test completed successfully!");
    }
} 