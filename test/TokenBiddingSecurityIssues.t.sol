// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/DiamondGenesisPass.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";

contract TokenBiddingSecurityIssuesTest is Test {
    CentralizedRoyaltyDistributor public distributor;
    DiamondGenesisPass public nft;
    
    address public owner = address(0x1);
    address public serviceAccount = address(0x2);
    address public creator = address(0x3);
    address public user1 = address(0x4);
    address public user2 = address(0x5);
    
    uint96 public royaltyFee = 750; // 7.5%
    
    function setUp() public {
        // Give test accounts some ETH
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(creator, 10 ether);
        vm.deal(owner, 10 ether);
        vm.deal(serviceAccount, 10 ether);
        
        vm.startPrank(owner);
        
        // Deploy the contracts
        distributor = new CentralizedRoyaltyDistributor();
        nft = new DiamondGenesisPass(
            address(distributor),
            royaltyFee,
            creator
        );
        
        // Setup roles
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), serviceAccount);
        nft.grantRole(nft.SERVICE_ACCOUNT_ROLE(), serviceAccount);
        
        // Configure NFT for testing
        nft.setPublicMintActive(true);
        
        vm.stopPrank();
        
        // Mint tokens for testing
        vm.startPrank(user1);
        nft.mint{value: 0.1 ether}(user1);
        vm.stopPrank();
        
        vm.startPrank(user2);
        nft.mint{value: 0.1 ether}(user2);
        vm.stopPrank();
    }
    
    function testSelfBiddingPrevention() public {
        // User1 owns tokenId 1
        assertEq(nft.ownerOf(1), user1);
        
        // User1 can place a bid on their own token (this is allowed)
        vm.startPrank(user1);
        nft.placeTokenBid{value: 0.2 ether}(1, false);
        vm.stopPrank();
        
        // Get highest bid
        (address highestBidder, uint256 highestBidAmount,) = nft.getHighestTokenBid(1, false);
        
        // Verify user1 is the highest bidder on their own token
        assertEq(highestBidder, user1);
        assertEq(highestBidAmount, 0.2 ether);
        
        // User1 should NOT be able to accept their own bid
        vm.startPrank(user1);
        
        // Try to accept own bid - this should revert with SelfBiddingNotAllowed
        vm.expectRevert(DiamondGenesisPass.SelfBiddingNotAllowed.selector);
        nft.acceptHighestTokenBid(1);
        
        vm.stopPrank();
        
        // The user should still own the token
        assertEq(nft.ownerOf(1), user1, "User should still own the token");
        
        // This test verifies that the contract correctly prevents users from accepting bids they placed themselves,
        // which prevents artificial sales and royalty generation.
    }
    
    function testProposedSelfBiddingFix() public {
        // The proposed fix is already implemented in the contract
        
        /*
        Within acceptHighestTokenBid:
        
        // Check that highest bidder is not the token owner (prevent self-bidding)
        if (highestBidder == msg.sender) {
            revert SelfBiddingNotAllowed();
        }
        */
        
        // Let's verify the same check exists in acceptHighestBid for minter status trading
        
        // First mint and verify ownership
        assertEq(nft.ownerOf(1), user1);
        
        // Get the minter of token #1 (should be user1)
        address minter = nft.getMinterOf(1);
        assertEq(minter, user1);
        
        // User1 places a bid on their own minter status
        vm.startPrank(user1);
        nft.placeBid{value: 0.2 ether}(1, false);
        vm.stopPrank();
        
        // Verify the bid is placed
        (address bidder, uint256 bidAmount, ) = nft.getHighestBid(1, false);
        assertEq(bidder, user1);
        assertEq(bidAmount, 0.2 ether);
        
        // User1 should NOT be able to accept their own bid for minter status
        vm.startPrank(user1);
        
        // Try to accept own bid - this should revert with SelfBiddingNotAllowed
        vm.expectRevert(DiamondGenesisPass.SelfBiddingNotAllowed.selector);
        nft.acceptHighestBid(1);
        
        vm.stopPrank();
        
        // This confirms that the self-bidding fix is already implemented for both token trading 
        // and minter status trading
    }
} 