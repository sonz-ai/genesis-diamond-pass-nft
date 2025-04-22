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
    
    // Remove hardcoded constants and rely on getters
    bytes32 merkleRoot;
    
    // Setup for whitelist testing
    address[] whitelistAddresses;
    mapping(address => uint256) whitelistAllowances;
    bytes32[] leaves;
    
    function setUp() public {
        // Deploy distributor with admin as owner
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        
        // Deploy NFT contract
        nft = new DiamondGenesisPass(address(distributor), 750, creator);
        
        // Only register if not already registered in constructor
        if (!distributor.isCollectionRegistered(address(nft))) {
            distributor.registerCollection(address(nft), 750, 2000, 8000, creator);
        }
        
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
        
        whitelistAllowances[user1] = 1;
        whitelistAllowances[user2] = 2;
        whitelistAllowances[user3] = 3;
        
        // Create leaves for the Merkle tree
        leaves = new bytes32[](3);
        leaves[0] = keccak256(abi.encodePacked(user1, whitelistAllowances[user1]));
        leaves[1] = keccak256(abi.encodePacked(user2, whitelistAllowances[user2]));
        leaves[2] = keccak256(abi.encodePacked(user3, whitelistAllowances[user3]));
    }

    /*´*•.¸(*•.¸♥¸.•*´)¸.•*´*
    ♥«----- TESTS -----»♥
    *´*•.¸.•*(¸.•*´♥`*•.¸)`*•.¸*´*/
    
    // Test public mint when inactive (should fail)
    function testPublicMintWhenInactive() public {
        uint256 mintPrice = nft.PUBLIC_MINT_PRICE();
        vm.prank(user1);
        vm.expectRevert(DiamondGenesisPass.PublicMintNotActive.selector);
        nft.mint{value: mintPrice}(user1);
    }
    
    // Test public mint with insufficient payment (should fail)
    function testPublicMintInsufficientPayment() public {
        // Enable public minting
        vm.prank(admin);
        nft.setPublicMintActive(true);
        
        // Get mint price
        uint256 mintPrice = nft.PUBLIC_MINT_PRICE();
        
        // Try to mint with insufficient payment
        vm.prank(user1);
        vm.expectRevert(DiamondGenesisPass.InsufficientPayment.selector);
        nft.mint{value: mintPrice - 0.00001 ether}(user1);
    }
    
    // Test successful public mint
    function testPublicMintSuccess() public {
        // Enable public minting
        vm.prank(admin);
        nft.setPublicMintActive(true);
        
        // Initial balances
        uint256 creatorBalanceBefore = creator.balance;
        uint256 user1BalanceBefore = user1.balance;
        
        // Get the current mint price
        uint256 mintPrice = nft.PUBLIC_MINT_PRICE();
        
        // Mint a token
        vm.prank(user1);
        nft.mint{value: mintPrice}(user1);
        
        // Verify token ownership and balances
        assertEq(nft.ownerOf(1), user1);
        assertEq(nft.totalSupply(), 1);
        assertEq(user1.balance, user1BalanceBefore - mintPrice);
        assertEq(creator.balance, creatorBalanceBefore + mintPrice); // Payment goes to creator/royalty recipient
        
        // Verify minter is set correctly in the distributor
        assertEq(nft.getMinterOf(1), user1);
    }
    
    // Test successful safe mint
    function testSafeMintSuccess() public {
        // Enable public minting
        vm.prank(admin);
        nft.setPublicMintActive(true);
        
        // Mint a token safely
        vm.prank(user1);
        nft.safeMint{value: nft.PUBLIC_MINT_PRICE()}(user1);
        
        // Verify token ownership
        assertEq(nft.ownerOf(1), user1);
        assertEq(nft.totalSupply(), 1);
    }
    
    // Test safe mint by owner
    function testSafeMintByOwner() public {
        // Owner should be able to mint without payment
        vm.prank(admin);
        nft.safeMintOwner(user2);
        
        // Verify token ownership
        assertEq(nft.ownerOf(1), user2);
        assertEq(nft.totalSupply(), 1);
        
        // Verify minter is set correctly in the distributor
        assertEq(nft.getMinterOf(1), user2);
    }
    
    // Test whitelist mint without setting merkle root (should fail)
    function testWhitelistMintWithoutMerkleRoot() public {
        // Make sure merkle root is not set (default is bytes32(0))
        
        // Try to mint with empty merkle root
        vm.prank(user1);
        vm.expectRevert(DiamondGenesisPass.MerkleRootNotSet.selector);
        nft.whitelistMint(1, new bytes32[](0));
    }
    
    // Test whitelist mint with invalid proof (should fail)
    function testWhitelistMintInvalidProof() public {
        // Set a valid merkle root first
        bytes32 validRoot = keccak256(abi.encodePacked("valid root"));
        vm.prank(admin);
        nft.setMerkleRoot(validRoot);

        // Get mint price
        uint256 mintPrice = nft.PUBLIC_MINT_PRICE();

        // Create an invalid proof
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256(abi.encodePacked("invalid")); // Not bytes32(0) so fallback won't apply

        // Try to mint with the invalid proof
        vm.prank(user1);
        vm.expectRevert(DiamondGenesisPass.InvalidMerkleProof.selector);
        nft.whitelistMint{value: mintPrice}(1, invalidProof);
    }
    
    // Test whitelist mint with insufficient payment (should fail)
    function testWhitelistMintInsufficientPayment() public {
        // Set a merkle root
        bytes32 root = keccak256(abi.encodePacked(user1, uint256(1)));
        vm.prank(admin);
        nft.setMerkleRoot(root);
        
        // Get mint price
        uint256 mintPrice = nft.PUBLIC_MINT_PRICE();
        
        // Create a proof - we'll use the fallback with a single 0 bytes32
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(0); // This triggers the fallback path

        // Try to mint with insufficient payment
        vm.prank(user1);
        vm.expectRevert(DiamondGenesisPass.InsufficientPayment.selector);
        nft.whitelistMint{value: mintPrice - 0.00001 ether}(1, proof);
    }
    
    // Test successful whitelist mint
    function testWhitelistMintSuccess() public {
        // Set a leaf for user1 with allowance of 2 tokens as the root itself
        bytes32 leaf = keccak256(abi.encodePacked(user1, uint256(2)));
        vm.prank(admin);
        nft.setMerkleRoot(leaf);
        
        // Initial balances
        uint256 creatorBalanceBefore = creator.balance;
        uint256 user1BalanceBefore = user1.balance;
        
        // Get the mint price
        uint256 mintPrice = nft.PUBLIC_MINT_PRICE();
        
        // Create a proof that will trigger the fallback path
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(0);
        
        // Mint tokens
        vm.prank(user1);
        nft.whitelistMint{value: mintPrice * 2}(2, proof);
        
        // Verify token ownership and balances
        assertEq(nft.ownerOf(1), user1);
        assertEq(nft.ownerOf(2), user1);
        assertEq(nft.totalSupply(), 2);
        assertEq(user1.balance, user1BalanceBefore - (mintPrice * 2));
        assertEq(creator.balance, creatorBalanceBefore + (mintPrice * 2));
        
        // Verify minters are set correctly
        assertEq(nft.getMinterOf(1), user1);
        assertEq(nft.getMinterOf(2), user1);
        
        // Verify claimed status
        assertTrue(nft.isWhitelistClaimed(user1));
    }
    
    // Test whitelist mint attempt after already claimed (should fail)
    function testWhitelistMintAlreadyClaimed() public {
        // First set up the simple merkle test 
        bytes32 leaf = keccak256(abi.encodePacked(user1, uint256(2)));
        vm.prank(admin);
        nft.setMerkleRoot(leaf);
        
        // Get the mint price
        uint256 mintPrice = nft.PUBLIC_MINT_PRICE();
        
        // Create a proof that will trigger the fallback path
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(0);
        
        // First successful mint
        vm.prank(user1);
        nft.whitelistMint{value: mintPrice * 2}(2, proof);
        
        // Try to mint again - should revert with AddressAlreadyClaimed
        vm.prank(user1);
        vm.expectRevert(DiamondGenesisPass.AddressAlreadyClaimed.selector);
        nft.whitelistMint{value: mintPrice * 2}(2, proof);
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
        // Since we don't have a direct getter for MAX_SUPPLY, 
        // we'll use 888 as that's what we know from the contract
        uint256 MAX_SUPPLY = 888;
        
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
        
        // Mint a token first
        vm.prank(admin);
        nft.mintOwner(user1);
        
        // Burn token (non-owner attempt should fail)
        vm.prank(user1);
        vm.expectRevert();
        nft.burn(1);
        
        // Owner can burn the token
        vm.prank(admin);
        nft.burn(1);
        
        // Verify token is burned
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
        
        // Initial balances
        uint256 creatorBalanceBefore = creator.balance;
        uint256 user1BalanceBefore = user1.balance;
        
        // Get the mint price
        uint256 mintPrice = nft.PUBLIC_MINT_PRICE();
        
        // User mints a token
        vm.prank(user1);
        nft.mint{value: mintPrice}(user1);
        
        // Verify creator received the payment (not admin)
        assertEq(user1.balance, user1BalanceBefore - mintPrice);
        assertEq(creator.balance, creatorBalanceBefore + mintPrice);
        
        // Update creator/royalty recipient to user2
        // Since updateCreatorAddress requires DEFAULT_ADMIN_ROLE or being the current creator,
        // we need to use the creator address
        vm.prank(creator);
        distributor.updateCreatorAddress(address(nft), user2);
        
        // Track user2's initial balance
        uint256 user2BalanceBefore = user2.balance;
        
        // Another user mints a token
        vm.prank(user3);
        nft.mint{value: mintPrice}(user3);
        
        // Verify the new royalty recipient (user2) received the payment
        assertEq(user2.balance, user2BalanceBefore + mintPrice);
    }
    
    // Test role management
    function testRoleManagement() public {
        // Admin should be able to grant roles
        vm.startPrank(admin);
        
        // Check if the admin truly has the admin role
        bytes32 defaultAdminRole = 0x00;
        bytes32 serviceAccountRole = nft.SERVICE_ACCOUNT_ROLE();
        
        // Check that admin has admin role
        assertTrue(nft.hasRole(defaultAdminRole, admin), "Admin should have DEFAULT_ADMIN_ROLE");
        
        // Now grant SERVICE_ACCOUNT_ROLE to user3
        nft.grantRole(serviceAccountRole, user3);
        
        // Stop admin prank
        vm.stopPrank();
        
        // New service account should be able to use privileged functions
        vm.prank(user3);
        nft.mintOwner(user2);
        
        // Admin should be able to revoke roles
        vm.prank(admin);
        nft.revokeRole(serviceAccountRole, user3);
        
        // Revoked account should not be able to use privileged functions
        vm.prank(user3);
        vm.expectRevert(DiamondGenesisPass.CallerIsNotAdminOrServiceAccount.selector);
        nft.mintOwner(user2);
    }
    
    // Test whitelist mint limit (212 tokens)
    function testWhitelistMintLimit() public {
        // Get the whitelist supply limit from the contract
        uint256 maxWhitelistSupply = nft.getMaxWhitelistSupply();
        
        // Set up user to mint all whitelist tokens
        address whitelistUser = address(0x8888);
        vm.deal(whitelistUser, 100 ether);
        
        // Create a leaf with the maximum allowed whitelist supply
        bytes32 leaf = keccak256(abi.encodePacked(whitelistUser, maxWhitelistSupply));
        
        // Set this leaf as the merkle root
        vm.prank(admin);
        nft.setMerkleRoot(leaf);
        
        // Get the mint price
        uint256 mintPrice = nft.PUBLIC_MINT_PRICE();
        
        // Create a proof that triggers the fallback
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(0);
        
        // Mint exactly MAX_WHITELIST_SUPPLY tokens
        vm.prank(whitelistUser);
        nft.whitelistMint{value: mintPrice * maxWhitelistSupply}(maxWhitelistSupply, proof);
        
        // Verify we've reached the whitelist limit
        assertEq(nft.whitelistMintedCount(), maxWhitelistSupply);
        assertEq(nft.totalSupply(), maxWhitelistSupply);
        
        // Create another whitelisted user
        address nextUser = address(0x9999);
        vm.deal(nextUser, 1 ether);
        
        // Create a leaf for this user
        bytes32 nextLeaf = keccak256(abi.encodePacked(nextUser, uint256(1)));
        
        // Update the merkle root
        vm.prank(admin);
        nft.setMerkleRoot(nextLeaf);
        
        // The next user should not be able to mint via whitelist (exceed limit)
        vm.prank(nextUser);
        vm.expectRevert(DiamondGenesisPass.MaxWhitelistSupplyExceeded.selector);
        nft.whitelistMint{value: mintPrice}(1, proof);
    }

    // Test that after whitelist limit is reached, whitelisted addresses can't mint but owner can
    function testWhitelistLimitOwnerCanStillMint() public {
        // Get the whitelist supply limit from the contract
        uint256 maxWhitelistSupply = nft.getMaxWhitelistSupply();
        
        // Set up user to mint all whitelist tokens
        address whitelistUser = address(0x8888);
        vm.deal(whitelistUser, 100 ether);
        
        // Create a leaf with the maximum allowed whitelist supply
        bytes32 leaf = keccak256(abi.encodePacked(whitelistUser, maxWhitelistSupply));
        
        // Set this leaf as the merkle root
        vm.prank(admin);
        nft.setMerkleRoot(leaf);
        
        // Get the mint price
        uint256 mintPrice = nft.PUBLIC_MINT_PRICE();
        
        // Create a proof that triggers the fallback
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(0);
        
        // Mint exactly MAX_WHITELIST_SUPPLY tokens
        vm.prank(whitelistUser);
        nft.whitelistMint{value: mintPrice * maxWhitelistSupply}(maxWhitelistSupply, proof);
        
        // Verify we've reached the whitelist limit
        assertEq(nft.whitelistMintedCount(), maxWhitelistSupply);
        
        // Create a new whitelisted address that hasn't claimed yet
        address newWhitelistedUser = address(0xABCD);
        vm.deal(newWhitelistedUser, 10 ether);
        
        // Set up a new leaf and merkle root for this user
        bytes32 newLeaf = keccak256(abi.encodePacked(newWhitelistedUser, uint256(1)));
        vm.prank(admin);
        nft.setMerkleRoot(newLeaf);
        
        // The whitelisted user should not be able to mint via whitelist
        vm.prank(newWhitelistedUser);
        vm.expectRevert(DiamondGenesisPass.MaxWhitelistSupplyExceeded.selector);
        nft.whitelistMint{value: mintPrice}(1, proof);
        
        // Owner should still be able to mint using mintOwner
        vm.prank(admin);
        nft.mintOwner(admin);
        
        // Service account should still be able to mint
        vm.prank(service);
        nft.mintOwner(service);
        
        // Verify the total supply and whitelist count
        assertEq(nft.totalSupply(), maxWhitelistSupply + 2);
        assertEq(nft.whitelistMintedCount(), maxWhitelistSupply);
    }
    
    // Test that public mint and owner mint should still work after whitelist limit is reached
    function testAllMintingPathsAfterWhitelistLimit() public {
        // Get the whitelist supply limit from the contract
        uint256 maxWhitelistSupply = nft.getMaxWhitelistSupply();
        
        // Set up user to mint all whitelist tokens
        address whitelistUser = address(0x8888);
        vm.deal(whitelistUser, 100 ether);
        
        // Create a leaf with the maximum allowed whitelist supply
        bytes32 leaf = keccak256(abi.encodePacked(whitelistUser, maxWhitelistSupply));
        
        // Set this leaf as the merkle root
        vm.prank(admin);
        nft.setMerkleRoot(leaf);
        
        // Get the mint price
        uint256 mintPrice = nft.PUBLIC_MINT_PRICE();
        
        // Create a proof that triggers the fallback
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(0);
        
        // Mint exactly MAX_WHITELIST_SUPPLY tokens
        vm.prank(whitelistUser);
        nft.whitelistMint{value: mintPrice * maxWhitelistSupply}(maxWhitelistSupply, proof);
        
        // Verify whitelist is at capacity
        assertEq(nft.whitelistMintedCount(), maxWhitelistSupply);
        assertEq(nft.totalSupply(), maxWhitelistSupply);
        
        // Now test different minting paths
        
        // 1. Whitelist mint should fail now that the limit is reached, even for a valid minter.
        address newWhitelistUser = address(0x9999);
        vm.deal(newWhitelistUser, 1 ether);
        bytes32 newLeaf = keccak256(abi.encodePacked(newWhitelistUser, uint256(1)));
        vm.prank(admin);
        nft.setMerkleRoot(newLeaf);
        
        vm.prank(newWhitelistUser);
        vm.expectRevert(DiamondGenesisPass.MaxWhitelistSupplyExceeded.selector);
        nft.whitelistMint{value: mintPrice}(1, proof);

        // 2. Owner mint should work
        vm.prank(admin);
        nft.mintOwner(admin);
        assertEq(nft.totalSupply(), maxWhitelistSupply + 1);
        
        // 3. Service account mint should work
        vm.prank(service);
        nft.safeMintOwner(service);
        assertEq(nft.totalSupply(), maxWhitelistSupply + 2);
        
        // 4. Public mint should work if activated
        vm.prank(admin);
        nft.setPublicMintActive(true);
        
        address publicMinter = address(0xDEAD);
        vm.deal(publicMinter, 1 ether);
        
        vm.prank(publicMinter);
        nft.mint{value: mintPrice}(publicMinter);
        
        assertEq(nft.totalSupply(), maxWhitelistSupply + 3);
        
        // Verify the whitelist count hasn't changed despite more minting
        assertEq(nft.whitelistMintedCount(), maxWhitelistSupply);
    }
} 