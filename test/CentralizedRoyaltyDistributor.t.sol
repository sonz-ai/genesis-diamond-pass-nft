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

    function testUpdateAccruedRoyaltiesAndClaim() public {
        // deposit royalties
        vm.deal(address(this), 1 ether);
        distributor.addCollectionRoyalties{value: 1 ether}(address(nft));
        
        // Update accrued royalties
        uint256 claimAmount = 0.5 ether;
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = user1;
        amounts[0] = claimAmount;
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // Verify accrued amount
        uint256 claimable = distributor.getClaimableRoyalties(address(nft), user1);
        assertEq(claimable, claimAmount);
        
        // Claim royalties
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        distributor.claimRoyalties(address(nft), claimAmount);
        
        // Verify balance increased
        assertEq(user1.balance, 1 ether + claimAmount);
        
        // Verify claimed amount is reflected
        claimable = distributor.getClaimableRoyalties(address(nft), user1);
        assertEq(claimable, 0);
    }
} 