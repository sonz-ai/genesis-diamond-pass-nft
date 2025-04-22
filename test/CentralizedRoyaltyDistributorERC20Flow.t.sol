// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DummyERC20 is ERC20 {
    constructor() ERC20("DummyToken", "DUM") {}
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract CentralizedRoyaltyDistributorERC20FlowTest is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass nft;
    DummyERC20 token;
    address admin = address(0xA11CE);
    address service = address(0xBEEF);
    address creator = address(0xC0FFEE);
    address user = address(0x1);
    address user2 = address(0x2);

    function setUp() public {
        // Deploy distributor and grant service role
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        
        // Deploy NFT contract and register with distributor
        nft = new DiamondGenesisPass(address(distributor), 500, creator);
        // Only register if not already registered
        if (!distributor.isCollectionRegistered(address(nft))) {
            distributor.registerCollection(address(nft), 500, 2000, 8000, creator);
        }
        
        vm.stopPrank();

        // Deploy dummy ERC20 token
        token = new DummyERC20();
        // Give admin some tokens to distribute
        token.mint(admin, 1_000_000 ether);
    }

    // Test the basic flow: Add funds, accrue, claim
    function testAddAccrueClaimERC20Flow() public {
        uint256 depositAmount = 100 ether;
        uint256 accrueAmount = 50 ether;
        
        // 1. Add funds to distributor's collection pool
        vm.startPrank(admin);
        token.approve(address(distributor), depositAmount);
        distributor.addCollectionERC20Royalties(address(nft), token, depositAmount);
        assertEq(distributor.getCollectionERC20Royalties(address(nft), token), depositAmount);
        vm.stopPrank();

        // 2. Accrue royalties for the user
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = user;
        amounts[0] = accrueAmount;
        
        vm.startPrank(service);
        distributor.updateAccruedERC20Royalties(address(nft), token, recipients, amounts);
        assertEq(distributor.getClaimableERC20Royalties(address(nft), token, user), accrueAmount);
        vm.stopPrank();

        // 3. User claims the accrued royalties
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 distributorPoolBefore = distributor.getCollectionERC20Royalties(address(nft), token);
        uint256 userClaimableBefore = distributor.getClaimableERC20Royalties(address(nft), token, user);
        
        vm.prank(user);
        distributor.claimERC20Royalties(address(nft), token, accrueAmount);

        // Assertions
        assertEq(token.balanceOf(user), userBalanceBefore + accrueAmount, "User balance incorrect");
        assertEq(distributor.getCollectionERC20Royalties(address(nft), token), distributorPoolBefore - accrueAmount, "Distributor pool incorrect");
        assertEq(distributor.getClaimableERC20Royalties(address(nft), token, user), userClaimableBefore - accrueAmount, "User claimable incorrect");
        assertEq(distributor.getClaimableERC20Royalties(address(nft), token, user), 0, "User claimable should be zero");
    }

    // Test claiming when insufficient tokens are in the collection pool
    function testClaimERC20InsufficientPool() public {
        uint256 depositAmount = 30 ether;
        uint256 accrueAmount = 50 ether; // Try to accrue more than deposited
        
        // 1. Add funds (less than needed for accrual)
        vm.startPrank(admin);
        token.approve(address(distributor), depositAmount);
        distributor.addCollectionERC20Royalties(address(nft), token, depositAmount);
        vm.stopPrank();

        // 2. Accrue royalties for the user
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = user;
        amounts[0] = accrueAmount;
        
        vm.startPrank(service);
        distributor.updateAccruedERC20Royalties(address(nft), token, recipients, amounts);
        assertEq(distributor.getClaimableERC20Royalties(address(nft), token, user), accrueAmount);
        vm.stopPrank();

        // 3. User tries to claim - should fail due to insufficient collection balance
        vm.prank(user);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__NotEnoughTokensToDistributeForCollection.selector);
        distributor.claimERC20Royalties(address(nft), token, accrueAmount);

        // 4. Try to claim the amount actually available - should succeed
        vm.prank(user);
        distributor.claimERC20Royalties(address(nft), token, depositAmount);
        assertEq(token.balanceOf(user), depositAmount);
    }

    // Test claiming more than accrued amount
    function testClaimERC20InsufficientAccrued() public {
        uint256 depositAmount = 100 ether;
        uint256 accrueAmount = 50 ether;
        uint256 claimAmount = 60 ether; // More than accrued
        
        // 1. Add funds
        vm.startPrank(admin);
        token.approve(address(distributor), depositAmount);
        distributor.addCollectionERC20Royalties(address(nft), token, depositAmount);
        vm.stopPrank();

        // 2. Accrue royalties
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = user;
        amounts[0] = accrueAmount;
        
        vm.startPrank(service);
        distributor.updateAccruedERC20Royalties(address(nft), token, recipients, amounts);
        assertEq(distributor.getClaimableERC20Royalties(address(nft), token, user), accrueAmount);
        vm.stopPrank();

        // 3. User tries to claim more than accrued - should fail
        vm.prank(user);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__InsufficientUnclaimedRoyalties.selector);
        distributor.claimERC20Royalties(address(nft), token, claimAmount);
    }

    // Test claiming zero tokens
    function testClaimERC20ZeroAmount() public {
        uint256 depositAmount = 100 ether;
        uint256 accrueAmount = 50 ether;
        
        // 1. Add funds & Accrue
        vm.startPrank(admin);
        token.approve(address(distributor), depositAmount);
        distributor.addCollectionERC20Royalties(address(nft), token, depositAmount);
        vm.stopPrank();
        
        vm.startPrank(service);
        address[] memory recipients = new address[](1); recipients[0] = user;
        uint256[] memory amounts = new uint256[](1); amounts[0] = accrueAmount;
        distributor.updateAccruedERC20Royalties(address(nft), token, recipients, amounts);
        vm.stopPrank();

        // 2. Claim zero - should succeed without changing balances
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 distributorPoolBefore = distributor.getCollectionERC20Royalties(address(nft), token);
        uint256 userClaimableBefore = distributor.getClaimableERC20Royalties(address(nft), token, user);
        
        vm.prank(user);
        distributor.claimERC20Royalties(address(nft), token, 0);
        
        assertEq(token.balanceOf(user), userBalanceBefore, "User balance changed");
        assertEq(distributor.getCollectionERC20Royalties(address(nft), token), distributorPoolBefore, "Pool balance changed");
        assertEq(distributor.getClaimableERC20Royalties(address(nft), token, user), userClaimableBefore, "Claimable amount changed");
    }
    
    // Test permissions for updateAccruedERC20Royalties
    function testUpdateAccruedERC20Permissions() public {
        uint256 accrueAmount = 10 ether;
        address[] memory recipients = new address[](1); recipients[0] = user;
        uint256[] memory amounts = new uint256[](1); amounts[0] = accrueAmount;

        // Should fail if called by random user (user2)
        vm.prank(user2);
        vm.expectRevert(bytes("AccessControl: account"));
        distributor.updateAccruedERC20Royalties(address(nft), token, recipients, amounts);

        // Should succeed if called by service account
        vm.prank(service);
        distributor.updateAccruedERC20Royalties(address(nft), token, recipients, amounts);
        assertEq(distributor.getClaimableERC20Royalties(address(nft), token, user), accrueAmount);

        // Should succeed if called by admin
        uint256 accrueAmount2 = 20 ether;
        amounts[0] = accrueAmount2;
        vm.prank(admin);
        distributor.updateAccruedERC20Royalties(address(nft), token, recipients, amounts);
        assertEq(distributor.getClaimableERC20Royalties(address(nft), token, user), accrueAmount + accrueAmount2);
    }
    
    // Test adding zero ERC20 royalties
    function testAddZeroERC20Royalties() public {
        vm.startPrank(admin);
        token.approve(address(distributor), 0);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__ZeroAmountToDistribute.selector);
        distributor.addCollectionERC20Royalties(address(nft), token, 0);
        vm.stopPrank();
    }
}
