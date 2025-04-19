pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/programmable-royalties/CentralizedRoyaltyAdapter.sol"; // interface only
import "src/DiamondGenesisPass.sol";
import "lib/murky/src/Merkle.sol"; // For generating proofs, if available.

contract CentralizedRoyaltyDistributorTest is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass nft;

    address admin = address(0xA11CE);
    address service = address(0xBEEF);
    address creator = address(0xC0FFEE);
    address user1 = address(0x1);
    address user2 = address(0x2);

    bytes32 emptyRoot = bytes32(0);

    function setUp() public {
        // Deploy distributor as admin with roles
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        vm.stopPrank();

        // Register collection once via admin
        vm.startPrank(admin);
        uint96 royaltyNum = 750; // 7.5%
        nft = new DiamondGenesisPass(address(distributor), royaltyNum, creator);
        // Only register if not already registered in constructor
        if (!distributor.isCollectionRegistered(address(nft))) {
            distributor.registerCollection(address(nft), royaltyNum, 2000, 8000, creator);
        }
        vm.stopPrank();
    }

    function testRegisterCollectionDuplicateRevert() public {
        vm.prank(admin);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__CollectionAlreadyRegistered.selector);
        distributor.registerCollection(address(nft), 750, 2000, 8000, creator);
    }

    function testNonAdminCannotRegister() public {
        vm.prank(user1);
        vm.expectRevert();
        distributor.registerCollection(address(0x123), 750, 2000, 8000, creator);
    }

    function testSetTokenMinter() public {
        // Mint using owner to user1 to bypass whitelist etc.
        vm.prank(admin);
        nft.mintOwner(user1);
        // Verify
        address minter = distributor.getMinter(address(nft), 1);
        assertEq(minter, user1);
    }

    function _createSingleLeafTree(address recipient, uint256 amount) internal pure returns (bytes32 root, bytes32[] memory proof) {
        bytes32 leaf = keccak256(abi.encodePacked(recipient, amount));
        root = leaf;
        proof = new bytes32[](0);
    }

    function testSubmitMerkleRootAndClaim() public {
        // deposit royalties
        vm.deal(address(this), 1 ether);
        distributor.addCollectionRoyalties{value: 1 ether}(address(nft));
        // create root
        uint256 claimAmount = 0.5 ether;
        (bytes32 root, bytes32[] memory proof) = _createSingleLeafTree(user1, claimAmount);
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), root, claimAmount);
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        distributor.claimRoyaltiesMerkle(address(nft), user1, claimAmount, proof);
        assertEq(user1.balance, 1 ether + claimAmount);
    }
} 