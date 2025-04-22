// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "src/DiamondGenesisPass.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";

contract MinterStatusBiddingTest is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass pass;

    address creator = address(0xC0FFEE);
    address owner = address(0xDEAD);
    address originalMinter = address(0xBEEF);
    address bidder1 = address(0xB1D1);
    address bidder2 = address(0xB1D2);
    address bidder3 = address(0xB1D3);

    function setUp() public {
        // Give everyone some ETH
        vm.deal(owner, 10 ether);
        vm.deal(originalMinter, 10 ether);
        vm.deal(bidder1, 10 ether);
        vm.deal(bidder2, 10 ether);
        vm.deal(bidder3, 10 ether);

        // Deploy contracts
        distributor = new CentralizedRoyaltyDistributor();
        pass = new DiamondGenesisPass(address(distributor), 750, creator);
        
        // Transfer ownership to the test owner
        pass.transferOwnership(owner);
        
        // Setup roles
        bytes32 SERVICE_ACCOUNT_ROLE = keccak256("SERVICE_ACCOUNT_ROLE");
        distributor.grantRole(SERVICE_ACCOUNT_ROLE, address(pass));
        distributor.grantRole(SERVICE_ACCOUNT_ROLE, address(this));
        
        // Owner mints one token to the original minter
        vm.prank(owner);
        pass.mintOwner(originalMinter);
    }

    function testInitialMinterStatus() public view {
        // Check that originalMinter is indeed the minter of token #1
        address actualMinter = pass.getMinterOf(1);
        assertEq(actualMinter, originalMinter);
    }

    function testPlacingTokenSpecificBid() public {
        // Bidder1 places a bid for token #1
        uint256 bidAmount = 0.5 ether;
        vm.prank(bidder1);
        pass.placeBid{value: bidAmount}(1, false);
        
        // Check if bid is recorded correctly
        DiamondGenesisPass.Bid[] memory bids = pass.viewBids(1);
        assertEq(bids.length, 1);
        assertEq(bids[0].bidder, bidder1);
        assertEq(bids[0].amount, bidAmount);
    }

    function testPlacingCollectionWideBid() public {
        // Bidder1 places a collection-wide bid
        uint256 bidAmount = 0.5 ether;
        vm.prank(bidder1);
        pass.placeBid{value: bidAmount}(0, true);
        
        // Check if bid is recorded correctly
        DiamondGenesisPass.Bid[] memory bids = pass.viewCollectionBids();
        assertEq(bids.length, 1);
        assertEq(bids[0].bidder, bidder1);
        assertEq(bids[0].amount, bidAmount);
    }

    function testIncreasingExistingBid() public {
        // Initial bid
        uint256 initialBidAmount = 0.5 ether;
        vm.prank(bidder1);
        pass.placeBid{value: initialBidAmount}(1, false);
        
        // Increase bid
        uint256 additionalBidAmount = 0.3 ether;
        vm.prank(bidder1);
        pass.placeBid{value: additionalBidAmount}(1, false);
        
        // Check if bid was increased correctly
        DiamondGenesisPass.Bid[] memory bids = pass.viewBids(1);
        assertEq(bids.length, 1);
        assertEq(bids[0].bidder, bidder1);
        assertEq(bids[0].amount, initialBidAmount + additionalBidAmount);
    }

    function testWithdrawingBid() public {
        // Initial bid
        uint256 bidAmount = 0.5 ether;
        vm.prank(bidder1);
        pass.placeBid{value: bidAmount}(1, false);
        
        // Get bidder1's balance before withdrawal
        uint256 balanceBefore = bidder1.balance;
        
        // Withdraw bid
        vm.prank(bidder1);
        pass.withdrawBid(1, false);
        
        // Check if bid was removed
        DiamondGenesisPass.Bid[] memory bids = pass.viewBids(1);
        assertEq(bids.length, 0);
        
        // Check if funds were returned
        assertEq(bidder1.balance, balanceBefore + bidAmount);
    }

    function testGetHighestBid() public {
        // Bidder1 places a bid
        vm.prank(bidder1);
        pass.placeBid{value: 0.5 ether}(1, false);
        
        // Bidder2 places a higher bid
        vm.prank(bidder2);
        pass.placeBid{value: 0.7 ether}(1, false);
        
        // Bidder3 places a lower bid
        vm.prank(bidder3);
        pass.placeBid{value: 0.3 ether}(1, false);
        
        // Check highest bid
        (address highestBidder, uint256 highestAmount,) = pass.getHighestBid(1, false);
        assertEq(highestBidder, bidder2);
        assertEq(highestAmount, 0.7 ether);
    }

    function testAcceptingHighestBid() public {
        // Record initial balances
        uint256 ownerBalanceBefore = owner.balance;
        
        // Bidder1 places a bid
        vm.prank(bidder1);
        pass.placeBid{value: 0.5 ether}(1, false);
        
        // Bidder2 places a higher bid
        vm.prank(bidder2);
        pass.placeBid{value: 0.7 ether}(1, false);
        
        // Original minter accepts the highest bid
        vm.prank(originalMinter);
        pass.acceptHighestBid(1);
        
        // Verify the minter status changed
        address newMinter = pass.getMinterOf(1);
        assertEq(newMinter, bidder2, "The highest bidder should become the new minter");
        
        // Check if payment went to the owner (not to the original minter)
        assertEq(owner.balance, ownerBalanceBefore + 0.7 ether);
        
        // Check if bids were completely cleared
        DiamondGenesisPass.Bid[] memory bids = pass.viewBids(1);
        assertEq(bids.length, 0, "All bids should be cleared after accepting the highest bid");
    }

    function testAcceptingCollectionWideBid() public {
        // Owner's initial balance
        uint256 ownerBalanceBefore = owner.balance;
        
        // Bidder1 places a token-specific bid
        vm.prank(bidder1);
        pass.placeBid{value: 0.5 ether}(1, false);
        
        // Bidder2 places a higher collection-wide bid
        vm.prank(bidder2);
        pass.placeBid{value: 0.8 ether}(0, true);
        
        // Original minter accepts the highest bid (which is the collection-wide one)
        vm.prank(originalMinter);
        pass.acceptHighestBid(1);
        
        // Check if minter status was transferred to collection-wide bidder
        address newMinter = pass.getMinterOf(1);
        assertEq(newMinter, bidder2);
        
        // Check if payment went to the owner
        assertEq(owner.balance, ownerBalanceBefore + 0.8 ether);
    }

    function testOnlyMinterCanAcceptBid() public {
        // Bidder1 places a bid
        vm.prank(bidder1);
        pass.placeBid{value: 0.5 ether}(1, false);
        
        // Non-minter tries to accept the bid
        vm.prank(bidder3);
        vm.expectRevert(); // Expected to revert with NotTokenMinter
        pass.acceptHighestBid(1);
    }

    function testNoBidsAvailable() public {
        // No bids placed yet
        
        // Minter tries to accept non-existent bids
        vm.prank(originalMinter);
        vm.expectRevert(); // Expected to revert with NoBidsAvailable
        pass.acceptHighestBid(1);
    }

    function testOwnerCanAssignMinterStatus() public {
        // Owner assigns minter status to bidder3
        vm.prank(owner);
        pass.setMinterStatus(1, bidder3);
        
        // Check if minter status was assigned
        address newMinter = pass.getMinterOf(1);
        assertEq(newMinter, bidder3);
    }

    function testOwnerCanRevokeMinterStatus() public {
        // Owner assigns minter status to bidder3
        vm.prank(owner);
        pass.setMinterStatus(1, bidder3);
        
        // Owner revokes minter status
        vm.prank(owner);
        pass.revokeMinterStatus(1);
        
        // Check if minter status was revoked (should return original minter)
        address currentMinter = pass.getMinterOf(1);
        assertEq(currentMinter, originalMinter);
    }

    function testMinterAndOwnerSeparation() public {
        // Initial state: originalMinter is both the minter and owner of token 1
        assertEq(pass.getMinterOf(1), originalMinter);
        assertEq(pass.ownerOf(1), originalMinter);
        
        // Owner mints a second token to bidder1
        vm.prank(owner);
        pass.mintOwner(bidder1);
        
        // Verify bidder1 is both minter and owner of token 2
        assertEq(pass.getMinterOf(2), bidder1);
        assertEq(pass.ownerOf(2), bidder1);
        
        // Owner set minter status of token 1 to bidder2 (separate from owner)
        vm.prank(owner);
        pass.setMinterStatus(1, bidder2);
        
        // Verify token 1 now has separate minter and owner
        assertEq(pass.getMinterOf(1), bidder2, "Minter should be updated to bidder2");
        assertEq(pass.ownerOf(1), originalMinter, "Owner should still be originalMinter");
    }
} 