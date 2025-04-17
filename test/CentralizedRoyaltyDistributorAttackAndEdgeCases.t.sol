// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// A reentrancy attack contract that tries to drain funds
contract ReentrancyAttacker {
    CentralizedRoyaltyDistributor public distributor;
    bytes32[] public emptyProof;
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
        distributor.claimRoyaltiesMerkle(collection, address(this), amount, emptyProof);
    }
    
    // Fallback function that tries to recursively claim
    receive() external payable {
        attackCount++;
        if (attackCount < maxAttacks) {
            distributor.claimRoyaltiesMerkle(collection, address(this), amount, emptyProof);
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
        nft = new DiamondGenesisPass(address(distributor), 750, creator);
        distributor.registerCollection(address(nft), 750, 2000, 8000, creator);
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
    }
    
    // Test 1: Registration edge cases
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
    
    // Test 2: Reentrancy attack on claim function
    function testReentrancyAttack() public {
        // Fund distributor for the NFT collection
        vm.deal(address(this), 1 ether);
        distributor.addCollectionRoyalties{value: 1 ether}(address(nft));
        
        // Create a Merkle root with the attacker address as recipient
        bytes32 leaf = keccak256(abi.encodePacked(address(attacker), uint256(0.1 ether)));
        
        // Submit the Merkle root (simplified for testing)
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), leaf, 0.1 ether);
        
        // Try the reentrancy attack
        uint256 attackerBalanceBefore = address(attacker).balance;
        attacker.attack(address(nft), 0.1 ether, 3);
        uint256 attackerBalanceAfter = address(attacker).balance;
        
        // Verify that only one claim succeeded (non-reentrant)
        assertEq(attackerBalanceAfter - attackerBalanceBefore, 0.1 ether);
        assertEq(attacker.attackCount(), 1); // Only one successful attack
    }
    
    // Test 3: Double claim attempt
    function testDoubleClaimAttempt() public {
        // Fund distributor
        vm.deal(address(this), 1 ether);
        distributor.addCollectionRoyalties{value: 1 ether}(address(nft));
        
        // Create a simple Merkle root
        bytes32 leaf = keccak256(abi.encodePacked(user1, uint256(0.5 ether)));
        
        // Submit the Merkle root
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), leaf, 0.5 ether);
        
        // First claim should succeed
        vm.prank(user1);
        distributor.claimRoyaltiesMerkle(address(nft), user1, 0.5 ether, new bytes32[](0));
        
        // Second claim should fail
        vm.prank(user1);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__AlreadyClaimed.selector);
        distributor.claimRoyaltiesMerkle(address(nft), user1, 0.5 ether, new bytes32[](0));
    }
    
    // Test 4: Claim with valid proof but wrong amount
    function testClaimWithWrongAmount() public {
        // Fund distributor
        vm.deal(address(this), 1 ether);
        distributor.addCollectionRoyalties{value: 1 ether}(address(nft));
        
        // Create Merkle tree with two leaves
        bytes32 leaf1 = keccak256(abi.encodePacked(user1, uint256(0.3 ether)));
        bytes32 leaf2 = keccak256(abi.encodePacked(user2, uint256(0.2 ether)));
        bytes32 root = keccak256(abi.encodePacked(leaf1, leaf2));
        
        // Submit the Merkle root
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), root, 0.5 ether);
        
        // Create proof for user1
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leaf2;
        
        // Try to claim with wrong amount
        vm.prank(user1);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__InvalidProof.selector);
        distributor.claimRoyaltiesMerkle(address(nft), user1, 0.4 ether, proof); // 0.4 instead of 0.3
    }
    
    // Test 5: Claim with valid proof but wrong recipient
    function testClaimWithWrongRecipient() public {
        // Fund distributor
        vm.deal(address(this), 1 ether);
        distributor.addCollectionRoyalties{value: 1 ether}(address(nft));
        
        // Create Merkle tree with user1's address
        bytes32 leaf = keccak256(abi.encodePacked(user1, uint256(0.5 ether)));
        
        // Submit the Merkle root
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), leaf, 0.5 ether);
        
        // Try to claim as user2
        vm.prank(user2);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__InvalidProof.selector);
        distributor.claimRoyaltiesMerkle(address(nft), user2, 0.5 ether, new bytes32[](0));
    }
    
    // Test 6: Claim with insufficient royalty pool
    function testClaimWithInsufficientPool() public {
        // Fund distributor with less than needed
        vm.deal(address(this), 0.2 ether);
        distributor.addCollectionRoyalties{value: 0.2 ether}(address(nft));
        
        // Create a Merkle root for 0.5 ETH
        bytes32 leaf = keccak256(abi.encodePacked(user1, uint256(0.5 ether)));
        
        // Submit the Merkle root with excess amount (should fail)
        vm.prank(service);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__InsufficientBalanceForRoot.selector);
        distributor.submitRoyaltyMerkleRoot(address(nft), leaf, 0.5 ether);
        
        // Now submit with correct balance declaration
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), leaf, 0.2 ether);
        
        // Try to claim more than the pool has
        vm.prank(user1);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__InvalidProof.selector);
        distributor.claimRoyaltiesMerkle(address(nft), user1, 0.5 ether, new bytes32[](0));
    }
    
    // Test 7: ERC20 token reverts on transfer
    function testERC20ClaimWithRevertingToken() public {
        // Approve and add reverting tokens to distributor
        revertingToken.approve(address(distributor), 100 ether);
        distributor.addCollectionERC20Royalties(address(nft), revertingToken, 100 ether);
        
        // Create a Merkle root for ERC20 claim
        bytes32 leaf = keccak256(abi.encodePacked(user1, address(revertingToken), uint256(50 ether)));
        
        // Submit the Merkle root
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), leaf, 0);
        
        // Try to claim - should revert due to token's transfer function
        vm.prank(user1);
        vm.expectRevert("Deliberate transfer revert");
        distributor.claimERC20RoyaltiesMerkle(address(nft), user1, revertingToken, 50 ether, new bytes32[](0));
    }
    
    // Test 8: ERC20 token with transfer fee
    function testERC20ClaimWithFeeToken() public {
        // Approve and add fee tokens to distributor
        feeToken.approve(address(distributor), 100 ether);
        distributor.addCollectionERC20Royalties(address(nft), feeToken, 100 ether);
        
        // Create a Merkle root for ERC20 claim
        bytes32 leaf = keccak256(abi.encodePacked(user1, address(feeToken), uint256(50 ether)));
        
        // Submit the Merkle root
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), leaf, 0);
        
        // Claim the tokens
        vm.prank(user1);
        distributor.claimERC20RoyaltiesMerkle(address(nft), user1, feeToken, 50 ether, new bytes32[](0));
        
        // Check balance - should be less than claimed due to fee
        uint256 expectedAfterFee = 50 ether - ((50 ether * 100) / 10000); // 1% fee
        assertEq(feeToken.balanceOf(user1), expectedAfterFee);
        assertEq(feeToken.balanceOf(feeCollector), (50 ether * 100) / 10000); // fee collector got the fee
    }
    
    // Test 9: Claim with a very large Merkle proof (gas limit testing)
    function testLargeMerkleProof() public {
        // Fund distributor
        vm.deal(address(this), 1 ether);
        distributor.addCollectionRoyalties{value: 1 ether}(address(nft));
        
        // Create a large Merkle proof (20 elements)
        bytes32[] memory largeProof = new bytes32[](20);
        for (uint256 i = 0; i < 20; i++) {
            largeProof[i] = keccak256(abi.encodePacked(i));
        }
        
        // Create a fake root and leaf
        bytes32 root = keccak256(abi.encodePacked("root"));
        
        // Submit the Merkle root
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), root, 0.5 ether);
        
        // Try to claim with large proof (should fail due to invalid proof, but not out of gas)
        vm.prank(user1);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__InvalidProof.selector);
        distributor.claimRoyaltiesMerkle(address(nft), user1, 0.5 ether, largeProof);
    }
    
    // Test 10: Zero value operations
    function testZeroValueOperations() public {
        // Try to add zero royalties
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__ZeroAmountToDistribute.selector);
        distributor.addCollectionRoyalties{value: 0}(address(nft));
        
        // Try to add zero ERC20 royalties
        revertingToken.approve(address(distributor), 100 ether);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__ZeroAmountToDistribute.selector);
        distributor.addCollectionERC20Royalties(address(nft), revertingToken, 0);
        
        // Add some royalties and create a Merkle root
        vm.deal(address(this), 1 ether);
        distributor.addCollectionRoyalties{value: 1 ether}(address(nft));
        
        // Create a Merkle root for zero ETH (should work)
        bytes32 leaf = keccak256(abi.encodePacked(user1, uint256(0)));
        
        // Submit the Merkle root with zero amount
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), leaf, 0);
        
        // Claim zero ETH (should work, but no ETH transferred)
        uint256 balanceBefore = user1.balance;
        vm.prank(user1);
        distributor.claimRoyaltiesMerkle(address(nft), user1, 0, new bytes32[](0));
        uint256 balanceAfter = user1.balance;
        
        // Verify no balance change
        assertEq(balanceAfter, balanceBefore);
    }
    
    // Test 11: Batch update with very large arrays
    function testLargeBatchUpdate() public {
        // Create arrays of 100 elements for batch update
        uint256 batchSize = 100;
        uint256[] memory tokenIds = new uint256[](batchSize);
        address[] memory minters = new address[](batchSize);
        uint256[] memory salePrices = new uint256[](batchSize);
        uint256[] memory timestamps = new uint256[](batchSize);
        bytes32[] memory txHashes = new bytes32[](batchSize);
        
        // Fill arrays with data
        for (uint256 i = 0; i < batchSize; i++) {
            tokenIds[i] = i + 1;
            minters[i] = address(uint160(i + 1));
            salePrices[i] = 1 ether;
            timestamps[i] = block.timestamp;
            txHashes[i] = keccak256(abi.encodePacked("tx", i));
        }
        
        // Perform batch update
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            minters,
            salePrices,
            timestamps,
            txHashes
        );
        
        // Check total accrued royalty
        uint256 expectedRoyaltyPerSale = (1 ether * 750) / 10000; // 7.5% of 1 ETH
        uint256 expectedTotalRoyalty = expectedRoyaltyPerSale * batchSize;
        assertEq(distributor.totalAccrued(), expectedTotalRoyalty);
    }
    
    // Test 12: Multiple claim attempts with same proof for different recipients
    function testMultipleClaimsWithSameProof() public {
        // Fund distributor
        vm.deal(address(this), 1 ether);
        distributor.addCollectionRoyalties{value: 1 ether}(address(nft));
        
        // Create Merkle tree with two leaves
        bytes32 leaf1 = keccak256(abi.encodePacked(user1, uint256(0.5 ether)));
        bytes32 leaf2 = keccak256(abi.encodePacked(user2, uint256(0.3 ether)));
        bytes32 root = keccak256(abi.encodePacked(leaf1, leaf2));
        
        // Submit the Merkle root
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), root, 0.8 ether);
        
        // Create proofs
        bytes32[] memory proof1 = new bytes32[](1);
        proof1[0] = leaf2;
        
        bytes32[] memory proof2 = new bytes32[](1);
        proof2[0] = leaf1;
        
        // User1 claims with correct proof
        vm.prank(user1);
        distributor.claimRoyaltiesMerkle(address(nft), user1, 0.5 ether, proof1);
        
        // User2 claims with correct proof
        vm.prank(user2);
        distributor.claimRoyaltiesMerkle(address(nft), user2, 0.3 ether, proof2);
        
        // User1 tries to use user2's proof
        vm.prank(user1);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__AlreadyClaimed.selector);
        distributor.claimRoyaltiesMerkle(address(nft), user1, 0.3 ether, proof2);
    }
} 