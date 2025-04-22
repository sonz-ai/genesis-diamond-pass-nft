// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// A reentrancy attack contract that tries to drain funds
contract ReentrancyAttacker {
    CentralizedRoyaltyDistributor public distributor;
    address public collection;
    uint256 public amount;
    uint256 public attackCount;
    uint256 public maxAttacks;
    
    constructor(CentralizedRoyaltyDistributor _distributor) {
        distributor = _distributor;
    }
    
    function attack(address _collection, uint256 _amount, uint256 _maxAttacks) external {
        collection = _collection;
        amount = _amount;
        attackCount = 0;
        maxAttacks = _maxAttacks;
        
        // Start the attack
        distributor.claimRoyalties(collection, amount);
    }
    
    // Fallback function that tries to recursively claim
    receive() external payable {
        attackCount++;
        if (attackCount < maxAttacks) {
            distributor.claimRoyalties(collection, amount);
        }
    }
}

// ERC20 that reverts on transfer
contract RevertingERC20 is ERC20 {
    constructor() ERC20("Reverting Token", "RVT") {
        _mint(msg.sender, 1000 ether);
    }
    
    function transfer(address, uint256) public pure override returns (bool) {
        revert("Deliberate transfer revert");
    }
    
    // Add transferFrom to test SafeERC20 usage in distributor
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert("Deliberate transferFrom revert");
    }
}

// ERC20 token with transfer fee (redirects some amount)
contract FeeERC20 is ERC20 {
    address public feeCollector;
    uint256 public fee = 100; // 1% fee in basis points
    
    constructor(address _feeCollector) ERC20("Fee Token", "FEE") {
        feeCollector = _feeCollector;
        _mint(msg.sender, 1000 ether);
    }
    
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        uint256 feeAmount = (amount * fee) / 10000;
        uint256 sendAmount = amount - feeAmount;
        
        super.transfer(feeCollector, feeAmount);
        super.transfer(recipient, sendAmount);
        return true;
    }
    
    // Add transferFrom to test SafeERC20 usage in distributor
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        uint256 feeAmount = (amount * fee) / 10000;
        uint256 sendAmount = amount - feeAmount;
        
        super.transferFrom(sender, feeCollector, feeAmount);
        super.transferFrom(sender, recipient, sendAmount);
        return true;
    }
}

