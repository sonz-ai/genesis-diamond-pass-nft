// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/DiamondGenesisPass.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";

interface IBidMarketplace {
    function placeBid(uint256 tokenId, bool isCollectionBid) external payable;
    function acceptHighestBid(uint256 tokenId) external;
    function withdrawBid(uint256 tokenId, bool isCollectionBid) external;
    function getMinter(address collection, uint256 tokenId) external view returns (address);
    function setTokenMinter(address collection, uint256 tokenId, address minter) external;
}

contract BidMarketplaceTest is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass            pass;

    address creator  = address(0xC0FFEE);
    address minter   = address(0xBEEF);
    address bidderA  = address(0xAAA1);
    address bidderB  = address(0xBBB1);

    function setUp() public {
        vm.deal(minter,  1 ether);
        vm.deal(bidderA, 5 ether);
        vm.deal(bidderB, 5 ether);

        distributor = new CentralizedRoyaltyDistributor();
        pass = new DiamondGenesisPass(address(distributor), 750, creator);
        
        // Make sure we set the minter directly in the distributor for the DiamondGenesisPass
        IBidMarketplace(address(distributor)).setTokenMinter(address(1), 1, minter);
    }

    function testBidFlow() public {
        IBidMarketplace bid = IBidMarketplace(address(distributor));

        vm.prank(bidderA);
        bid.placeBid{value: 1 ether}(1, false);

        vm.prank(bidderB);
        bid.placeBid{value: 2 ether}(1, false);

        vm.prank(minter);
        bid.acceptHighestBid(1);

        address newMinter = bid.getMinter(address(1), 1);
        assertEq(newMinter, bidderB);

        uint256 balBefore = bidderA.balance;
        vm.prank(bidderA);
        bid.withdrawBid(1, false);
        assertGt(bidderA.balance, balBefore);
    }
}