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
        vm.expectEmit(false, false, false, true, address(nft));
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
        vm.expectRevert(DiamondGenesisPass.PublicMintNotActive.selector);
        nft.mint{value: 0.1 ether}(user);
    }

    function testSetPublicMintActiveAndMint() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, true, address(nft));
        emit PublicMintStatusUpdated(true);
        nft.setPublicMintActive(true);

        vm.prank(user);
        vm.expectEmit(true, true, false, true, address(nft));
        emit PublicMinted(user, 1);
        nft.mint{value: 0.1 ether}(user);

        assertEq(nft.ownerOf(1), user);
    }

    function testRecordSaleByOwnerAndService() public {
        // Activate and mint
        vm.prank(admin);
        nft.setPublicMintActive(true);
        vm.prank(user);
        nft.mint{value: 0.1 ether}(user);

        // By owner
        vm.prank(admin);
        vm.expectEmit(true, true, false, true, address(nft));
        emit SaleRecorded(address(nft), 1, 2 ether);
        nft.recordSale(1, 2 ether);

        // By service
        vm.prank(service);
        vm.expectEmit(true, true, false, true, address(nft));
        emit SaleRecorded(address(nft), 1, 3 ether);
        nft.recordSale(1, 3 ether);
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
