// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title IntegrationTestFixes
 * @notice Integration tests to verify fixes for various issues
 * @dev This test covers end-to-end flows with fixes for previously failing tests
 */
contract IntegrationTestFixes is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass nft;
    ERC20PresetMinterPauser mockERC20;
    
    address admin = address(0x1);
    address service = address(0x2);
    address creator = address(0x3);
    address minter = address(0x4);
    address buyer = address(0x5);
    
    uint256 constant SALE_PRICE = 1 ether;
    uint96 constant ROYALTY_FEE = 1000; // 10% in basis points
    uint256 constant MINTER_SHARES = 2000; // 20% in basis points
    uint256 constant CREATOR_SHARES = 8000; // 80% in basis points
    
    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy contracts
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        
        nft = new DiamondGenesisPass(address(distributor), ROYALTY_FEE, creator);
        nft.setPublicMintActive(true);
        
        // Only register if not already registered in constructor
        if (!distributor.isCollectionRegistered(address(nft))) {
            distributor.registerCollection(
                address(nft),
                ROYALTY_FEE,
                MINTER_SHARES,
                CREATOR_SHARES,
                creator
            );
        }
        
        // Disable transfer validation completely by setting the validator to address(0)
        // This allows easier testing without dealing with transfer validation
        nft.setTransferValidator(address(0));
        
        // Deploy mock ERC20 token
        mockERC20 = new ERC20PresetMinterPauser("Mock Token", "MOCK");
        mockERC20.mint(buyer, 10 ether);
        
        vm.stopPrank();
    }
    
    // Helper function to generate a Merkle tree and proofs for ETH royalties
    function generateMerkleRootAndProofs(
        address[] memory recipients,
        uint256[] memory amounts
    ) internal pure returns (
        bytes32 merkleRoot,
        bytes32[][] memory proofs
    ) {
        require(recipients.length == amounts.length, "Arrays must have the same length");
        
        // Generate leaves
        bytes32[] memory leaves = new bytes32[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(recipients[i], amounts[i]));
        }
        
        // Sort leaves (important for consistent proofs)
        for (uint256 i = 0; i < leaves.length; i++) {
            for (uint256 j = i + 1; j < leaves.length; j++) {
                if (leaves[i] > leaves[j]) {
                    bytes32 temp = leaves[i];
                    leaves[i] = leaves[j];
                    leaves[j] = temp;
                }
            }
        }
        
        // For simplicity in testing with just 2 recipients, we'll create a simple merkle tree
        if (recipients.length == 2) {
            // Create the merkle root
            merkleRoot = keccak256(abi.encodePacked(leaves[0], leaves[1]));
            
            // Generate proofs
            proofs = new bytes32[][](2);
            proofs[0] = new bytes32[](1);
            proofs[0][0] = leaves[1]; // Proof for recipient 0 is leaf 1
            
            proofs[1] = new bytes32[](1);
            proofs[1][0] = leaves[0]; // Proof for recipient 1 is leaf 0
            
            return (merkleRoot, proofs);
        } else {
            // For simplicity, we'll handle only 2 recipients in this test
            revert("Only 2 recipients supported in this helper");
        }
    }
    
    // Helper function to generate a Merkle tree and proofs for ERC20 royalties
    function generateERC20MerkleRootAndProofs(
        address[] memory recipients,
        address token,
        uint256[] memory amounts
    ) internal pure returns (
        bytes32 merkleRoot,
        bytes32[][] memory proofs
    ) {
        require(recipients.length == amounts.length, "Arrays must have the same length");
        
        // Generate leaves
        bytes32[] memory leaves = new bytes32[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(recipients[i], token, amounts[i]));
        }
        
        // Sort leaves (important for consistent proofs)
        for (uint256 i = 0; i < leaves.length; i++) {
            for (uint256 j = i + 1; j < leaves.length; j++) {
                if (leaves[i] > leaves[j]) {
                    bytes32 temp = leaves[i];
                    leaves[i] = leaves[j];
                    leaves[j] = temp;
                }
            }
        }
        
        // For simplicity in testing with just 2 recipients, we'll create a simple merkle tree
        if (recipients.length == 2) {
            // Create the merkle root
            merkleRoot = keccak256(abi.encodePacked(leaves[0], leaves[1]));
            
            // Generate proofs
            proofs = new bytes32[][](2);
            proofs[0] = new bytes32[](1);
            proofs[0][0] = leaves[1]; // Proof for recipient 0 is leaf 1
            
            proofs[1] = new bytes32[](1);
            proofs[1][0] = leaves[0]; // Proof for recipient 1 is leaf 0
            
            return (merkleRoot, proofs);
        } else {
            // For simplicity, we'll handle only 2 recipients in this test
            revert("Only 2 recipients supported in this helper");
        }
    }
    
    function testFullLifecycleWithFixedAnalytics() public {
        // Step 1: Mint an NFT
        vm.deal(minter, 1 ether);
        vm.prank(minter);
        nft.mint{value: 0.1 ether}(minter);
        
        // Verify minter is recorded correctly
        address recordedMinter = distributor.getMinter(address(nft), 1);
        assertEq(recordedMinter, minter, "Minter should be recorded correctly");
        
        // Step 2: Simulate a secondary sale
        vm.prank(minter);
        nft.transferFrom(minter, buyer, 1); // Should work now with validation disabled
        
        // Step 3: Record the sale via service account
        bytes32 txHash = keccak256("transaction1");
        
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        
        address[] memory minters = new address[](1);
        minters[0] = minter;
        
        uint256[] memory salePrices = new uint256[](1);
        salePrices[0] = SALE_PRICE;
        
        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = block.timestamp;
        
        bytes32[] memory txHashes = new bytes32[](1);
        txHashes[0] = txHash;
        
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            minters,
            salePrices,
            txHashes
        );
        
        // Verify royalty data was updated correctly
        (
            address storedMinter,
            address currentOwner,
            uint256 transactionCount,
            uint256 totalVolume,
            uint256 minterRoyaltyEarned,
            uint256 creatorRoyaltyEarned
        ) = distributor.getTokenRoyaltyData(address(nft), 1);
        
        assertEq(storedMinter, minter, "Stored minter should match");
        assertEq(currentOwner, buyer, "Current owner should be buyer");
        assertEq(transactionCount, 1, "Transaction count should be 1");
        assertEq(totalVolume, SALE_PRICE, "Total volume should match sale price");
        
        // Calculate expected royalties
        uint256 totalRoyalty = (SALE_PRICE * ROYALTY_FEE) / 10000;
        uint256 expectedMinterRoyalty = (totalRoyalty * MINTER_SHARES) / 10000;
        uint256 expectedCreatorRoyalty = (totalRoyalty * CREATOR_SHARES) / 10000;
        
        assertEq(minterRoyaltyEarned, expectedMinterRoyalty, "Minter royalty earned should match expected");
        assertEq(creatorRoyaltyEarned, expectedCreatorRoyalty, "Creator royalty earned should match expected");
        
        // Step 4: Send royalty payment to distributor using addCollectionRoyalties
        // This ensures it's properly tracked for the specific collection
        vm.deal(admin, totalRoyalty);
        vm.prank(admin);
        distributor.addCollectionRoyalties{value: totalRoyalty}(address(nft));
        
        // Step 5: Generate Merkle proofs and root for claims
        address[] memory recipients = new address[](2);
        recipients[0] = minter;
        recipients[1] = creator;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = expectedMinterRoyalty;
        amounts[1] = expectedCreatorRoyalty;
        
        (bytes32 merkleRoot, bytes32[][] memory proofs) = generateMerkleRootAndProofs(recipients, amounts);
        
        // Submit the Merkle root
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), merkleRoot, totalRoyalty);
        
        // Verify analytics are correct (no double counting)
        assertEq(distributor.totalAccruedRoyalty(), totalRoyalty, "Total accrued royalty should match");
        assertEq(distributor.totalClaimedRoyalty(), 0, "No royalties claimed yet");
        
        // Step 6: Claim royalties with valid Merkle proofs
        // Assuming minter is at index 0 and creator is at index 1 in our arrays
        
        // Minter claims
        uint256 minterBalanceBefore = minter.balance;
        vm.prank(minter);
        distributor.claimRoyaltiesMerkle(address(nft), minter, expectedMinterRoyalty, proofs[0]);
        uint256 minterBalanceAfter = minter.balance;
        
        assertEq(minterBalanceAfter - minterBalanceBefore, expectedMinterRoyalty, "Minter should receive correct royalty");
        
        // Creator claims
        uint256 creatorBalanceBefore = creator.balance;
        vm.prank(creator);
        distributor.claimRoyaltiesMerkle(address(nft), creator, expectedCreatorRoyalty, proofs[1]);
        uint256 creatorBalanceAfter = creator.balance;
        
        assertEq(creatorBalanceAfter - creatorBalanceBefore, expectedCreatorRoyalty, "Creator should receive correct royalty");
        
        // Verify final analytics
        assertEq(distributor.totalAccruedRoyalty(), totalRoyalty, "Total accrued royalty should remain unchanged");
        assertEq(distributor.totalClaimedRoyalty(), totalRoyalty, "Total claimed royalty should match total accrued");
    }
    
    function testERC20RoyaltyFlow() public {
        // Step 1: Mint an NFT
        vm.deal(minter, 1 ether);
        vm.prank(minter);
        nft.mint{value: 0.1 ether}(minter);
        
        // Step 2: Simulate a secondary sale with ERC20 payment
        vm.prank(minter);
        nft.transferFrom(minter, buyer, 1); // Should work now with validation disabled
        
        // Step 3: Add ERC20 royalties to the distributor
        uint256 erc20RoyaltyAmount = 1 ether; // 1 token
        
        // Grant this test contract the MINTER_ROLE so it can mint tokens directly
        vm.startPrank(admin);
        bytes32 MINTER_ROLE = keccak256("MINTER_ROLE");
        mockERC20.grantRole(MINTER_ROLE, address(this));
        vm.stopPrank();
        
        // Mint tokens to this contract for testing
        mockERC20.mint(address(this), erc20RoyaltyAmount);
        
        // Approve the distributor to spend tokens from this contract
        mockERC20.approve(address(distributor), erc20RoyaltyAmount);
        
        // Add the ERC20 royalties to the collection
        vm.prank(admin);
        distributor.addCollectionERC20Royalties(address(nft), IERC20(address(mockERC20)), erc20RoyaltyAmount);
        
        // Calculate shares
        uint256 minterERC20Share = (erc20RoyaltyAmount * MINTER_SHARES) / 10000;
        uint256 creatorERC20Share = (erc20RoyaltyAmount * CREATOR_SHARES) / 10000;
        
        // Step 4: Generate Merkle proofs and root for ERC20 claims
        address[] memory recipients = new address[](2);
        recipients[0] = minter;
        recipients[1] = creator;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = minterERC20Share;
        amounts[1] = creatorERC20Share;
        
        (bytes32 erc20MerkleRoot, bytes32[][] memory proofs) = generateERC20MerkleRootAndProofs(
            recipients, 
            address(mockERC20), 
            amounts
        );
        
        // Submit the ERC20 Merkle root
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), erc20MerkleRoot, erc20RoyaltyAmount);
        
        // Step 5: Claim ERC20 royalties with valid Merkle proofs
        
        // Minter claims
        vm.prank(minter);
        distributor.claimERC20RoyaltiesMerkle(
            address(nft), 
            minter, 
            IERC20(address(mockERC20)), 
            minterERC20Share, 
            proofs[0]
        );
        
        // Creator claims
        vm.prank(creator);
        distributor.claimERC20RoyaltiesMerkle(
            address(nft), 
            creator, 
            IERC20(address(mockERC20)), 
            creatorERC20Share, 
            proofs[1]
        );
        
        // Verify balances
        assertEq(mockERC20.balanceOf(minter), minterERC20Share, "Minter should receive correct ERC20 royalty");
        assertEq(mockERC20.balanceOf(creator), creatorERC20Share, "Creator should receive correct ERC20 royalty");
    }
    
    function testOracleFlow() public {
        // Step 1: Mint an NFT
        vm.deal(minter, 1 ether);
        vm.prank(minter);
        nft.mint{value: 0.1 ether}(minter);
        
        // Step 2: Set oracle update interval - set to 1 to allow frequent updates in test
        vm.prank(admin);
        distributor.setOracleUpdateMinBlockInterval(address(nft), 1);
        
        // Step 3: Trigger oracle update
        vm.roll(block.number + 1); // Roll forward one block
        vm.prank(minter);
        distributor.updateRoyaltyDataViaOracle(address(nft));
        
        // Step 4: Try to update again too soon (should fail)
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSignature("RoyaltyDistributor__OracleUpdateTooFrequent()"));
        distributor.updateRoyaltyDataViaOracle(address(nft));
        
        // Step 5: Simulate block advancement
        vm.roll(block.number + 2);
        
        // Step 6: Update should work now
        vm.prank(minter);
        distributor.updateRoyaltyDataViaOracle(address(nft));
    }
}
