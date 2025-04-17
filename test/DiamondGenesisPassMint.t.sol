// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/DiamondGenesisPass.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract DiamondGenesisPassMintTest is Test {
    DiamondGenesisPass nft;
    CentralizedRoyaltyDistributor distributor;
    
    address admin = address(0x1111);
    address service = address(0x2222);
    address creator = address(0x3333);
    address user1 = address(0x4444);
    address user2 = address(0x5555);
    address user3 = address(0x6666);
    
    uint256 constant PUBLIC_MINT_PRICE = 0.1 ether;
    uint256 constant MAX_SUPPLY = 888;
    bytes32 merkleRoot;
    
    // Setup for whitelist testing
    address[] whitelistAddresses;
    mapping(address => uint256) whitelistAllowances;
    bytes32[] leaves;
    
    function setUp() public {
        // Deploy contracts
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        nft = new DiamondGenesisPass(address(distributor), 750, creator);
        distributor.registerCollection(address(nft), 750, 2000, 8000, creator);
        
        // Set up roles
        nft.grantRole(nft.SERVICE_ACCOUNT_ROLE(), service);
        vm.stopPrank();
        
        // Fund test accounts
        vm.deal(admin, 10 ether);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
        
        // Setup whitelist for testing
        setupWhitelist();
    }
    
    // Helper function to set up a whitelist with Merkle tree
    function setupWhitelist() internal {
        // Define allowances for whitelist addresses
        whitelistAddresses = new address[](3);
        whitelistAddresses[0] = user1;
        whitelistAddresses[1] = user2;
        whitelistAddresses[2] = user3;
        
        whitelistAllowances[user1] = 2; // User1 can mint 2 tokens
        whitelistAllowances[user2] = 1; // User2 can mint 1 token
        whitelistAllowances[user3] = 3; // User3 can mint 3 tokens
        
        // Create merkle tree leaves
        leaves = new bytes32[](3);
        for (uint256 i = 0; i < whitelistAddresses.length; i++) {
            address account = whitelistAddresses[i];
            uint256 quantity = whitelistAllowances[account];
            leaves[i] = keccak256(abi.encodePacked(account, quantity));
        }
        
        // Create merkle tree (simple approach for testing)
        if (leaves.length == 1) {
            merkleRoot = leaves[0];
        } else if (leaves.length >= 2) {
            bytes32 leaf01 = keccak256(abi.encodePacked(leaves[0], leaves[1]));
            if (leaves.length == 2) {
                merkleRoot = leaf01;
            } else {
                bytes32 leaf2X = keccak256(abi.encodePacked(leaves[2], leaves.length > 3 ? leaves[3] : leaves[2]));
                merkleRoot = keccak256(abi.encodePacked(leaf01, leaf2X));
            }
        }
        
        // Set merkle root in the contract
        vm.prank(admin);
        nft.setMerkleRoot(merkleRoot);
    }
    
    // Helper to generate a merkle proof for testing whitelist minting
    function getProof(address account, uint256 quantity) internal view returns (bytes32[] memory) {
        bytes32 leaf = keccak256(abi.encodePacked(account, quantity));
        bytes32[] memory proof = new bytes32[](1);
        
        // Simple proof generation for testing
        if (leaf == leaves[0]) {
            proof[0] = keccak256(abi.encodePacked(leaves[1], leaves.length > 2 ? leaves[2] : leaves[1]));
        } else if (leaf == leaves[1]) {
            proof[0] = keccak256(abi.encodePacked(leaves[0], leaves.length > 2 ? leaves[2] : leaves[0]));
        } else if (leaves.length > 2 && leaf == leaves[2]) {
            proof[0] = keccak256(abi.encodePacked(leaves[0], leaves[1]));
        }
        
        return proof;
    }
    
    // Test public mint when inactive (should fail)
    function testPublicMintWhenInactive() public {
        vm.prank(user1);
        vm.expectRevert(DiamondGenesisPass.PublicMintNotActive.selector);
        nft.mint{value: PUBLIC_MINT_PRICE}(user1);
    }
    
    // Test public mint with insufficient payment (should fail)
    function testPublicMintInsufficientPayment() public {
        // Enable public minting
        vm.prank(admin);
        nft.setPublicMintActive(true);
        
        // Try to mint with insufficient payment
        vm.prank(user1);
        vm.expectRevert(DiamondGenesisPass.InsufficientPayment.selector);
        nft.mint{value: PUBLIC_MINT_PRICE - 0.01 ether}(user1);
    }
    
    // Test successful public mint
    function testPublicMintSuccess() public {
        // Enable public minting
        vm.prank(admin);
        nft.setPublicMintActive(true);
        
        // Initial balances
        uint256 adminBalanceBefore = admin.balance;
        uint256 user1BalanceBefore = user1.balance;
        
        // Mint a token
        vm.prank(user1);
        nft.mint{value: PUBLIC_MINT_PRICE}(user1);
        
        // Verify token ownership and balances
        assertEq(nft.ownerOf(1), user1);
        assertEq(nft.totalSupply(), 1);
        assertEq(user1.balance, user1BalanceBefore - PUBLIC_MINT_PRICE);
        assertEq(admin.balance, adminBalanceBefore + PUBLIC_MINT_PRICE); // Payment goes to owner (admin)
        
        // Verify minter is set correctly in the distributor
        assertEq(nft.minterOf(1), user1);
    }
    
    // Test successful safe mint
    function testSafeMintSuccess() public {
        // Enable public minting
        vm.prank(admin);
        nft.setPublicMintActive(true);
        
        // Mint a token safely
        vm.prank(user1);
        nft.safeMint{value: PUBLIC_MINT_PRICE}(user1);
        
        // Verify token ownership
        assertEq(nft.ownerOf(1), user1);
        assertEq(nft.totalSupply(), 1);
    }
    
    // Test whitelist mint without setting merkle root (should fail)
    function testWhitelistMintWithoutMerkleRoot() public {
        // Remove merkle root
        vm.prank(admin);
        nft.setMerkleRoot(bytes32(0));
        
        // Try to mint with empty merkle root
        vm.prank(user1);
        vm.expectRevert(DiamondGenesisPass.MerkleRootNotSet.selector);
        nft.whitelistMint(2, new bytes32[](0));
    }
    
    // Test whitelist mint with invalid proof (should fail)
    function testWhitelistMintInvalidProof() public {
        // Try to mint with invalid proof
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256(abi.encodePacked("invalid"));
        
        vm.prank(user1);
        vm.expectRevert(DiamondGenesisPass.InvalidMerkleProof.selector);
        nft.whitelistMint{value: PUBLIC_MINT_PRICE * 2}(2, invalidProof);
    }
    
    // Test whitelist mint with insufficient payment (should fail)
    function testWhitelistMintInsufficientPayment() public {
        // Get valid proof for user1
        bytes32[] memory proof = getProof(user1, 2);
        
        // Try to mint with insufficient payment
        vm.prank(user1);
        vm.expectRevert(DiamondGenesisPass.InsufficientPayment.selector);
        nft.whitelistMint{value: PUBLIC_MINT_PRICE}(2, proof); // Should be 2 * PUBLIC_MINT_PRICE
    }
    
    // Test successful whitelist mint
    function testWhitelistMintSuccess() public {
        // Get valid proof for user1
        bytes32[] memory proof = getProof(user1, 2);
        
        // Initial balances
        uint256 adminBalanceBefore = admin.balance;
        uint256 user1BalanceBefore = user1.balance;
        
        // Mint tokens
        vm.prank(user1);
        nft.whitelistMint{value: PUBLIC_MINT_PRICE * 2}(2, proof);
        
        // Verify token ownership and balances
        assertEq(nft.ownerOf(1), user1);
        assertEq(nft.ownerOf(2), user1);
        assertEq(nft.totalSupply(), 2);
        assertEq(user1.balance, user1BalanceBefore - (PUBLIC_MINT_PRICE * 2));
        assertEq(admin.balance, adminBalanceBefore + (PUBLIC_MINT_PRICE * 2));
        
        // Verify minters are set correctly
        assertEq(nft.minterOf(1), user1);
        assertEq(nft.minterOf(2), user1);
        
        // Verify claimed status
        assertTrue(nft.isWhitelistClaimed(user1));
    }
    
    // Test whitelist mint attempt after already claimed (should fail)
    function testWhitelistMintAlreadyClaimed() public {
        // First successful mint
        bytes32[] memory proof = getProof(user1, 2);
        vm.prank(user1);
        nft.whitelistMint{value: PUBLIC_MINT_PRICE * 2}(2, proof);
        
        // Try to mint again
        vm.prank(user1);
        vm.expectRevert(DiamondGenesisPass.AddressAlreadyClaimed.selector);
        nft.whitelistMint{value: PUBLIC_MINT_PRICE * 2}(2, proof);
    }
    
    // Test owner-only mint functions (mintOwner)
    function testMintOwnerPermissions() public {
        // Admin should be able to mint
        vm.prank(admin);
        nft.mintOwner(user1);
        assertEq(nft.ownerOf(1), user1);
        
        // Service account should be able to mint
        vm.prank(service);
        nft.mintOwner(user2);
        assertEq(nft.ownerOf(2), user2);
        
        // Regular user should not be able to mint
        vm.prank(user3);
        vm.expectRevert(DiamondGenesisPass.CallerIsNotAdminOrServiceAccount.selector);
        nft.mintOwner(user3);
    }
    
    // Test owner-only mint functions (safeMintOwner)
    function testSafeMintOwnerPermissions() public {
        // Admin should be able to mint
        vm.prank(admin);
        nft.safeMintOwner(user1);
        assertEq(nft.ownerOf(1), user1);
        
        // Service account should be able to mint
        vm.prank(service);
        nft.safeMintOwner(user2);
        assertEq(nft.ownerOf(2), user2);
        
        // Regular user should not be able to mint
        vm.prank(user3);
        vm.expectRevert(DiamondGenesisPass.CallerIsNotAdminOrServiceAccount.selector);
        nft.safeMintOwner(user3);
    }
    
    // Test reaching max supply
    function testMintToMaxSupply() public {
        // Enable public minting
        vm.prank(admin);
        nft.setPublicMintActive(true);
        
        // Mint tokens until we reach MAX_SUPPLY - 1
        for (uint256 i = 1; i < MAX_SUPPLY; i++) {
            vm.prank(admin);
            nft.mintOwner(user1);
        }
        
        assertEq(nft.totalSupply(), MAX_SUPPLY - 1);
        
        // Mint the last token
        vm.prank(admin);
        nft.mintOwner(user1);
        
        assertEq(nft.totalSupply(), MAX_SUPPLY);
        
        // Try to mint one more (should fail)
        vm.prank(admin);
        vm.expectRevert(DiamondGenesisPass.MaxSupplyExceeded.selector);
        nft.mintOwner(user1);
    }
    
    // Test admin functions
    function testAdminFunctions() public {
        // Set public mint status (non-admin should fail)
        vm.prank(user1);
        vm.expectRevert();
        nft.setPublicMintActive(true);
        
        // Admin can set public mint status
        vm.prank(admin);
        nft.setPublicMintActive(true);
        
        // Set merkle root (non-admin should fail)
        bytes32 newRoot = keccak256(abi.encodePacked("new root"));
        vm.prank(user1);
        vm.expectRevert();
        nft.setMerkleRoot(newRoot);
        
        // Admin can set merkle root
        vm.prank(admin);
        nft.setMerkleRoot(newRoot);
        
        // Burn token (only owner should be able to burn)
        vm.prank(admin);
        nft.mintOwner(user1);
        
        vm.prank(user1);
        vm.expectRevert();
        nft.burn(1);
        
        vm.prank(admin);
        nft.burn(1);
        
        vm.expectRevert("ERC721: invalid token ID");
        nft.ownerOf(1);
    }
    
    // Test recordSale permissions
    function testRecordSalePermissions() public {
        // Mint a token
        vm.prank(admin);
        nft.mintOwner(user1);
        
        // Non-admin/service should not be able to record sale
        vm.prank(user1);
        vm.expectRevert(DiamondGenesisPass.CallerIsNotAdminOrServiceAccount.selector);
        nft.recordSale(1, 1 ether);
        
        // Admin should be able to record sale
        vm.prank(admin);
        nft.recordSale(1, 1 ether);
        
        // Service account should be able to record sale
        vm.prank(service);
        nft.recordSale(1, 2 ether);
        
        // Cannot record sale for non-existent token
        vm.prank(admin);
        vm.expectRevert("Token does not exist");
        nft.recordSale(999, 1 ether);
    }
    
    // Test tokenURI functionality
    function testTokenURI() public {
        // Mint a token
        vm.prank(admin);
        nft.mintOwner(user1);
        
        // Set base URI and suffix
        vm.prank(admin);
        nft.setBaseURI("https://api.example.com/token/");
        vm.prank(admin);
        nft.setSuffixURI(".json");
        
        // Check token URI
        assertEq(nft.tokenURI(1), "https://api.example.com/token/1.json");
        
        // Cannot get URI for non-existent token
        vm.expectRevert("ERC721Metadata: URI query for nonexistent token");
        nft.tokenURI(999);
    }
    
    // Test payment forwarding
    function testPaymentForwarding() public {
        // Enable public minting
        vm.prank(admin);
        nft.setPublicMintActive(true);
        
        // Track initial balance
        uint256 adminBalanceBefore = admin.balance;
        
        // User mints a token
        vm.prank(user1);
        nft.mint{value: PUBLIC_MINT_PRICE}(user1);
        
        // Verify admin received the payment
        assertEq(admin.balance, adminBalanceBefore + PUBLIC_MINT_PRICE);
        
        // Transfer ownership to user2
        vm.prank(admin);
        nft.transferOwnership(user2);
        
        // Track user2's initial balance
        uint256 user2BalanceBefore = user2.balance;
        
        // Another user mints a token
        vm.prank(user3);
        nft.mint{value: PUBLIC_MINT_PRICE}(user3);
        
        // Verify the new owner (user2) received the payment
        assertEq(user2.balance, user2BalanceBefore + PUBLIC_MINT_PRICE);
    }
    
    // Test role management
    function testRoleManagement() public {
        // Admin should be able to grant roles
        vm.prank(admin);
        nft.grantRole(nft.SERVICE_ACCOUNT_ROLE(), user3);
        
        // New service account should be able to use privileged functions
        vm.prank(user3);
        nft.mintOwner(user2);
        
        // Admin should be able to revoke roles
        vm.prank(admin);
        nft.revokeRole(nft.SERVICE_ACCOUNT_ROLE(), user3);
        
        // Revoked account should not be able to use privileged functions
        vm.prank(user3);
        vm.expectRevert(DiamondGenesisPass.CallerIsNotAdminOrServiceAccount.selector);
        nft.mintOwner(user2);
    }
} 