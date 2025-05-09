// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

contract CentralizedRoyaltyAdapterTest is Test {
    CentralizedRoyaltyDistributor public distributor;
    DiamondGenesisPass public nft;
    address public admin = address(0xAD);
    address public creator = address(0xC0FFEE);
    address public user1 = address(0x1);

    function setUp() public {
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        nft = new DiamondGenesisPass(address(distributor), 1000, creator);
        // Only register if not already registered
        if (!distributor.isCollectionRegistered(address(nft))) {
            distributor.registerCollection(address(nft), 1000, 2000, 8000, creator);
        }
        vm.stopPrank();
    }

    function testSupportsInterfaceIERC2981() public view {
        // IERC2981 interface should be supported via adapter
        assertTrue(nft.supportsInterface(type(IERC2981).interfaceId));
    }

    function testRoyaltyInfoReturnsDistributorAndCorrectAmount() public view {
        // 2 ETH sale price => royalty = 2 ETH * 10% = 0.2 ETH
        (address receiver, uint256 amount) = nft.royaltyInfo(1, 2 ether);
        assertEq(receiver, address(distributor));
        assertEq(amount, (2 ether * 1000) / 10000);
    }

    function testHelperViewsReturnCorrectConfig() public view {
        // minterShares and creatorShares from distributor
        assertEq(nft.minterShares(), 2000);
        assertEq(nft.creatorShares(), 8000);
        // creator address
        assertEq(nft.creator(), creator);
        // royalty fee numerator via distributor
        assertEq(nft.distributorRoyaltyFeeNumerator(), 1000);
    }

    function testMinterOfAfterMintOwner() public {
        vm.prank(admin);
        nft.mintOwner(user1);
        // minterOf should reflect the original minter
        assertEq(nft.minterOf(1), user1);
    }

    function testInitialClaimableRoyaltiesAreZero() public view {
        // Initial claimable royalties should be zero
        assertEq(nft.getClaimableRoyalties(user1), 0);
    }
} 