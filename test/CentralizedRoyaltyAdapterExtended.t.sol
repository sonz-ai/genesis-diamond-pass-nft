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
        assertEq(nft.minterOf(1), user1);
        
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
        assertEq(nft.minterOf(1), user2);
        
        // For minter status trades, 100% of royalty goes to contract owner (admin)
        // No royalty split for minter status trades
        assertEq(address(admin).balance, adminBalanceBefore + 0.3 ether);
        assertEq(address(user1).balance, minterBalanceBefore); // Original minter doesn't get paid
        
        // Verify token ownership remains unchanged
        assertEq(nft.ownerOf(1), user1);
    }
    
    /* ───────── token bidding system ───────── */
    function testTokenBiddingSystem() public {
        // Mint a token for user1
        vm.prank(admin);
        nft.mintOwner(user1);
        
        // User2 places a bid for token ID 1
        vm.prank(user2);
        nft.placeTokenBid{value: 0.5 ether}(1, false);
        
        // Check that the bid was registered
        (address bidder, uint256 bidAmount,) = nft.getHighestTokenBid(1, false);
        assertEq(bidder, user2);
        assertEq(bidAmount, 0.5 ether);
        
        // Another user places a higher bid
        address user3 = address(0x3333);
        vm.deal(user3, 1 ether);
        vm.prank(user3);
        nft.placeTokenBid{value: 0.6 ether}(1, false);
        
        // Check that the new highest bid was updated
        (bidder, bidAmount,) = nft.getHighestTokenBid(1, false);
        assertEq(bidder, user3);
        assertEq(bidAmount, 0.6 ether);
        
        // User2 withdraws their outbid amount
        uint256 balanceBefore = address(user2).balance;
        vm.prank(user2);
        nft.withdrawTokenBid(1, false);
        assertEq(address(user2).balance, balanceBefore + 0.5 ether);
        
        // Token owner accepts the highest bid
        uint256 ownerBalanceBefore = address(user1).balance;
        uint256 royaltyAmount = (0.6 ether * 750) / 10_000; // 7.5% of 0.6 ETH
        
        vm.prank(user1);
        nft.acceptHighestTokenBid(1);
        
        // Check token ownership changed
        assertEq(nft.ownerOf(1), user3);
        
        // Calculate royalty shares
        uint256 creatorRoyalty = (royaltyAmount * 8000) / 10_000; // 80% of royalties
        uint256 minterRoyalty = (royaltyAmount * 2000) / 10_000; // 20% of royalties
        
        // Check seller received payment minus royalties
        assertEq(address(user1).balance, ownerBalanceBefore + 0.6 ether - royaltyAmount);
        
        // Verify royalty distribution in the distributor
        (,, uint256 txCount, uint256 volume, uint256 minterEarned, uint256 creatorEarned) = 
            distributor.getTokenRoyaltyData(address(nft), 1);
        assertEq(txCount, 1);
        assertEq(volume, 0.6 ether);
        assertEq(minterEarned, minterRoyalty);
        assertEq(creatorEarned, creatorRoyalty);
    }
}