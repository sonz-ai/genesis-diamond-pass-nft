// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

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
    uint256 constant ROYALTY_FEE = 1000; // 10% in basis points
    uint256 constant MINTER_SHARES = 2000; // 20% in basis points
    uint256 constant CREATOR_SHARES = 8000; // 80% in basis points
    
    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy contracts
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        
        nft = new DiamondGenesisPass(address(distributor), ROYALTY_FEE, creator);
        nft.setPublicMintActive(true);
        
        // Deploy mock ERC20 token
        mockERC20 = new ERC20PresetMinterPauser("Mock Token", "MOCK");
        mockERC20.mint(buyer, 10 ether);
        
        vm.stopPrank();
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
        nft.transferFrom(minter, buyer, 1);
        
        // Step 3: Record the sale via service account
        bytes32 txHash = keccak256("transaction1");
        address[] memory collections = new address[](1);
        collections[0] = address(nft);
        
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        
        uint256[] memory salePrices = new uint256[](1);
        salePrices[0] = SALE_PRICE;
        
        bytes32[] memory txHashes = new bytes32[](1);
        txHashes[0] = txHash;
        
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(collections, tokenIds, salePrices, txHashes);
        
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
        
        // Step 4: Send royalty payment to distributor
        vm.deal(address(this), totalRoyalty);
        (bool success, ) = address(distributor).call{value: totalRoyalty}("");
        require(success, "Transfer failed");
        
        // Step 5: Submit Merkle root for claims
        bytes32 merkleRoot = keccak256(abi.encodePacked(
            keccak256(abi.encodePacked(minter, expectedMinterRoyalty)),
            keccak256(abi.encodePacked(creator, expectedCreatorRoyalty))
        ));
        
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), merkleRoot, totalRoyalty);
        
        // Verify analytics are correct (no double counting)
        assertEq(distributor.totalAccruedRoyalty(), totalRoyalty, "Total accrued royalty should match");
        assertEq(distributor.totalClaimedRoyalty(), 0, "No royalties claimed yet");
        
        // Step 6: Claim royalties
        // For simplicity, using empty proofs (would need actual Merkle tree implementation for real proofs)
        bytes32[] memory emptyProof = new bytes32[](0);
        
        // Minter claims
        uint256 minterBalanceBefore = minter.balance;
        vm.prank(minter);
        distributor.claimRoyaltiesMerkle(address(nft), minter, expectedMinterRoyalty, emptyProof);
        uint256 minterBalanceAfter = minter.balance;
        
        assertEq(minterBalanceAfter - minterBalanceBefore, expectedMinterRoyalty, "Minter should receive correct royalty");
        
        // Creator claims
        uint256 creatorBalanceBefore = creator.balance;
        vm.prank(creator);
        distributor.claimRoyaltiesMerkle(address(nft), creator, expectedCreatorRoyalty, emptyProof);
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
        nft.transferFrom(minter, buyer, 1);
        
        // Step 3: Add ERC20 royalties to the distributor
        uint256 erc20RoyaltyAmount = 1 ether; // 1 token
        vm.prank(buyer);
        mockERC20.transfer(address(this), erc20RoyaltyAmount);
        
        vm.prank(address(this));
        mockERC20.approve(address(distributor), erc20RoyaltyAmount);
        
        vm.prank(admin);
        distributor.addCollectionERC20Royalties(address(nft), mockERC20, erc20RoyaltyAmount);
        
        // Step 4: Submit Merkle root for ERC20 claims
        uint256 minterERC20Share = (erc20RoyaltyAmount * MINTER_SHARES) / 10000;
        uint256 creatorERC20Share = (erc20RoyaltyAmount * CREATOR_SHARES) / 10000;
        
        bytes32 erc20MerkleRoot = keccak256(abi.encodePacked(
            keccak256(abi.encodePacked(minter, address(mockERC20), minterERC20Share)),
            keccak256(abi.encodePacked(creator, address(mockERC20), creatorERC20Share))
        ));
        
        vm.prank(service);
        distributor.submitERC20MerkleRoot(address(nft), address(mockERC20), erc20MerkleRoot, erc20RoyaltyAmount);
        
        // Step 5: Claim ERC20 royalties
        bytes32[] memory emptyProof = new bytes32[](0);
        
        // Minter claims
        vm.prank(minter);
        distributor.claimERC20RoyaltiesMerkle(
            address(nft), 
            address(mockERC20), 
            minter, 
            minterERC20Share, 
            emptyProof
        );
        
        // Creator claims
        vm.prank(creator);
        distributor.claimERC20RoyaltiesMerkle(
            address(nft), 
            address(mockERC20), 
            creator, 
            creatorERC20Share, 
            emptyProof
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
        
        // Step 2: Set oracle update interval
        vm.prank(admin);
        distributor.setOracleUpdateMinBlockInterval(address(nft), 10);
        
        // Step 3: Trigger oracle update
        vm.prank(minter);
        distributor.updateRoyaltyDataViaOracle(address(nft), 1);
        
        // Step 4: Try to update again too soon (should fail)
        vm.prank(minter);
        vm.expectRevert();
        distributor.updateRoyaltyDataViaOracle(address(nft), 1);
        
        // Step 5: Simulate block advancement
        vm.roll(block.number + 11);
        
        // Step 6: Update should work now
        vm.prank(minter);
        distributor.updateRoyaltyDataViaOracle(address(nft), 1);
    }
}