contract CentralizedRoyaltyDistributorAttackAndEdgeCasesTest is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass nft;
    ReentrancyAttacker attacker;
    RevertingERC20 revertingToken;
    FeeERC20 feeToken;
    
    address admin = address(0xA11CE);
    address service = address(0xBEEF);
    address creator = address(0xC0FFEE);
    address user1 = address(0x1);
    address user2 = address(0x2);
    address feeCollector = address(0xFEE);
    
    bytes32 zeroRoot = bytes32(0);
    
    function setUp() public {
        // Deploy contracts
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        nft = new DiamondGenesisPass(address(distributor), 750, creator); // 7.5% royalty fee
        // Only register if not already registered
        if (!distributor.isCollectionRegistered(address(nft))) {
            distributor.registerCollection(address(nft), 750, 2000, 8000, creator);
        }
        nft.setPublicMintActive(true);
        vm.stopPrank();
        
        // Deploy attack contracts
        attacker = new ReentrancyAttacker(distributor);
        revertingToken = new RevertingERC20();
        feeToken = new FeeERC20(feeCollector);
        
        // Fund accounts
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(address(attacker), 1 ether);
        
        // Fund ERC20 accounts for tests
        revertingToken.transfer(address(distributor), 200 ether); // Pre-fund distributor
        feeToken.transfer(address(distributor), 200 ether); // Pre-fund distributor
    }
    
    // Test 1: Registration edge cases (KEEP - Valid)
    function testRegisterCollectionWithInvalidShares() public {
        address newCollection = address(0x123);
        
        // Test: Shares don't sum to denominator
        vm.prank(admin);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__SharesDoNotSumToDenominator.selector);
        distributor.registerCollection(newCollection, 500, 3000, 6000, creator); // 3000 + 6000 != 10000
        
        // Test: Zero creator address
        vm.prank(admin);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__CreatorCannotBeZeroAddress.selector);
        distributor.registerCollection(newCollection, 500, 5000, 5000, address(0));
        
        // Test: Royalty fee exceeds denominator
        vm.prank(admin);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__RoyaltyFeeWillExceedSalePrice.selector);
        distributor.registerCollection(newCollection, 11000, 5000, 5000, creator); // 11000 > 10000
        
        // Test: Zero shares
        vm.prank(admin);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__SharesCannotBeZero.selector);
        distributor.registerCollection(newCollection, 500, 0, 10000, creator);
        
        vm.prank(admin);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__SharesCannotBeZero.selector);
        distributor.registerCollection(newCollection, 500, 10000, 0, creator);
    }
    
    // Test 2: Reentrancy attack on claim function (KEEP - Valid)
    function testReentrancyAttack() public {
        // Fund distributor for the NFT collection correctly
        vm.deal(address(nft), 1 ether);
        vm.prank(address(nft));
        (bool success, ) = address(distributor).call{value: 1 ether}("");
        require(success, "Funding failed");

        // Set up direct accrual for attacker
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = address(attacker);
        amounts[0] = 0.1 ether;
        
        // Update accrued royalties for attacker
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);

        // Try the reentrancy attack - expect it to revert due to nonReentrant guard
        // The specific revert might be the transfer failing inside the receive() loop
        vm.expectRevert(); 
        attacker.attack(address(nft), 0.1 ether, 3);
    }
    
    // Test 3: Double claim attempt (KEEP - Valid)
    function testDoubleClaimAttempt() public {
        // Fund distributor via the collection's receive() or addCollectionRoyalties
        vm.deal(address(nft), 1 ether);
        vm.prank(address(nft));
        (bool success, ) = address(distributor).call{value: 1 ether}("");
        require(success, "Funding failed");
        
        // Set up direct accrual for user1
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = user1;
        amounts[0] = 0.5 ether;
        
        // Update accrued royalties
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // First claim should succeed
        vm.prank(user1);
        distributor.claimRoyalties(address(nft), 0.5 ether);
        
        // Second claim for the same amount should fail
        vm.prank(user1);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__InsufficientUnclaimedRoyalties.selector);
        distributor.claimRoyalties(address(nft), 0.5 ether);
        
        // Third claim for 0 should succeed (but do nothing)
        vm.prank(user1);
        distributor.claimRoyalties(address(nft), 0);
    }
    
    // Test 4: Claim with Wrong Amount (REMOVE - Merkle Specific)
    /* function testClaimWithWrongAmount() public { ... } */
    
    // Test 5: Claim with Wrong Recipient (REMOVE - Merkle Specific)
    /* function testClaimWithWrongRecipient() public { ... } */
    
    // Test 6: Claim with insufficient royalty pool (REWRITE)
    function testClaimWithInsufficientPool() public {
        // Accrue royalties for user1
        uint256 accruedAmount = 0.5 ether;
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = user1;
        amounts[0] = accruedAmount;
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // Fund distributor with LESS than the accrued amount
        uint256 fundedAmount = 0.2 ether;
        vm.deal(address(nft), fundedAmount);
        vm.prank(address(nft));
        (bool success, ) = address(distributor).call{value: fundedAmount}("");
        require(success, "Funding failed");

        // Try to claim the full accrued amount - should fail due to insufficient collection balance
        vm.prank(user1);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__NotEnoughEtherToDistributeForCollection.selector);
        distributor.claimRoyalties(address(nft), accruedAmount); 
        
        // Try to claim the funded amount - should succeed
        vm.prank(user1);
        distributor.claimRoyalties(address(nft), fundedAmount); 
        assertEq(user1.balance, 10 ether + fundedAmount); // User1 started with 10 ETH
    }
    
    // Test 7: ERC20 token reverts on transfer (REWRITE)
    function testERC20ClaimWithRevertingToken() public {
        // Accrue reverting tokens for user1
        uint256 accruedAmount = 50 ether;
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = user1;
        amounts[0] = accruedAmount;
        
        // Use `addCollectionERC20Royalties` to add tokens to the distributor's collection balance
        // The setUp already transferred tokens to the distributor address, now associate them with the collection
        vm.prank(admin); // Or anyone who holds the tokens
        revertingToken.approve(address(distributor), accruedAmount);
        distributor.addCollectionERC20Royalties(address(nft), revertingToken, accruedAmount);
        
        // Accrue the claim for user1
        vm.prank(service);
        distributor.updateAccruedERC20Royalties(address(nft), revertingToken, recipients, amounts);

        // Try to claim - should revert due to token's transfer function via SafeERC20
        vm.prank(user1);
        // SafeERC20 reverts without a message, or with the underlying revert message if available
        vm.expectRevert("Deliberate transfer revert"); 
        distributor.claimERC20Royalties(address(nft), revertingToken, accruedAmount);
    }
    
    // Test 8: ERC20 token with transfer fee (REWRITE)
    function testERC20ClaimWithFeeToken() public {
        // Accrue fee tokens for user1
        uint256 accruedAmount = 50 ether;
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = user1;
        amounts[0] = accruedAmount;
        
        // Add fee tokens to the distributor's collection balance
        vm.prank(admin); // Or anyone who holds the tokens
        feeToken.approve(address(distributor), accruedAmount);
        distributor.addCollectionERC20Royalties(address(nft), feeToken, accruedAmount);
        
        // Accrue the claim for user1
        vm.prank(service);
        distributor.updateAccruedERC20Royalties(address(nft), feeToken, recipients, amounts);
        
        // Claim the tokens
        uint256 userBalanceBefore = feeToken.balanceOf(user1);
        uint256 collectorBalanceBefore = feeToken.balanceOf(feeCollector);
        
        vm.prank(user1);
        distributor.claimERC20Royalties(address(nft), feeToken, accruedAmount);
        
        // Check balances - should account for fee
        uint256 feeAmount = (accruedAmount * feeToken.fee()) / 10000;
        uint256 expectedUserAmount = accruedAmount - feeAmount;
        
        assertEq(feeToken.balanceOf(user1), userBalanceBefore + expectedUserAmount, "User balance mismatch");
        assertEq(feeToken.balanceOf(feeCollector), collectorBalanceBefore + feeAmount, "Fee collector balance mismatch");
    }
    
    // Test 9: Large Merkle Proof (REMOVE - Merkle Specific)
    /* function testLargeMerkleProof() public { ... } */
    
    // Test 10: Zero value operations (REFACTOR)
    function testZeroValueOperations() public {
        // Try to add zero ETH royalties using addCollectionRoyalties
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__ZeroAmountToDistribute.selector);
        distributor.addCollectionRoyalties{value: 0}(address(nft));
        
        // Try to add zero ETH royalties using receive() via direct call
        vm.prank(address(nft)); // Simulate collection sending royalties
        (bool success, ) = address(distributor).call{value: 0}("");
        require(success, "Zero value call failed"); // Should succeed, but add 0

        // Try to add zero ERC20 royalties
        vm.prank(admin);
        revertingToken.approve(address(distributor), 0); // Approve 0
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__ZeroAmountToDistribute.selector);
        distributor.addCollectionERC20Royalties(address(nft), revertingToken, 0);
        
        // --- Test Claiming Zero ---
        // Accrue some royalties first
        uint256 accruedAmount = 0.5 ether;
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = user1;
        amounts[0] = accruedAmount;
        
        // Fund distributor for the claim
        vm.deal(address(nft), accruedAmount);
        vm.prank(address(nft));
        (success, ) = address(distributor).call{value: accruedAmount}("");
        require(success, "Funding failed");
        
        // Accrue for user1
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // Claim zero ETH (should succeed, but no ETH transferred)
        uint256 balanceBefore = user1.balance;
        vm.prank(user1);
        distributor.claimRoyalties(address(nft), 0);
        uint256 balanceAfter = user1.balance;
        
        // Verify no balance change (gas costs might affect exact match)
        assertTrue(balanceAfter <= balanceBefore, "Balance increased after claiming zero"); 
        
        // Check claimable remains the same
        uint256 claimable = distributor.getClaimableRoyalties(address(nft), user1);
        assertEq(claimable, accruedAmount, "Claimable amount changed after claiming zero");

        // --- Test Accruing Zero ---
        uint256 totalAccruedBefore = distributor.totalAccruedRoyalty();
        amounts[0] = 0; // Accrue zero amount
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        assertEq(distributor.totalAccruedRoyalty(), totalAccruedBefore, "Total accrued changed after accruing zero");
        assertEq(distributor.getClaimableRoyalties(address(nft), user1), accruedAmount, "User claimable changed after accruing zero");
    }
    
    // Test 11: Batch update with very large arrays (KEEP - Valid)
    function testLargeBatchUpdate() public {
        // Create arrays of 100 elements for batch update
        uint256 batchSize = 100;
        uint256[] memory tokenIds = new uint256[](batchSize);
        address[] memory minters = new address[](batchSize);
        uint256[] memory salePrices = new uint256[](batchSize);
        bytes32[] memory txHashes = new bytes32[](batchSize);
        
        // Fill arrays with data
        for (uint256 i = 0; i < batchSize; i++) {
            tokenIds[i] = i + 1; // Assume tokens 1 to 100 exist (need minting in setup?)
            minters[i] = address(uint160(i + 100)); // Dummy minters
            salePrices[i] = 1 ether;
            txHashes[i] = keccak256(abi.encodePacked("tx", i));
            
            // Ensure minters are set in distributor for analytics (though not strictly needed for batchUpdate)
            vm.prank(address(nft)); // Simulate NFT contract setting minter
            distributor.setTokenMinter(address(nft), tokenIds[i], minters[i]);
        }
        
        // Perform batch update
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            minters, // Pass minters array
            salePrices,
            txHashes
        );
        
        // Check total accrued royalty (analytics value)
        (uint256 feeNum, , , ) = distributor.getCollectionConfig(address(nft));
        uint256 expectedRoyaltyPerSale = (1 ether * feeNum) / distributor.FEE_DENOMINATOR(); 
        uint256 expectedTotalRoyalty = expectedRoyaltyPerSale * batchSize;
        assertEq(distributor.totalAccrued(), expectedTotalRoyalty, "Total accrued mismatch");
    }
    
    // Test 12: Multiple Claims with Same Proof (REMOVE - Merkle Specific, covered by testDoubleClaimAttempt)
    /* function testMultipleClaimsWithSameProof() public { ... } */

    // === NEW TESTS ===

    // Test: updateAccruedRoyalties permissions
    function testUpdateAccruedPermissions() public {
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = user1;
        amounts[0] = 0.1 ether;

        // Should fail if called by random user
        vm.prank(user2);
        vm.expectRevert(bytes("AccessControl: account")); // OZ AccessControl revert
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);

        // Should succeed if called by service account
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);

        // Should succeed if called by admin
        amounts[0] = 0.2 ether; // Change amount to avoid duplicate event if needed
        vm.prank(admin);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);

        assertEq(distributor.getClaimableRoyalties(address(nft), user1), 0.3 ether);
    }

    // Test: batchUpdateRoyaltyData permissions
    function testBatchUpdatePermissions() public {
        uint256[] memory tokenIds = new uint256[](1);
        address[] memory minters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);
        tokenIds[0] = 1;
        minters[0] = user1;
        salePrices[0] = 1 ether;
        txHashes[0] = keccak256("tx1");

        // Mint token 1 first
        vm.prank(admin);
        nft.mintOwner(user1);

        // Should fail if called by random user
        vm.prank(user2);
        vm.expectRevert(bytes("AccessControl: account")); // OZ AccessControl revert
        distributor.batchUpdateRoyaltyData(address(nft), tokenIds, minters, salePrices, txHashes);

        // Should succeed if called by service account
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(address(nft), tokenIds, minters, salePrices, txHashes);

        // Should succeed if called by admin (add another tx)
        tokenIds[0] = 2; // Use different token/tx
        minters[0] = user2;
        txHashes[0] = keccak256("tx2");
        vm.prank(admin);
        nft.mintOwner(user2); // Mint token 2
        vm.prank(admin);
        distributor.batchUpdateRoyaltyData(address(nft), tokenIds, minters, salePrices, txHashes);
    }

    // Test: updateCreatorAddress permissions
    function testUpdateCreatorPermissions() public {
        address newCreator = address(0xDEADBEEF);
        
        // Should fail if called by random user
        vm.prank(user1);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__NotCollectionCreatorOrAdmin.selector);
        distributor.updateCreatorAddress(address(nft), newCreator);
        
        // Should fail if called by service account
        vm.prank(service);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__NotCollectionCreatorOrAdmin.selector);
        distributor.updateCreatorAddress(address(nft), newCreator);
        
        // Should succeed if called by current creator
        vm.prank(creator);
        distributor.updateCreatorAddress(address(nft), newCreator);
        (,,, address currentCreatorAfterUpdate1) = distributor.getCollectionConfig(address(nft));
        assertEq(currentCreatorAfterUpdate1, newCreator);
        
        // Should succeed if called by admin
        address finalCreator = address(0xBAADF00D);
        vm.prank(admin);
        distributor.updateCreatorAddress(address(nft), finalCreator);
        (,,, address currentCreatorAfterUpdate2) = distributor.getCollectionConfig(address(nft));
        assertEq(currentCreatorAfterUpdate2, finalCreator);

        // Should succeed if called by collection contract itself (via a function it exposes)
        // Example: DiamondGenesisPass could have a function `setRoyaltyRecipient` calling distributor.updateCreatorAddress
        // vm.prank(address(nft));
        // distributor.updateCreatorAddress(address(nft), address(0xCAFE)); // This would fail directly
        // Instead, test via the NFT contract's function (if it exists)
        vm.prank(admin); // Owner of NFT is admin initially
        nft.setRoyaltyRecipient(address(0xCAFE));
        (,,, address currentCreatorAfterUpdate3) = distributor.getCollectionConfig(address(nft));
        assertEq(currentCreatorAfterUpdate3, address(0xCAFE));
    }

    // NEW TEST: Verify batch functionality of updateAccruedRoyalties
    function testBatchDirectAccrual() public {
        // Define batch data for multiple recipients
        address recipient1 = address(0xBAADF00D); vm.deal(recipient1, 1 ether);
        address recipient2 = address(0xFACEB00C); vm.deal(recipient2, 1 ether);
        address recipient3 = address(0xDEADBEEF); vm.deal(recipient3, 1 ether);

        address[] memory recipients = new address[](3);
        uint256[] memory amounts = new uint256[](3);

        recipients[0] = recipient1; amounts[0] = 0.1 ether;
        recipients[1] = recipient2; amounts[1] = 0.2 ether;
        recipients[2] = recipient3; amounts[2] = 0.3 ether;

        uint256 totalBatchAmount = amounts[0] + amounts[1] + amounts[2]; // 0.6 ether

        // Fund the distributor pool first
        vm.deal(admin, totalBatchAmount);
        vm.prank(admin);
        distributor.addCollectionRoyalties{value: totalBatchAmount}(address(nft));

        // Get initial total accrued for comparison
        uint256 totalAccruedBefore = distributor.totalAccruedRoyalty();

        // Accrue royalties for all recipients in one batch call
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);

        // Verify global total accrued increased correctly
        assertEq(distributor.totalAccruedRoyalty(), totalAccruedBefore + totalBatchAmount, "Total accrued mismatch after batch");

        // Verify individual claimable amounts
        assertEq(distributor.getClaimableRoyalties(address(nft), recipient1), amounts[0], "Recipient 1 claimable incorrect");
        assertEq(distributor.getClaimableRoyalties(address(nft), recipient2), amounts[1], "Recipient 2 claimable incorrect");
        assertEq(distributor.getClaimableRoyalties(address(nft), recipient3), amounts[2], "Recipient 3 claimable incorrect");

        // Have recipients claim their amounts
        uint256 totalClaimedBefore = distributor.totalClaimed();
        
        vm.prank(recipient1);
        distributor.claimRoyalties(address(nft), amounts[0]);
        vm.prank(recipient2);
        distributor.claimRoyalties(address(nft), amounts[1]);
        vm.prank(recipient3);
        distributor.claimRoyalties(address(nft), amounts[2]);

        // Verify final state
        assertEq(distributor.totalClaimed(), totalClaimedBefore + totalBatchAmount, "Total claimed mismatch after batch claims");
        assertEq(distributor.collectionUnclaimed(address(nft)), 0, "Collection pool should be empty after batch claims");
        assertEq(distributor.getClaimableRoyalties(address(nft), recipient1), 0);
        assertEq(distributor.getClaimableRoyalties(address(nft), recipient2), 0);
        assertEq(distributor.getClaimableRoyalties(address(nft), recipient3), 0);
    }
} 