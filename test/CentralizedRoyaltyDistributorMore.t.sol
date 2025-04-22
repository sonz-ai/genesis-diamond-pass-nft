// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contract TestERC20 is ERC20 { // Removed as not used after refactor
//     constructor() ERC20("TestToken", "TTK") {
//         _mint(msg.sender, 1000 ether);
//     }
// }

contract CentralizedRoyaltyDistributorMoreTest is Test {
    // Declare event for expectEmit matching the distributor's event signature
    event RoyaltyAttributed(
        address indexed collection,
        uint256 indexed tokenId,
        address indexed minter,
        uint256 salePrice,
        uint256 minterShareAttributed,
        uint256 creatorShareAttributed,
        bytes32 transactionHash
    );
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass nft;
    // TestERC20 token; // Removed as not used after refactor

    address admin = address(0xA11CE);
    address service = address(0xBEEF);
    address creator = address(0xC0FFEE);
    address user1 = address(0x1);
    address user2 = address(0x2);

    function setUp() public {
        // Deploy distributor and set roles
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        // Deploy NFT and register
        nft = new DiamondGenesisPass(address(distributor), 750, creator);
        // Only register if not already registered in constructor
        if (!distributor.isCollectionRegistered(address(nft))) {
            distributor.registerCollection(address(nft), 750, 2000, 8000, creator);
        }
        // Mint token 1 to user1
        nft.mintOwner(user1);
        vm.stopPrank();
    }

    function testGetCollectionConfig() public {
        (uint256 feeNum, uint256 minterShares, uint256 creatorShares, address creatorAddr) = distributor.getCollectionConfig(address(nft));
        assertEq(feeNum, 750);
        assertEq(minterShares, 2000);
        assertEq(creatorShares, 8000);
        assertEq(creatorAddr, creator);
    }

    function testGetCollectionConfigRevertIfNotRegistered() public {
        vm.prank(user1);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__CollectionNotRegistered.selector);
        distributor.getCollectionConfig(address(0x123));
    }

    function testUnauthorizedSetTokenMinterRevert() public {
        vm.prank(user2);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__CallerIsNotCollectionOwner.selector);
        distributor.setTokenMinter(address(nft), 2, user2);
    }

    function testReceiveFallbackAttributesRoyalties() public {
        // initial
        uint256 before = distributor.getCollectionRoyalties(address(nft));
        // send ETH from NFT contract
        vm.deal(address(nft), 1 ether);
        vm.prank(address(nft));
        (bool ok,) = address(distributor).call{value: 1 ether}("");
        assertTrue(ok);
        uint256 afterBal = distributor.getCollectionRoyalties(address(nft));
        assertEq(afterBal - before, 1 ether);

        (,,uint256 totalRoyaltyCollected) = distributor.getCollectionRoyaltyData(address(nft));
        assertEq(totalRoyaltyCollected, 1 ether);
    }

    function testBatchUpdateRoyaltyDataAndTotalAccrued() public {
        // Prepare sale data
        uint256[] memory tokenIds = new uint256[](1);
        address[] memory minters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);
        tokenIds[0] = 1;
        minters[0] = user1;
        salePrices[0] = 1 ether;
        txHashes[0] = keccak256(abi.encodePacked("tx1"));

        // Expect event and execute
        vm.startPrank(service);
        // Calculate expected shares based on config in setUp()
        uint256 expectedRoyalty = (1 ether * 750) / 10000; // 0.075 ETH
        uint256 expectedMinterShare = (expectedRoyalty * 2000) / 10000; // 0.015 ETH
        uint256 expectedCreatorShare = (expectedRoyalty * 8000) / 10000; // 0.06 ETH

        vm.expectEmit(true, true, true, true);
        emit RoyaltyAttributed(address(nft), 1, user1, 1 ether, expectedMinterShare, expectedCreatorShare, txHashes[0]);
        distributor.batchUpdateRoyaltyData(address(nft), tokenIds, minters, salePrices, txHashes);
        vm.stopPrank();

        assertEq(distributor.totalAccrued(), expectedRoyalty);
    }

    function testUnauthorizedBatchUpdateRevert() public {
        uint256[] memory t = new uint256[](0);
        vm.prank(user2);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__CallerIsNotAdminOrServiceAccount.selector);
        distributor.batchUpdateRoyaltyData(address(nft), t, new address[](0), new uint256[](0), new bytes32[](0));
    }

    // REMOVED: testSubmitMerkleRootInsufficientBalanceRevert
    /* function testSubmitMerkleRootInsufficientBalanceRevert() public { ... } */

    // REMOVED: testClaimRoyaltiesMerkleInvalidProofRevert
    /* function testClaimRoyaltiesMerkleInvalidProofRevert() public { ... } */

    // REMOVED: testTotalClaimedIncrements
    /* function testTotalClaimedIncrements() public { ... } */

    // REMOVED: testAddAndClaimERC20RoyaltiesMerkle
    /* function testAddAndClaimERC20RoyaltiesMerkle() public { ... } */

    function testClaimRoyalties() public {
        // 1. Add royalties to the collection
        vm.deal(address(this), 1 ether);
        distributor.addCollectionRoyalties{value: 1 ether}(address(nft));
        
        // 2. Update accrued royalties for user1
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = user1;
        amounts[0] = 0.5 ether;
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // 3. Verify claimable amounts
        assertEq(distributor.getClaimableRoyalties(address(nft), user1), 0.5 ether);
        
        // 4. Claim royalties
        uint256 balanceBefore = user1.balance;
        vm.prank(user1);
        distributor.claimRoyalties(address(nft), 0.5 ether);
        
        // 5. Verify balance changed and claimable is now 0
        assertEq(user1.balance, balanceBefore + 0.5 ether);
        assertEq(distributor.getClaimableRoyalties(address(nft), user1), 0);
        
        // 6. Verify total claimed increased
        assertEq(distributor.totalClaimed(), 0.5 ether);
    }

    function testCannotClaimMoreThanAccrued() public {
        // 1. Add royalties to the collection
        vm.deal(address(this), 1 ether);
        distributor.addCollectionRoyalties{value: 1 ether}(address(nft));
        
        // 2. Update accrued royalties for user1
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = user1;
        amounts[0] = 0.5 ether;
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // 3. Try to claim more than accrued
        vm.prank(user1);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__InsufficientUnclaimedRoyalties.selector);
        distributor.claimRoyalties(address(nft), 0.6 ether);
    }

    function testUpdateRoyaltyRecipient() public {
        // Get initial creator
        address initialCreator = creator;
        address newRecipient = address(0x4444);
        
        // Get initial creator from distributor
        (,,, address creatorFromDistributor) = distributor.getCollectionConfig(address(nft));
        assertEq(creatorFromDistributor, initialCreator);
        
        // Update creator/royalty recipient
        vm.prank(admin);
        nft.setRoyaltyRecipient(newRecipient);
        
        // Verify update was successful
        (,,, creatorFromDistributor) = distributor.getCollectionConfig(address(nft));
        assertEq(creatorFromDistributor, newRecipient);
        assertEq(nft.creator(), newRecipient);
    }
} 