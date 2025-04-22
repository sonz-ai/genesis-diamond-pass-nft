// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/programmable-royalties/CentralizedRoyaltyAdapter.sol";
import "src/DiamondGenesisPass.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";

contract MockRoyaltyAdapter is CentralizedRoyaltyAdapter {
    constructor(address distributor_, uint256 feeNumerator_)
        CentralizedRoyaltyAdapter(distributor_, feeNumerator_) {}
}

contract UnregisteredCollectionAdapter is CentralizedRoyaltyAdapter {
    constructor(address distributor_, uint256 feeNumerator_)
        CentralizedRoyaltyAdapter(distributor_, feeNumerator_) {}

    function forceRevertsOnConfig() public view {
        this.minterShares();
    }
}

contract CentralizedRoyaltyAdapterExtendedTest is Test {
    CentralizedRoyaltyDistributor public distributor;
    DiamondGenesisPass             public nft;
    MockRoyaltyAdapter             public mockAdapter;
    UnregisteredCollectionAdapter  public unregisteredAdapter;

    address public admin    = address(0x1001);
    address public service  = address(0x1002);
    address public creator  = address(0x1003);
    address public user1    = address(0x1111);
    address public user2    = address(0x2222);

    event RoyaltyDistributorSet(address indexed distributor);
    event RoyaltyFeeNumeratorSet(uint256 feeNumerator);

    function setUp() public {
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);

        nft = new DiamondGenesisPass(address(distributor), 750, creator);

        unregisteredAdapter = new UnregisteredCollectionAdapter(address(distributor), 500);
        vm.stopPrank();

        vm.deal(admin, 10 ether);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
    }

    /* ───────── constructor guards ───────── */
    function testConstructorZeroAddressRevert() public {
        vm.expectRevert(
            CentralizedRoyaltyAdapter
                .CentralizedRoyaltyAdapter__DistributorCannotBeZeroAddress
                .selector
        );
        mockAdapter = new MockRoyaltyAdapter(address(0), 500);
    }

    function testConstructorExcessFeeRevert() public {
        vm.expectRevert(
            CentralizedRoyaltyAdapter
                .CentralizedRoyaltyAdapter__RoyaltyFeeWillExceedSalePrice
                .selector
        );
        mockAdapter = new MockRoyaltyAdapter(address(distributor), 15_000);
    }

    function testConstructorWithMaxFee() public {
        mockAdapter = new MockRoyaltyAdapter(address(distributor), 10_000);
        assertEq(mockAdapter.royaltyFeeNumerator(), 10_000);
    }

    function testConstructorEmitsEvents() public {
        vm.expectEmit(true, false, false, true);
        emit RoyaltyDistributorSet(address(distributor));

        vm.expectEmit(false, false, false, true);
        emit RoyaltyFeeNumeratorSet(500);

        mockAdapter = new MockRoyaltyAdapter(address(distributor), 500);
    }

    /* ───────── distributor analytics ───────── */
    function testTokenRoyaltyDataAfterBatchUpdate() public {
        // Mint a token
        vm.prank(admin);
        nft.mintOwner(user1);

        // Prepare minimal test data
        uint256[] memory tokenIds = new uint256[](1);
        address[] memory minters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);

        tokenIds[0] = 1;
        minters[0] = user1;
        salePrices[0] = 1 ether;
        txHashes[0] = keccak256("tx1");

        // Update royalty data
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            minters,
            salePrices,
            txHashes
        );

        // Get minter and token holder
        (address minter, address currentOwner) = distributor.getTokenMinterAndHolder(address(nft), 1);
        assertEq(minter, user1);
        assertEq(currentOwner, user1);
        
        // Get transaction data
        (uint256 transactionCount, uint256 totalVolume) = distributor.getTokenTransactionData(address(nft), 1);
        assertEq(transactionCount, 1);
        assertEq(totalVolume, 1 ether);
        
        // Calculate expected royalties (moved to avoid stack depth issues)
        uint256 royaltyAmount = (1 ether * 750) / 10_000;
        uint256 expectedMinterShare = (royaltyAmount * 2000) / 10_000;
        uint256 expectedCreatorShare = (royaltyAmount * 8000) / 10_000;
        
        // Get royalty earnings
        (uint256 minterRoyaltyEarned, uint256 creatorRoyaltyEarned) = distributor.getTokenRoyaltyEarnings(address(nft), 1);
        assertEq(minterRoyaltyEarned, expectedMinterShare);
        assertEq(creatorRoyaltyEarned, expectedCreatorShare);
    }

    /* ───────── reverts on unregistered collection ───────── */
    function testUnregisteredCollectionCalls() public {
        vm.expectRevert(
            CentralizedRoyaltyDistributor.RoyaltyDistributor__CollectionNotRegistered.selector
        );
        unregisteredAdapter.forceRevertsOnConfig();
    }

    /* ───────── interface support ───────── */
    function testSupportsMultipleInterfaces() public view {
        assertTrue(nft.supportsInterface(type(IERC2981).interfaceId));
        assertTrue(nft.supportsInterface(type(IERC165).interfaceId));

        bytes4 nonSupported = bytes4(keccak256("nonSupportedInterface()"));
        assertFalse(nft.supportsInterface(nonSupported));
    }

    /* ───────── royalty calc edge cases ───────── */
    function testRoyaltyCalculationEdgeCases() public view {
        (address recv, uint256 amt) = nft.royaltyInfo(1, 0);
        assertEq(recv, address(distributor));
        assertEq(amt, 0);

        uint256 bigPrice = 1_000_000 ether;
        (recv, amt) = nft.royaltyInfo(1, bigPrice);
        assertEq(recv, address(distributor));
        assertEq(amt, (bigPrice * 750) / 10_000);

        uint256 tinyPrice = 100;
        (recv, amt) = nft.royaltyInfo(1, tinyPrice);
        assertEq(recv, address(distributor));
        assertEq(amt, (tinyPrice * 750) / 10_000);
    }

    /* ───────── local vs distributor fee ───────── */
    function testLocalVsDistributorRoyaltyFee() public {
        vm.startPrank(admin);
        DiamondGenesisPass newNft = new DiamondGenesisPass(
            address(distributor),
            500,      // local fee 5 %
            creator
        );
        vm.stopPrank();

        // Check royalty info
        (address recv, uint256 amt) = newNft.royaltyInfo(1, 1 ether);
        assertEq(recv, address(distributor));
        assertEq(amt, 0.05 ether); // 5% of 1 ether
        
        // Check fee numerator matches
        assertEq(newNft.distributorRoyaltyFeeNumerator(), 500);
    }

    /* ───────── gas snapshots (non‑assert) ───────── */
    function testGasUsageForViewFunctions() public {
        vm.prank(admin);
        nft.mintOwner(user1);

        // Create smaller arrays to reduce stack pressure
        uint256[] memory ids  = new uint256[](1);
        address[] memory mtrs = new address[](1);
        uint256[] memory prc  = new uint256[](1);
        bytes32[] memory txh  = new bytes32[](1);

        ids[0]  = 1;
        mtrs[0] = user1;
        prc[0]  = 1 ether;
        txh[0]  = keccak256(abi.encodePacked("tx0"));

        vm.prank(service);
        distributor.batchUpdateRoyaltyData(address(nft), ids, mtrs, prc, txh);

        // Measure gas for royaltyInfo
        uint256 start = gasleft();
        nft.royaltyInfo(1, 1 ether);
        console.log("Gas usage - royaltyInfo:", start - gasleft());

        // Measure gas for getTokenMinterAndHolder
        start = gasleft();
        distributor.getTokenMinterAndHolder(address(nft), 1);
        console.log("Gas usage - getTokenMinterAndHolder:", start - gasleft());

        // Measure gas for minterOf
        start = gasleft();
        nft.minterOf(1);
        console.log("Gas usage - minterOf:", start - gasleft());
    }

    /* ───────── non‑existent token data ───────── */
    function testTokenRoyaltyDataForNonexistentToken() public view {
        // Check minter and token holder
        (address minter, address currentOwner) = distributor.getTokenMinterAndHolder(address(nft), 999);
        assertEq(minter, address(0));
        assertEq(currentOwner, address(0));
        
        // Check transaction data
        (uint256 count, uint256 vol) = distributor.getTokenTransactionData(address(nft), 999);
        assertEq(count, 0);
        assertEq(vol, 0);
        
        // Check royalty earnings
        (uint256 mEarned, uint256 cEarned) = distributor.getTokenRoyaltyEarnings(address(nft), 999);
        assertEq(mEarned, 0);
        assertEq(cEarned, 0);
    }

    /* ───────── minter status bidding system ───────── */
    function testMinterStatusBidding() public {
        // Mint a token for user1
        vm.prank(admin);
        nft.mintOwner(user1);
        
        // Verify initial minter
        assertEq(nft.getMinterOf(1), user1);
        
        // User2 places a bid for minter status of token 1
        vm.prank(user2);
        nft.placeBid{value: 0.3 ether}(1, false);
        
        // Check bid was registered
        (address bidder, uint256 bidAmount,) = nft.getHighestBid(1, false);
        assertEq(bidder, user2);
        assertEq(bidAmount, 0.3 ether);
        
        // Current minter accepts the bid
        uint256 minterBalanceBefore = address(user1).balance;
        uint256 adminBalanceBefore = address(admin).balance;
        
        vm.prank(user1);
        nft.acceptHighestBid(1);
        
        // Verify minter status changed
        assertEq(nft.getMinterOf(1), user2);
        
        // For minter status trades, 100% of royalty goes to contract owner (admin)
        // No royalty split for minter status trades
        assertEq(address(admin).balance, adminBalanceBefore + 0.3 ether);
        assertEq(address(user1).balance, minterBalanceBefore); // Original minter doesn't get paid
        
        // Verify token ownership remains unchanged
        assertEq(nft.ownerOf(1), user1);
    }
    
    /* ───────── direct accrual system test (simplified) ───────── */
    function testDirectAccrualSystem() public {
        // Mint a token to user1
        vm.prank(admin);
        nft.mintOwner(user1);
        
        // First add ETH to the distributor for the collection
        vm.deal(address(this), 0.075 ether);
        distributor.addCollectionRoyalties{value: 0.075 ether}(address(nft));
        
        // Verify the collection has received the royalties
        assertEq(distributor.getCollectionRoyalties(address(nft)), 0.075 ether, "Collection should have 0.075 ETH in royalties");
        
        // Simulate a sale by directly updating accrued royalties
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        
        recipients[0] = user1; // minter
        recipients[1] = creator; // creator
        
        // 20% of 0.075 = 0.015 ETH to minter (user1)
        // 80% of 0.075 = 0.06 ETH to creator
        amounts[0] = 0.015 ether;
        amounts[1] = 0.06 ether;
        
        // Use simple approach without transaction hashes to avoid deduplication issues
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // Check claimable royalties
        uint256 user1Claimable = distributor.getClaimableRoyalties(address(nft), user1);
        uint256 creatorClaimable = distributor.getClaimableRoyalties(address(nft), creator);
        
        // Verify the correct royalty split was applied
        assertEq(user1Claimable, 0.015 ether, "Minter should have 20% of royalties claimable");
        assertEq(creatorClaimable, 0.06 ether, "Creator should have 80% of royalties claimable");
        
        // Verify only 0.075 ETH in total is accrued (no double counting)
        assertEq(distributor.totalAccrued(), 0.075 ether, "Total accrued should be exactly 0.075 ETH");
        
        // Complete the test by claiming
        vm.prank(user1);
        distributor.claimRoyalties(address(nft), user1Claimable);
        
        vm.prank(creator);
        distributor.claimRoyalties(address(nft), creatorClaimable);
        
        // Verify all claimed
        assertEq(distributor.getClaimableRoyalties(address(nft), user1), 0, "User1 should have 0 after claiming");
        assertEq(distributor.getClaimableRoyalties(address(nft), creator), 0, "Creator should have 0 after claiming");
        assertEq(distributor.totalClaimed(), 0.075 ether, "Total claimed should match total accrued");
    }

    /* ───────── royalty distribution test (simplified) ───────── */
    function testRoyaltyDistribution() public {
        // Mint a token to user1
        vm.prank(admin);
        nft.mintOwner(user1);
        
        // Simulate a royalty payment to the distributor
        uint256 royaltyAmount = 0.075 ether;
        vm.deal(address(this), royaltyAmount);
        distributor.addCollectionRoyalties{value: royaltyAmount}(address(nft));
        
        // Verify collection royalties were recorded
        assertEq(distributor.getCollectionRoyalties(address(nft)), royaltyAmount);
        
        // Calculate expected shares
        uint256 minterShare = (royaltyAmount * 2000) / 10000;  // 20% to minter
        uint256 creatorShare = (royaltyAmount * 8000) / 10000;  // 80% to creator
        
        // Update accrued royalties based on the sale
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        
        recipients[0] = user1; // minter
        recipients[1] = creator; // creator
        amounts[0] = minterShare;
        amounts[1] = creatorShare;
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // Check claimable royalties
        assertEq(distributor.getClaimableRoyalties(address(nft), user1), minterShare);
        assertEq(distributor.getClaimableRoyalties(address(nft), creator), creatorShare);
        
        // Claim royalties
        uint256 user1BalanceBefore = address(user1).balance;
        uint256 creatorBalanceBefore = address(creator).balance;
        
        vm.prank(user1);
        distributor.claimRoyalties(address(nft), minterShare);
        
        vm.prank(creator);
        distributor.claimRoyalties(address(nft), creatorShare);
        
        // Verify balances increased correctly
        assertEq(address(user1).balance, user1BalanceBefore + minterShare);
        assertEq(address(creator).balance, creatorBalanceBefore + creatorShare);
        
        // Verify royalties are now claimed
        assertEq(distributor.getClaimableRoyalties(address(nft), user1), 0);
        assertEq(distributor.getClaimableRoyalties(address(nft), creator), 0);
    }

    /* ───────── test royalty tracking for burned tokens ───────── */
    function testRoyaltyTrackingForBurnedTokens() public {
        // Mint a token to user1
        vm.prank(admin);
        nft.mintOwner(user1);
        
        // Verify user1 is the minter
        assertEq(nft.getMinterOf(1), user1);
        
        // Simulate a sale by recording royalty data
        uint256[] memory tokenIds = new uint256[](1);
        address[] memory minters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);
        
        tokenIds[0] = 1;
        minters[0] = user1;
        salePrices[0] = 1 ether;
        txHashes[0] = keccak256("tx1");
        
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(address(nft), tokenIds, minters, salePrices, txHashes);
        
        // Burn the token
        vm.prank(admin);
        nft.burn(1);
        
        // Verify minter info is still preserved in the distributor
        assertEq(distributor.getMinter(address(nft), 1), user1);
        
        // Verify royalty earnings are still tracked
        (uint256 minterRoyaltyEarned, uint256 creatorRoyaltyEarned) = distributor.getTokenRoyaltyEarnings(address(nft), 1);
        
        // Calculate expected royalties
        uint256 royaltyAmount = (1 ether * 750) / 10_000;
        uint256 expectedMinterShare = (royaltyAmount * 2000) / 10_000;
        uint256 expectedCreatorShare = (royaltyAmount * 8000) / 10_000;
        
        assertEq(minterRoyaltyEarned, expectedMinterShare);
        assertEq(creatorRoyaltyEarned, expectedCreatorShare);
    }

    /* ───────── royalty recipient update ───────── */
    function testRoyaltyRecipientUpdate() public {
        // Get the initial creator
        address initialCreator = creator;
        (,,, address creatorFromDistributor) = distributor.getCollectionConfig(address(nft));
        assertEq(creatorFromDistributor, initialCreator);
        
        // Create a new recipient address
        address newRecipient = address(0x4444);
        
        // Update the royalty recipient
        vm.prank(admin);
        nft.setRoyaltyRecipient(newRecipient);
        
        // Verify update was successful
        (,,, creatorFromDistributor) = distributor.getCollectionConfig(address(nft));
        assertEq(creatorFromDistributor, newRecipient);
        assertEq(nft.creator(), newRecipient);
        
        // Test the legacy function as well
        address anotherRecipient = address(0x5555);
        vm.prank(admin);
        nft.updateCreatorAddress(anotherRecipient);
        
        // Verify update was successful
        (,,, creatorFromDistributor) = distributor.getCollectionConfig(address(nft));
        assertEq(creatorFromDistributor, anotherRecipient);
        assertEq(nft.creator(), anotherRecipient);
    }

    /** 
     * @notice Test complex minter status bidding scenarios
     * @dev This test addresses collection-wide bids and token-specific bids
     */
    function testComplexMinterStatusBidding() public {
        // Mint tokens for user1 as initial minter
        vm.startPrank(admin);
        nft.mintOwner(user1); // Token 1
        nft.mintOwner(user1); // Token 2
        vm.stopPrank();
        
        // Verify user1 is initial minter of both tokens
        assertEq(nft.getMinterOf(1), user1);
        assertEq(nft.getMinterOf(2), user1);
        
        // User2 places a collection-wide bid
        vm.prank(user2);
        nft.placeBid{value: 0.4 ether}(0, true); // Collection-wide bid
        
        // User3 places a token-specific bid for token 1, but lower than user2's collection bid
        address user3 = address(0x3333);
        vm.deal(user3, 1 ether);
        vm.prank(user3);
        nft.placeBid{value: 0.3 ether}(1, false); // Token-specific bid
        
        // Accept highest bid for token 1 (should be user2's collection-wide bid)
        uint256 adminBalanceBefore = address(admin).balance;
        vm.prank(user1);
        nft.acceptHighestBid(1);
        
        // Verify minter status changed to user2 (who had the higher collection-wide bid)
        assertEq(nft.getMinterOf(1), user2);
        assertEq(address(admin).balance, adminBalanceBefore + 0.4 ether);
        
        // Now user3 places a higher token-specific bid for token 2
        vm.prank(user3);
        nft.placeBid{value: 0.5 ether}(2, false);
        
        // Accept highest bid for token 2 (should be user3's token-specific bid)
        adminBalanceBefore = address(admin).balance;
        vm.prank(user1);
        nft.acceptHighestBid(2);
        
        // Verify minter status changed to user3 (who had the higher token-specific bid)
        assertEq(nft.getMinterOf(2), user3);
        assertEq(address(admin).balance, adminBalanceBefore + 0.5 ether);
    }

    /**
     * @notice Test transaction hash deduplication in royalty updates
     * @dev Ensures the same transaction hash can't be processed multiple times
     */
    function testTransactionHashDeduplication() public {
        // Mint a token to user1
        vm.prank(admin);
        nft.mintOwner(user1);
        
        // Add ETH to the distributor
        vm.deal(address(distributor), 0.075 ether);
        vm.deal(address(this), 0.075 ether);
        distributor.addCollectionRoyalties{value: 0.075 ether}(address(nft));
        
        // Create a transaction hash
        bytes32 txHash = keccak256("tx1");
        
        // First update with the transaction hash
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        bytes32[] memory txHashes = new bytes32[](2);
        
        recipients[0] = user1;
        recipients[1] = creator;
        amounts[0] = 0.015 ether;
        amounts[1] = 0.06 ether;
        txHashes[0] = txHash;
        txHashes[1] = txHash;
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts, txHashes);
        
        // Check initial accrued royalties
        uint256 initialUser1Accrued = distributor.getClaimableRoyalties(address(nft), user1);
        uint256 initialCreatorAccrued = distributor.getClaimableRoyalties(address(nft), creator);
        
        // Try to update again with the same transaction hash
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts, txHashes);
        
        // Verify royalties were not double-counted
        uint256 finalUser1Accrued = distributor.getClaimableRoyalties(address(nft), user1);
        uint256 finalCreatorAccrued = distributor.getClaimableRoyalties(address(nft), creator);
        
        assertEq(initialUser1Accrued, finalUser1Accrued, "User1 royalties should not increase for duplicate transaction");
        assertEq(initialCreatorAccrued, finalCreatorAccrued, "Creator royalties should not increase for duplicate transaction");
    }

    // Helper functions to wrap single values into arrays
    function _wrapUint(uint256 value) internal pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = value;
        return array;
    }
    
    function _wrapAddress(address value) internal pure returns (address[] memory) {
        address[] memory array = new address[](1);
        array[0] = value;
        return array;
    }
    
    function _wrapBytes32(bytes32 value) internal pure returns (bytes32[] memory) {
        bytes32[] memory array = new bytes32[](1);
        array[0] = value;
        return array;
    }
}