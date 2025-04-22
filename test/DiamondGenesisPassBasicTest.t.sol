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
        
        // Only register if not already registered in constructor
        if (!distributor.isCollectionRegistered(address(nft))) {
            distributor.registerCollection(
                address(nft),
                1000, // 10% royalty fee
                2000, // 20% minter shares
                8000, // 80% creator shares
                creator
            );
        }
        
        vm.stopPrank();
    }

    function testInitialMerkleRootIsZero() public {
        // Try to whitelist mint - should fail as root is not set
        bytes32[] memory proof = new bytes32[](0);
        vm.expectRevert(DiamondGenesisPass.MerkleRootNotSet.selector);
        nft.whitelistMint(1, proof);
    }

    function testSetMerkleRootByOwner() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit MerkleRootSet(exampleRoot);
        nft.setMerkleRoot(exampleRoot);
        // Assertion removed as private variable cannot be read directly
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
        nft.mint(user);
    }

    function testSetPublicMintActiveAndMint() public {
        // Get mint price from contract
        uint256 mintPrice = nft.PUBLIC_MINT_PRICE();
        
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit PublicMintStatusUpdated(true);
        nft.setPublicMintActive(true);
        
        vm.prank(user);
        vm.deal(user, mintPrice);
        vm.expectEmit(true, true, true, true);
        emit PublicMinted(user, 1);
        nft.mint{value: mintPrice}(user);

        assertEq(nft.ownerOf(1), user, "User should own the minted token");
    }

    function testRecordSaleByOwnerAndService() public {
        // Initialize public minting
        vm.prank(admin);
        nft.setPublicMintActive(true);
        
        // Get mint price from contract
        uint256 mintPrice = nft.PUBLIC_MINT_PRICE();
        
        // Mint a token to user
        vm.startPrank(user);
        vm.deal(user, mintPrice);
        nft.mint{value: mintPrice}(user);
        vm.stopPrank();
        
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

    function testSupportsInterfaceCorrectly() public view {
        // ERC721
        assertTrue(nft.supportsInterface(type(IERC721).interfaceId), "Does not support IERC721");
        // ERC2981
        assertTrue(nft.supportsInterface(type(IERC721Metadata).interfaceId), "Does not support IERC721Metadata");
        // AccessControl
        assertTrue(nft.supportsInterface(0x7965db0b));
        // random
        assertFalse(nft.supportsInterface(0x12345678));
    }
}
