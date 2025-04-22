// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "src/DiamondGenesisPass.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";

contract BidMarketplaceTest is Test {
    CentralizedRoyaltyDistributor public distributor;
    DiamondGenesisPass public nft;

    address public admin    = address(0x1001);
    address public service  = address(0x1002);
    address public creator  = address(0x1003);
    address public minter   = address(0xBEEF);
    address public bidderA  = address(0xAAA1);
    address public bidderB  = address(0xBBB1);

    function setUp() public {
        // Setup accounts with ETH
        vm.deal(admin,   10 ether);
        vm.deal(service, 10 ether);
        vm.deal(creator,  1 ether);
        vm.deal(minter,   1 ether);
        vm.deal(bidderA,  5 ether);
        vm.deal(bidderB,  5 ether);

        // Deploy contracts
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        
        // Grant service role to service account
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        
        nft = new DiamondGenesisPass(address(distributor), 750, creator);
        
        // Grant service role to service account on NFT contract as well
        nft.grantRole(nft.SERVICE_ACCOUNT_ROLE(), service);
        
        // Disable the transfer validator to allow transfers
        nft.setTransferValidator(address(0));
        
        // Mint a token to the minter
        nft.mintOwner(minter);
        vm.stopPrank();
        
        // Verify initial minter status
        assertEq(nft.getMinterOf(1), minter);
    }

    function testBidFlow() public {
        // BidderA places a bid for minter status on token 1
        vm.prank(bidderA);
        nft.placeBid{value: 1 ether}(1, false);

        // BidderB places a higher bid
        vm.prank(bidderB);
        nft.placeBid{value: 2 ether}(1, false);

        // Get the highest bid
        (address highestBidder, uint256 highestAmount,) = nft.getHighestBid(1, false);
        assertEq(highestBidder, bidderB);
        assertEq(highestAmount, 2 ether);

        // Current minter accepts the highest bid
        uint256 adminBalanceBefore = admin.balance;
        
        vm.prank(minter);
        nft.acceptHighestBid(1);

        // Verify minter status changed
        assertEq(nft.getMinterOf(1), bidderB);
        
        // Verify admin received payment (100% goes to owner according to design)
        assertEq(admin.balance, adminBalanceBefore + 2 ether);
    }
    
    function testTokenBidSystem() public {
        console.log("Starting simplified token bid system test");
        
        // Verify token owner and minter at start
        assertEq(nft.ownerOf(1), minter);
        assertEq(nft.getMinterOf(1), minter);
        
        // Place a bid
        vm.prank(bidderA);
        nft.placeTokenBid{value: 1 ether}(1, false);
        
        // Verify bid was recorded correctly
        (address highestBidder, uint256 highestAmount,) = nft.getHighestTokenBid(1, false);
        assertEq(highestBidder, bidderA);
        assertEq(highestAmount, 1 ether);

        // Calculate expected royalty
        uint256 royaltyAmount = (1 ether * 750) / 10_000; // 7.5% of 1 ETH
        // Note: Not using sellerProceeds in this simplified test
        
        // Verify bid withdrawal works
        uint256 balanceBefore = bidderA.balance;
        vm.prank(bidderA);
        nft.withdrawTokenBid(1, false);
        assertEq(bidderA.balance, balanceBefore + 1 ether);
        
        // Verify bid is gone after withdrawal
        (highestBidder, highestAmount,) = nft.getHighestTokenBid(1, false);
        assertEq(highestBidder, address(0));
        assertEq(highestAmount, 0);
        
        console.log("Token bid system test successful");
    }
    
    function testBidWithdrawal() public {
        // BidderA places a bid
        vm.prank(bidderA);
        nft.placeBid{value: 1 ether}(1, false);
        
        // Record balance before withdrawal
        uint256 balanceBefore = bidderA.balance;
        
        // Withdraw the bid
        vm.prank(bidderA);
        nft.withdrawBid(1, false);
        
        // Verify bidder received funds back
        assertEq(bidderA.balance, balanceBefore + 1 ether);
    }
    
    function testTokenBidWithdrawal() public {
        // BidderA places a token bid
        vm.prank(bidderA);
        nft.placeTokenBid{value: 1 ether}(1, false);
        
        // Record balance before withdrawal
        uint256 balanceBefore = bidderA.balance;
        
        // Withdraw the bid
        vm.prank(bidderA);
        nft.withdrawTokenBid(1, false);
        
        // Verify bidder received funds back
        assertEq(bidderA.balance, balanceBefore + 1 ether);
    }
    
    function testCollectionWideBid() public {
        // BidderA places a collection-wide bid
        vm.prank(bidderA);
        nft.placeBid{value: 1.5 ether}(0, true);
        
        // BidderB places a token-specific bid, but lower
        vm.prank(bidderB);
        nft.placeBid{value: 1 ether}(1, false);
        
        // Minter accepts highest bid (should be collection-wide)
        vm.prank(minter);
        nft.acceptHighestBid(1);
        
        // Verify bidderA became the minter
        assertEq(nft.getMinterOf(1), bidderA);
    }
    
    /**
     * @notice Test that specifically focuses on token ownership transfer
     */
    function testTokenOwnershipTransfer() public {
        // Verify initial token ownership
        assertEq(nft.ownerOf(1), minter);
        
        // Set approval for all to avoid approval issues
        vm.prank(minter);
        nft.setApprovalForAll(address(this), true);
        
        // Transfer token from minter to bidderA using transferFrom
        nft.transferFrom(minter, bidderA, 1);
        
        // Verify ownership transferred correctly
        assertEq(nft.ownerOf(1), bidderA);
        
        // Verify minter status remains unchanged
        assertEq(nft.getMinterOf(1), minter);
    }

    /**
     * @notice Basic test for token bid acceptance
     */
    function testAcceptHighestTokenBid() public {
        console.log("Starting testAcceptHighestTokenBid");
        
        // Setup bidder to place a token bid
        vm.deal(bidderA, 5 ether);
        
        // Record initial balances
        uint256 minterBalanceBefore = minter.balance;
        uint256 distributorBalanceBefore = address(distributor).balance;
        
        // Place a token bid
        vm.prank(bidderA);
        nft.placeTokenBid{value: 1 ether}(1, false);
        console.log("Bid placed by bidderA for 1 ETH");
        
        // Verify bid was placed
        (address highestBidder, uint256 highestAmount,) = nft.getHighestTokenBid(1, false);
        assertEq(highestBidder, bidderA);
        assertEq(highestAmount, 1 ether);
        console.log("Verified bid is correctly recorded");
        
        // Verify minter owns the token before acceptance
        assertEq(nft.ownerOf(1), minter);
        console.log("Token owner before acceptance:", minter);
        
        // Setup approval
        vm.startPrank(minter);
        nft.approve(address(nft), 1);
        vm.stopPrank();
        
        // Calculate expected royalty
        uint256 salePrice = 1 ether;
        uint256 royaltyAmount = (salePrice * 750) / 10_000; // 7.5% of 1 ETH
        uint256 sellerProceeds = salePrice - royaltyAmount;
        
        // Accept the bid
        vm.prank(minter);
        nft.acceptHighestTokenBid(1);
        console.log("Bid acceptance successful");
        
        // Verify token ownership transferred
        address newOwner = nft.ownerOf(1);
        console.log("New token owner:", newOwner);
        assertEq(newOwner, bidderA, "Token ownership should transfer to bidder");
        
        // Verify royalty sent to distributor
        assertEq(address(distributor).balance, distributorBalanceBefore + royaltyAmount, "Royalty should be sent to distributor");
        
        // Verify seller received proceeds
        assertEq(minter.balance, minterBalanceBefore + sellerProceeds, "Seller should receive proceeds");
        
        // Calculate expected royalty shares
        uint256 minterShare = (royaltyAmount * 2000) / 10_000; // 20% of royalties
        uint256 creatorShare = (royaltyAmount * 8000) / 10_000; // 80% of royalties
        
        // Simulate off-chain service tracking this sale
        bytes32 txHash = keccak256(abi.encodePacked("token_sale_1"));
        
        // Process the sale in the distributor system
        vm.startPrank(service);
        
        // 1. Register the sale details 
        uint256[] memory tokenIds = new uint256[](1);
        address[] memory minters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);
        
        tokenIds[0] = 1;
        minters[0] = minter; // Original minter
        salePrices[0] = salePrice;
        txHashes[0] = txHash;
        
        distributor.batchUpdateRoyaltyData(address(nft), tokenIds, minters, salePrices, txHashes);
        
        // 2. Update accrued royalties
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        bytes32[] memory accrualHashes = new bytes32[](2);
        
        recipients[0] = minter;
        recipients[1] = creator;
        amounts[0] = minterShare;
        amounts[1] = creatorShare;
        accrualHashes[0] = txHash;
        accrualHashes[1] = txHash;
        
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts, accrualHashes);
        vm.stopPrank();
        
        // Verify correct royalty accrual
        assertEq(distributor.getClaimableRoyalties(address(nft), minter), minterShare, "Minter should have claimable royalties");
        assertEq(distributor.getClaimableRoyalties(address(nft), creator), creatorShare, "Creator should have claimable royalties");
    }

    /**
     * @notice Simplified test focused just on the royalty distribution without token transfers
     */
    function testRoyaltyDistributionFlow() public {
        console.log("Starting royalty distribution test");
        
        // 1. Setup a simulated sale (1 ETH)
        uint256 salePrice = 1 ether;
        uint256 royaltyAmount = (salePrice * 750) / 10_000; // 7.5% of 1 ETH
        
        console.log("Sale price:", salePrice);
        console.log("Royalty amount:", royaltyAmount);
        
        // 2. Record balances before
        uint256 minterBalanceBefore = minter.balance;
        uint256 creatorBalanceBefore = creator.balance;
        
        // 3. Add funds to distributor so claims can work
        vm.deal(address(this), royaltyAmount);
        distributor.addCollectionRoyalties{value: royaltyAmount}(address(nft));
        
        // 4. Record the sale data in the distributor
        // This will automatically calculate and accrue the royalties
        // based on the collection config (20% minter, 80% creator)
        uint256[] memory tokenIds = new uint256[](1);
        address[] memory minters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);
        
        tokenIds[0] = 1;
        minters[0] = minter;
        salePrices[0] = salePrice;
        txHashes[0] = keccak256(abi.encodePacked("sale1"));
        
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(address(nft), tokenIds, minters, salePrices, txHashes);
        
        // 5. Calculate expected shares (for verification only)
        uint256 expectedMinterShare = (royaltyAmount * 2000) / 10_000; // 20% of royalties
        uint256 expectedCreatorShare = (royaltyAmount * 8000) / 10_000; // 80% of royalties
        
        console.log("Expected minter share:", expectedMinterShare);
        console.log("Expected creator share:", expectedCreatorShare);
        
        // 6. Verify the accrued amounts match our expectations
        uint256 minterClaimable = distributor.getClaimableRoyalties(address(nft), minter);
        uint256 creatorClaimable = distributor.getClaimableRoyalties(address(nft), creator);
        
        assertEq(minterClaimable, expectedMinterShare, "Minter should have correct claimable royalties");
        assertEq(creatorClaimable, expectedCreatorShare, "Creator should have correct claimable royalties");
        
        // 7. Claim royalties
        vm.prank(minter);
        distributor.claimRoyalties(address(nft), minterClaimable);
        
        vm.prank(creator);
        distributor.claimRoyalties(address(nft), creatorClaimable);
        
        // 8. Verify balances after claiming
        assertEq(minter.balance, minterBalanceBefore + minterClaimable, "Minter should receive their share");
        assertEq(creator.balance, creatorBalanceBefore + creatorClaimable, "Creator should receive their share");
        
        // 9. Verify claimed amounts
        assertEq(distributor.getClaimableRoyalties(address(nft), minter), 0, "Minter should have 0 royalties after claim");
        assertEq(distributor.getClaimableRoyalties(address(nft), creator), 0, "Creator should have 0 royalties after claim");
        
        console.log("Royalty distribution test passed");
    }
}