// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";

contract CentralizedRoyaltyAdapterDirectAccrualTest is Test {
    CentralizedRoyaltyDistributor public distributor;
    DiamondGenesisPass             public nft;

    address public admin    = address(0x1001);
    address public service  = address(0x1002);
    address public creator  = address(0x1003);
    address public user1    = address(0x1111);
    address public user2    = address(0x2222);

    function setUp() public {
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);

        nft = new DiamondGenesisPass(address(distributor), 750, creator);
        vm.stopPrank();

        vm.deal(admin, 10 ether);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
    }

    /* ───────── direct accrual system ───────── */
    function testDirectAccrualSystem() public {
        // Mint a token to user1
        vm.prank(admin);
        nft.mintOwner(user1);
        
        // Check initial accrued royalties is zero
        uint256 initialAccrued = distributor.getClaimableRoyalties(address(nft), user1);
        assertEq(initialAccrued, 0);
        
        // Add ETH to the distributor's collection pool
        vm.deal(admin, 2 ether);
        vm.prank(admin);
        distributor.addCollectionRoyalties{value: 1 ether}(address(nft));
        
        // Update accrued royalties via service account
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = user1;
        amounts[0] = 0.5 ether;
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // Check updated accrued royalties
        uint256 accrued = distributor.getClaimableRoyalties(address(nft), user1);
        assertEq(accrued, 0.5 ether);
        
        // Claim royalties
        vm.prank(user1);
        distributor.claimRoyalties(address(nft), 0.3 ether);
        
        // Check remaining claimable amount after partial claim
        uint256 remaining = distributor.getClaimableRoyalties(address(nft), user1);
        assertEq(remaining, 0.2 ether);
    }
} 