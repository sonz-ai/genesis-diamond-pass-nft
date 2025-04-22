// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/DiamondGenesisPass.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";

/**
 * @title DiamondGenesisPassRoleManagement
 * @notice Test to verify proper role management in DiamondGenesisPass
 * @dev This test specifically checks the AccessControl functionality
 *      and the onlyOwnerOrServiceAccount modifier
 */
contract DiamondGenesisPassRoleManagement is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass nft;
    
    address admin = address(0x1);
    address serviceAccount = address(0x2);
    address creator = address(0x3);
    address user = address(0x4);
    address newOwner = address(0x5);
    address newServiceAccount = address(0x6);
    
    bytes32 constant SERVICE_ACCOUNT_ROLE = keccak256("SERVICE_ACCOUNT_ROLE");
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    
    function setUp() public {
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), serviceAccount);
        
        nft = new DiamondGenesisPass(address(distributor), 1000, creator);
        vm.stopPrank();
    }
    
    function testInitialRoleAssignment() public view {
        // Check that the deployer (admin) has both roles
        assertTrue(nft.hasRole(DEFAULT_ADMIN_ROLE, admin), "Admin should have DEFAULT_ADMIN_ROLE");
        assertTrue(nft.hasRole(SERVICE_ACCOUNT_ROLE, admin), "Admin should have SERVICE_ACCOUNT_ROLE");
        
        // Check that the deployer is also the owner
        assertEq(nft.owner(), admin, "Admin should be the owner");
        
        // Check that the role admin for SERVICE_ACCOUNT_ROLE is DEFAULT_ADMIN_ROLE
        assertEq(nft.getRoleAdmin(SERVICE_ACCOUNT_ROLE), DEFAULT_ADMIN_ROLE, 
            "DEFAULT_ADMIN_ROLE should be the admin for SERVICE_ACCOUNT_ROLE");
    }
    
    function testOwnershipTransfer() public {
        // Transfer ownership to newOwner
        vm.prank(admin);
        nft.transferOwnership(newOwner);
        
        // Check that ownership was transferred
        assertEq(nft.owner(), newOwner, "Ownership should be transferred to newOwner");
        
        // Verify that transferring ownership doesn't affect roles
        assertTrue(nft.hasRole(DEFAULT_ADMIN_ROLE, admin), "Admin should still have DEFAULT_ADMIN_ROLE after ownership transfer");
        assertTrue(nft.hasRole(SERVICE_ACCOUNT_ROLE, admin), "Admin should still have SERVICE_ACCOUNT_ROLE after ownership transfer");
        
        // New owner should not automatically have roles
        assertFalse(nft.hasRole(DEFAULT_ADMIN_ROLE, newOwner), "New owner should not automatically have DEFAULT_ADMIN_ROLE");
        assertFalse(nft.hasRole(SERVICE_ACCOUNT_ROLE, newOwner), "New owner should not automatically have SERVICE_ACCOUNT_ROLE");
    }
    
    function testRoleManagement() public {
        // Grant SERVICE_ACCOUNT_ROLE to newServiceAccount
        vm.prank(admin);
        nft.grantRole(SERVICE_ACCOUNT_ROLE, newServiceAccount);
        
        // Check that the role was granted
        assertTrue(nft.hasRole(SERVICE_ACCOUNT_ROLE, newServiceAccount), 
            "newServiceAccount should have SERVICE_ACCOUNT_ROLE");
        
        // Revoke SERVICE_ACCOUNT_ROLE from admin
        vm.prank(admin);
        nft.revokeRole(SERVICE_ACCOUNT_ROLE, admin);
        
        // Check that the role was revoked
        assertFalse(nft.hasRole(SERVICE_ACCOUNT_ROLE, admin), 
            "Admin should no longer have SERVICE_ACCOUNT_ROLE");
        
        // Try to grant role as non-admin (should fail)
        vm.prank(user);
        vm.expectRevert();
        nft.grantRole(SERVICE_ACCOUNT_ROLE, user);
    }
    
    function testOnlyOwnerOrServiceAccountModifier() public {
        // Setup: Grant SERVICE_ACCOUNT_ROLE to serviceAccount
        vm.prank(admin);
        nft.grantRole(SERVICE_ACCOUNT_ROLE, serviceAccount);
        
        // Test 1: Owner can call mintOwner
        vm.prank(admin);
        nft.mintOwner(admin);
        assertEq(nft.ownerOf(1), admin, "Owner should be able to mint");
        
        // Test 2: Service account can call mintOwner
        vm.prank(serviceAccount);
        nft.mintOwner(serviceAccount);
        assertEq(nft.ownerOf(2), serviceAccount, "Service account should be able to mint");
        
        // Test 3: Regular user cannot call mintOwner
        vm.prank(user);
        vm.expectRevert(DiamondGenesisPass.CallerIsNotAdminOrServiceAccount.selector);
        nft.mintOwner(user);
        
        // Test 4: After ownership transfer, old owner can still call if they have SERVICE_ACCOUNT_ROLE
        vm.prank(admin);
        nft.transferOwnership(newOwner);
        
        vm.prank(admin);
        nft.mintOwner(admin);
        assertEq(nft.ownerOf(3), admin, "Old owner with SERVICE_ACCOUNT_ROLE should still be able to mint");
        
        // Test 5: New owner can call even without SERVICE_ACCOUNT_ROLE
        vm.prank(newOwner);
        nft.mintOwner(newOwner);
        assertEq(nft.ownerOf(4), newOwner, "New owner should be able to mint without SERVICE_ACCOUNT_ROLE");
        
        // Test 6: After revoking SERVICE_ACCOUNT_ROLE from DiamondGenesisPass, old owner still has access
        // because they have SERVICE_ACCOUNT_ROLE on the distributor
        vm.prank(newOwner);
        nft.revokeRole(SERVICE_ACCOUNT_ROLE, admin);
        
        // Admin can still call mintOwner because they have SERVICE_ACCOUNT_ROLE on distributor
        vm.prank(admin);
        nft.mintOwner(admin);
        assertEq(nft.ownerOf(5), admin, "Admin with distributor SERVICE_ACCOUNT_ROLE should be able to mint");
        
        // Only after mocking that admin doesn't have the distributor role would the call fail
        // We can do this by mocking the hasRole call on the distributor
        vm.mockCall(
            address(distributor),
            abi.encodeWithSelector(distributor.hasRole.selector, distributor.SERVICE_ACCOUNT_ROLE(), admin),
            abi.encode(false)
        );
        
        vm.prank(admin);
        vm.expectRevert(DiamondGenesisPass.CallerIsNotAdminOrServiceAccount.selector);
        nft.mintOwner(admin);
    }
    
    function testRecordSalePermissions() public {
        // Setup: Mint a token and set up roles
        vm.prank(admin);
        nft.mintOwner(user);
        
        vm.prank(admin);
        nft.grantRole(SERVICE_ACCOUNT_ROLE, serviceAccount);
        
        // Test 1: Owner can record sale
        vm.prank(admin);
        nft.recordSale(1, 1 ether);
        
        // Test 2: Service account can record sale
        vm.prank(serviceAccount);
        nft.recordSale(1, 2 ether);
        
        // Test 3: Regular user cannot record sale
        vm.prank(user);
        vm.expectRevert(DiamondGenesisPass.CallerIsNotAdminOrServiceAccount.selector);
        nft.recordSale(1, 3 ether);
        
        // Test 4: After ownership transfer, check permissions again
        vm.prank(admin);
        nft.transferOwnership(newOwner);
        
        // New owner can record sale
        vm.prank(newOwner);
        nft.recordSale(1, 4 ether);
        
        // Old owner with SERVICE_ACCOUNT_ROLE can still record sale
        vm.prank(admin);
        nft.recordSale(1, 5 ether);
        
        // After revoking SERVICE_ACCOUNT_ROLE from DiamondGenesisPass, old owner still has access
        // because they have SERVICE_ACCOUNT_ROLE on the distributor
        vm.prank(newOwner);
        nft.revokeRole(SERVICE_ACCOUNT_ROLE, admin);
        
        // Admin can still call recordSale because they have SERVICE_ACCOUNT_ROLE on distributor
        vm.prank(admin);
        nft.recordSale(1, 6 ether);
        
        // Only after mocking that admin doesn't have the distributor role would the call fail
        // We can do this by mocking the hasRole call on the distributor
        vm.mockCall(
            address(distributor),
            abi.encodeWithSelector(distributor.hasRole.selector, distributor.SERVICE_ACCOUNT_ROLE(), admin),
            abi.encode(false)
        );
        
        vm.prank(admin);
        vm.expectRevert(DiamondGenesisPass.CallerIsNotAdminOrServiceAccount.selector);
        nft.recordSale(1, 7 ether);
    }
    
    function testSetMerkleRootPermissions() public {
        bytes32 merkleRoot = keccak256("testRoot");
        
        // Only owner can set merkle root (not service account)
        vm.prank(admin);
        nft.grantRole(SERVICE_ACCOUNT_ROLE, serviceAccount);
        
        // Owner can set merkle root
        vm.prank(admin);
        nft.setMerkleRoot(merkleRoot);
        
        // Service account cannot set merkle root
        vm.prank(serviceAccount);
        vm.expectRevert();
        nft.setMerkleRoot(keccak256("anotherRoot"));
        
        // After ownership transfer
        vm.prank(admin);
        nft.transferOwnership(newOwner);
        
        // New owner can set merkle root
        vm.prank(newOwner);
        nft.setMerkleRoot(keccak256("newOwnerRoot"));
        
        // Old owner cannot set merkle root anymore
        vm.prank(admin);
        vm.expectRevert();
        nft.setMerkleRoot(keccak256("oldOwnerRoot"));
    }
}
