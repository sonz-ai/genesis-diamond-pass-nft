// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/DiamondGenesisPass.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";

contract DiamondGenesisPassBasicTest is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass nft;
    address admin = address(0x1);
    address service = address(0x2);
    address creator = address(0x3);
    address user = address(0x4);
    bytes32 exampleRoot = keccak256("testRoot");

    // Events matching DiamondGenesisPass
    event MerkleRootSet(bytes32 indexed merkleRoot);
    event PublicMintStatusUpdated(bool isActive);
    event PublicMinted(address indexed to, uint256 indexed tokenId);
    event SaleRecorded(address indexed collection, uint256 indexed tokenId, uint256 salePrice);

    function setUp() public {
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        nft = new DiamondGenesisPass(address(distributor), 1000, creator);
        vm.stopPrank();
    }

    function testInitialMerkleRootIsZero() public {
        assertEq(nft.getMerkleRoot(), bytes32(0));
    }

    function testSetMerkleRootByOwner() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit MerkleRootSet(exampleRoot);
        nft.setMerkleRoot(exampleRoot);
        assertEq(nft.getMerkleRoot(), exampleRoot);
    }

    function testSetMerkleRootRevertsWhenNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        nft.setMerkleRoot(exampleRoot);
    }

    function testInitialPublicMintInactive() public {
        vm.prank(user);
        vm.deal(user, 1 ether);
        vm.expectRevert(DiamondGenesisPass.PublicMintNotActive.selector);
        nft.mint{value: 0.1 ether}(user);
    }

    function testSetPublicMintActiveAndMint() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit PublicMintStatusUpdated(true);
        nft.setPublicMintActive(true);
        
        vm.prank(user);
        vm.deal(user, 1 ether);
        vm.expectEmit(true, true, true, true);
        emit PublicMinted(user, 1);
        nft.mint{value: 0.1 ether}(user);

        assertEq(nft.ownerOf(1), user);
    }

    function testRecordSaleByOwnerAndService() public {
        // Initialize public minting
        vm.prank(admin);
        nft.setPublicMintActive(true);
        
        // Mint a token to user
        vm.prank(user);
        // Ensure user has ETH
        vm.deal(user, 1 ether);
        nft.mint{value: 0.1 ether}(user);
        
        // Record sale by owner
        vm.prank(admin);
        nft.recordSale(1, 1 ether);
        
        // Record sale by service account
        vm.prank(service);
        nft.recordSale(1, 2 ether);
    }

    function testRecordSaleRevertsWhenNotAuthorized() public {
        vm.prank(user);
        vm.expectRevert();
        nft.recordSale(1, 1 ether);
    }

    function testSupportsInterfaceCorrectly() public {
        // ERC721
        assertTrue(nft.supportsInterface(0x80ac58cd));
        // ERC2981
        assertTrue(nft.supportsInterface(0x2a55205a));
        // AccessControl
        assertTrue(nft.supportsInterface(0x7965db0b));
        // random
        assertFalse(nft.supportsInterface(0x12345678));
    }
}
