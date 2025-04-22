// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/DiamondGenesisPass.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";

contract RoyaltyAnalyticsTest is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass            pass;

    address internal constant CREATOR = address(0xC0FFEE);
    address internal constant MINTER  = address(0xBEEF);

    function setUp() public {
        vm.deal(address(this), 20 ether);
        vm.deal(MINTER,         10 ether);

        distributor = new CentralizedRoyaltyDistributor();
        pass        = new DiamondGenesisPass(address(distributor), 750, CREATOR);

        pass.mintOwner(MINTER);
    }

    function testAccruedAndClaimedFlow() public {
        uint256 tokenId   = 1;
        uint256 salePrice = 1 ether;
        bytes32 txHash    = keccak256("txHash");

        uint256[] memory tokenIds = new uint256[](1);
        address[] memory tokenMinters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        uint256[] memory timestamps = new uint256[](1);
        bytes32[] memory hashes = new bytes32[](1);

        tokenIds[0]     = tokenId;
        tokenMinters[0] = MINTER;
        salePrices[0]   = salePrice;
        timestamps[0]   = block.timestamp;
        hashes[0]       = txHash;

        distributor.batchUpdateRoyaltyData(
            address(pass),
            tokenIds,
            tokenMinters,
            salePrices,
            hashes
        );

        uint256 royalty = (salePrice * 750) / 10_000;
        
        // Check totalAccrued was updated by batchUpdateRoyaltyData
        assertEq(distributor.totalAccrued(), royalty);
        
        // Fund the distributor
        distributor.addCollectionRoyalties{value: royalty}(address(pass));

        // Calculate shares
        uint256 minterShare = (royalty * 2000) / 10_000;
        uint256 creatorShare = (royalty * 8000) / 10_000;

        // Verify royalty data is captured correctly
        (uint256 minterRoyaltyEarned, uint256 creatorRoyaltyEarned) = 
            distributor.getTokenRoyaltyEarnings(address(pass), tokenId);
        
        assertEq(minterRoyaltyEarned, minterShare);
        assertEq(creatorRoyaltyEarned, creatorShare);

        // Verify that the minter can claim their share 
        // directly after batchUpdateRoyaltyData without calling updateAccruedRoyalties
        assertEq(distributor.getClaimableRoyalties(address(pass), MINTER), minterShare);
        
        // Claim minter share
        vm.prank(MINTER);
        distributor.claimRoyalties(address(pass), minterShare);
        
        // Verify claimed royalties
        assertEq(distributor.totalClaimed(), minterShare);
        assertEq(distributor.getClaimableRoyalties(address(pass), MINTER), 0);
        
        // Verify that creator can claim their share
        assertEq(distributor.getClaimableRoyalties(address(pass), CREATOR), creatorShare);
        
        // Claim creator share
        vm.prank(CREATOR);
        distributor.claimRoyalties(address(pass), creatorShare);
        
        // Verify all royalties are claimed
        assertEq(distributor.totalClaimed(), royalty);
        assertEq(distributor.getClaimableRoyalties(address(pass), CREATOR), 0);
        assertEq(distributor.totalUnclaimed(), 0);
    }
    
    function testUnclaimedRoyalties() public {
        uint256 tokenId   = 1;
        uint256 salePrice = 1 ether;
        bytes32 txHash    = keccak256("txHash");

        // Calculate expected royalty amount
        uint256 royaltyAmount = (salePrice * 750) / 10_000;
        
        // Process a sale through batch update
        uint256[] memory tokenIds = new uint256[](1);
        address[] memory tokenMinters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        bytes32[] memory hashes = new bytes32[](1);

        tokenIds[0]     = tokenId;
        tokenMinters[0] = MINTER;
        salePrices[0]   = salePrice;
        hashes[0]       = txHash;

        distributor.batchUpdateRoyaltyData(
            address(pass),
            tokenIds,
            tokenMinters,
            salePrices,
            hashes
        );
        
        // Check totalAccrued was updated by batchUpdateRoyaltyData
        assertEq(distributor.totalAccrued(), royaltyAmount);
        
        // Add royalties to the collection pool
        distributor.addCollectionRoyalties{value: royaltyAmount}(address(pass));
        
        // Calculate royalty shares
        uint256 minterShare = (royaltyAmount * 2000) / 10_000;
        uint256 creatorShare = (royaltyAmount * 8000) / 10_000;
        
        // Check total unclaimed equals total accrued initially
        assertEq(distributor.totalUnclaimed(), royaltyAmount);
        assertEq(distributor.totalClaimed(), 0);
        
        // Check collection-specific unclaimed amount matches what was added
        assertEq(distributor.collectionUnclaimed(address(pass)), royaltyAmount);
        assertEq(pass.totalUnclaimedRoyalties(), royaltyAmount);
        
        // Verify individual claimable amounts
        assertEq(distributor.getClaimableRoyalties(address(pass), MINTER), minterShare);
        assertEq(distributor.getClaimableRoyalties(address(pass), CREATOR), creatorShare);
        
        // Claim minter's share
        vm.prank(MINTER);
        distributor.claimRoyalties(address(pass), minterShare);
        
        // Check updated unclaimed amounts
        assertEq(distributor.totalUnclaimed(), royaltyAmount - minterShare);
        assertEq(distributor.collectionUnclaimed(address(pass)), royaltyAmount - minterShare);
        assertEq(pass.totalUnclaimedRoyalties(), royaltyAmount - minterShare);
        
        // Verify remaining unclaimed
        assertEq(distributor.getClaimableRoyalties(address(pass), MINTER), 0);
        assertEq(distributor.getClaimableRoyalties(address(pass), CREATOR), creatorShare);
    }
}