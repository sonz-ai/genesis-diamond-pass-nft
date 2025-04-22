// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "src/DiamondGenesisPass.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";

contract TokenBiddingTest is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass pass;

    address creator = address(0xC0FFEE);
    address owner = address(0xDEAD);
    address tokenOwner = address(0xBEEF);
    address bidder1 = address(0xB1D1);
    address bidder2 = address(0xB1D2);
    address bidder3 = address(0xB1D3);

    function setUp() public {
        // Give everyone some ETH
        vm.deal(owner, 10 ether);
        vm.deal(tokenOwner, 10 ether);
        vm.deal(bidder1, 10 ether);
        vm.deal(bidder2, 10 ether);
        vm.deal(bidder3, 10 ether);
        vm.deal(creator, 10 ether);

        // Deploy contracts
        distributor = new CentralizedRoyaltyDistributor();
        pass = new DiamondGenesisPass(address(distributor), 750, creator); // 7.5% royalty fee
        
        // Transfer ownership to the test owner
        pass.transferOwnership(owner);
        
        // Setup roles
        bytes32 SERVICE_ACCOUNT_ROLE = keccak256("SERVICE_ACCOUNT_ROLE");
        distributor.grantRole(SERVICE_ACCOUNT_ROLE, address(pass));
        distributor.grantRole(SERVICE_ACCOUNT_ROLE, address(this));
        
        // Disable the transfer validator to allow transfers
        vm.prank(owner);
        pass.setTransferValidator(address(0));
        
        // Owner mints one token to the token owner
        vm.prank(owner);
        pass.mintOwner(tokenOwner);
        
        // Verify token was minted correctly
        assertEq(pass.ownerOf(1), tokenOwner, "Token owner should be set correctly");
        
        // Verify token can be transferred
        vm.prank(tokenOwner);
        pass.approve(address(this), 1);
        
        vm.prank(tokenOwner);
        pass.transferFrom(tokenOwner, address(this), 1);
        assertEq(pass.ownerOf(1), address(this), "Token should be transferable");
        
        // Transfer back to tokenOwner for the tests
        pass.transferFrom(address(this), tokenOwner, 1);
        assertEq(pass.ownerOf(1), tokenOwner, "Token should be returned to tokenOwner");
    }

    function testInitialTokenOwnership() public view {
        // Check that tokenOwner is indeed the owner of token #1
        address actualOwner = pass.ownerOf(1);
        assertEq(actualOwner, tokenOwner);
    }

    function testPlacingTokenSpecificBid() public {
        // Bidder1 places a bid for token #1
        uint256 bidAmount = 0.5 ether;
        vm.prank(bidder1);
        pass.placeTokenBid{value: bidAmount}(1, false);
        
        // Check if bid is recorded correctly
        DiamondGenesisPass.TokenBid[] memory bids = pass.viewTokenBids(1);
        assertEq(bids.length, 1);
        assertEq(bids[0].bidder, bidder1);
        assertEq(bids[0].amount, bidAmount);
    }

    function testPlacingCollectionWideBid() public {
        // Bidder1 places a collection-wide bid
        uint256 bidAmount = 0.5 ether;
        vm.prank(bidder1);
        pass.placeTokenBid{value: bidAmount}(0, true);
        
        // Check if bid is recorded correctly
        DiamondGenesisPass.TokenBid[] memory bids = pass.viewCollectionTokenBids();
        assertEq(bids.length, 1);
        assertEq(bids[0].bidder, bidder1);
        assertEq(bids[0].amount, bidAmount);
    }

    function testIncreasingExistingBid() public {
        // Initial bid
        uint256 initialBidAmount = 0.5 ether;
        vm.prank(bidder1);
        pass.placeTokenBid{value: initialBidAmount}(1, false);
        
        // Increase bid
        uint256 additionalBidAmount = 0.3 ether;
        vm.prank(bidder1);
        pass.placeTokenBid{value: additionalBidAmount}(1, false);
        
        // Check if bid was increased correctly
        DiamondGenesisPass.TokenBid[] memory bids = pass.viewTokenBids(1);
        assertEq(bids.length, 1);
        assertEq(bids[0].bidder, bidder1);
        assertEq(bids[0].amount, initialBidAmount + additionalBidAmount);
    }

    function testWithdrawingBid() public {
        // Initial bid
        uint256 bidAmount = 0.5 ether;
        vm.prank(bidder1);
        pass.placeTokenBid{value: bidAmount}(1, false);
        
        // Get bidder1's balance before withdrawal
        uint256 balanceBefore = bidder1.balance;
        
        // Withdraw bid
        vm.prank(bidder1);
        pass.withdrawTokenBid(1, false);
        
        // Check if bid was removed
        DiamondGenesisPass.TokenBid[] memory bids = pass.viewTokenBids(1);
        assertEq(bids.length, 0);
        
        // Check if funds were returned
        assertEq(bidder1.balance, balanceBefore + bidAmount);
    }

    function testGetHighestBid() public {
        // Bidder1 places a bid
        vm.prank(bidder1);
        pass.placeTokenBid{value: 0.5 ether}(1, false);
        
        // Bidder2 places a higher bid
        vm.prank(bidder2);
        pass.placeTokenBid{value: 0.7 ether}(1, false);
        
        // Bidder3 places a lower bid
        vm.prank(bidder3);
        pass.placeTokenBid{value: 0.3 ether}(1, false);
        
        // Check highest bid
        (address highestBidder, uint256 highestAmount,) = pass.getHighestTokenBid(1, false);
        assertEq(highestBidder, bidder2);
        assertEq(highestAmount, 0.7 ether);
    }

    function testAcceptingHighestBid() public {
        console.log("Starting testAcceptingHighestBid");
        
        // Record initial balances
        uint256 tokenOwnerBalanceBefore = tokenOwner.balance;
        uint256 creatorBalanceBefore = creator.balance;
        uint256 distributorBalanceBefore = address(distributor).balance;
        
        console.log("Initial balances - Owner:", tokenOwnerBalanceBefore);
        console.log("Initial balances - Distributor:", distributorBalanceBefore);
        
        // Bidder1 places a bid
        vm.prank(bidder1);
        pass.placeTokenBid{value: 0.5 ether}(1, false);
        console.log("Bidder1 placed bid for 0.5 ETH");
        
        // Bidder2 places a higher bid
        uint256 bidAmount = 0.7 ether;
        vm.prank(bidder2);
        pass.placeTokenBid{value: bidAmount}(1, false);
        console.log("Bidder2 placed bid for 0.7 ETH");
        
        // Check highest bid
        (address highBidder, uint256 highAmount,) = pass.getHighestTokenBid(1, false);
        console.log("Highest bidder:", highBidder);
        console.log("Highest amount:", highAmount);
        
        // Get token owner and confirm
        address actualOwner = pass.ownerOf(1);
        console.log("Token owner before acceptance:", actualOwner);
        
        console.log("About to accept highest bid...");
        // Token owner accepts the highest bid
        vm.prank(tokenOwner);
        try pass.acceptHighestTokenBid(1) {
            console.log("Successfully accepted bid");
        } catch Error(string memory reason) {
            console.log("Failed with reason:", reason);
            revert(reason);
        } catch (bytes memory) {
            console.log("Failed with low-level error");
            revert("Low-level error");
        }
        
        // Verify the token ownership changed
        address newOwner = pass.ownerOf(1);
        assertEq(newOwner, bidder2, "The highest bidder should become the new token owner");
        
        // Calculate expected royalty and seller proceeds
        uint256 royaltyAmount = (bidAmount * 750) / 10000; // 7.5% royalty
        uint256 sellerProceeds = bidAmount - royaltyAmount;
        
        // Check if payment distribution was correct
        // 1. Royalty to distributor
        assertEq(address(distributor).balance, distributorBalanceBefore + royaltyAmount, "Royalty should be sent to distributor");
        
        // 2. Remainder to seller
        assertEq(tokenOwner.balance, tokenOwnerBalanceBefore + sellerProceeds, "Seller should receive sale proceeds minus royalty");
        
        // Check if bids were completely cleared
        DiamondGenesisPass.TokenBid[] memory bids = pass.viewTokenBids(1);
        assertEq(bids.length, 0, "All bids should be cleared after accepting the highest bid");
    }

    function testAcceptingCollectionWideBid() public {
        // Record initial balances
        uint256 tokenOwnerBalanceBefore = tokenOwner.balance;
        uint256 distributorBalanceBefore = address(distributor).balance;
        
        // Bidder1 places a token-specific bid
        vm.prank(bidder1);
        pass.placeTokenBid{value: 0.5 ether}(1, false);
        
        // Bidder2 places a higher collection-wide bid
        uint256 bidAmount = 0.8 ether;
        vm.prank(bidder2);
        pass.placeTokenBid{value: bidAmount}(0, true);
        
        // Token owner accepts the highest bid (which is the collection-wide one)
        vm.prank(tokenOwner);
        pass.acceptHighestTokenBid(1);
        
        // Verify token ownership was transferred to collection-wide bidder
        address newOwner = pass.ownerOf(1);
        assertEq(newOwner, bidder2, "The collection-wide bidder should become the new token owner");
        
        // Calculate expected royalty and seller proceeds
        uint256 royaltyAmount = (bidAmount * 750) / 10000; // 7.5% royalty
        uint256 sellerProceeds = bidAmount - royaltyAmount;
        
        // Check royalty payment to distributor
        assertEq(address(distributor).balance, distributorBalanceBefore + royaltyAmount, "Royalty should be sent to distributor");
        
        // Check proceeds to seller
        assertEq(tokenOwner.balance, tokenOwnerBalanceBefore + sellerProceeds, "Seller should receive sale proceeds minus royalty");
    }
    
    function testNonOwnerCannotAcceptBid() public {
        // Bidder1 places a bid
        vm.prank(bidder1);
        pass.placeTokenBid{value: 0.5 ether}(1, false);
        
        // Bidder3 (not the token owner) tries to accept the bid
        vm.prank(bidder3);
        vm.expectRevert(DiamondGenesisPass.NotTokenOwner.selector);
        pass.acceptHighestTokenBid(1);
    }
    
    function testCannotBidOnNonExistentToken() public {
        // Try to bid on token #999 (doesn't exist)
        vm.prank(bidder1);
        vm.expectRevert(DiamondGenesisPass.TokenNotMinted.selector);
        pass.placeTokenBid{value: 0.5 ether}(999, false);
    }
    
    function testCannotMakeZeroBid() public {
        // Try to make a zero-value bid
        vm.prank(bidder1);
        vm.expectRevert(DiamondGenesisPass.InsufficientBidAmount.selector);
        pass.placeTokenBid{value: 0}(1, false);
    }
    
    function testSecondHighestBidRefund() public {
        // Three bidders place bids
        vm.prank(bidder1);
        pass.placeTokenBid{value: 0.5 ether}(1, false);
        
        vm.prank(bidder2);
        pass.placeTokenBid{value: 0.7 ether}(1, false);
        
        vm.prank(bidder3);
        pass.placeTokenBid{value: 0.3 ether}(1, false);
        
        // Record balances before acceptance
        uint256 bidder1BalanceBefore = bidder1.balance;
        uint256 bidder3BalanceBefore = bidder3.balance;
        
        // Token owner accepts highest bid (from bidder2)
        vm.prank(tokenOwner);
        pass.acceptHighestTokenBid(1);
        
        // Check if bidder1 and bidder3 were refunded
        assertEq(bidder1.balance, bidder1BalanceBefore + 0.5 ether, "Bidder1 should be refunded");
        assertEq(bidder3.balance, bidder3BalanceBefore + 0.3 ether, "Bidder3 should be refunded");
    }
} 