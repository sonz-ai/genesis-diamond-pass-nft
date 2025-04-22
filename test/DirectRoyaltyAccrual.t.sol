// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title DirectRoyaltyAccrual
 * @notice Tests for the direct accrual royalty distribution system
 */
contract DirectRoyaltyAccrualTest is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass nft;
    
    address admin = address(0xA11CE);
    address service = address(0xBEEF);
    address creator = address(0xC0FFEE);
    address minter = address(0x1);
    address buyer = address(0x2);
    
    uint96 royaltyFee = 750; // 7.5%
    uint256 constant MINTER_SHARES = 2000; // 20%
    uint256 constant CREATOR_SHARES = 8000; // 80%
    uint256 constant SALE_PRICE = 1 ether;
    uint256 constant ROYALTY_AMOUNT = (SALE_PRICE * 750) / 10000; // 7.5% of 1 ETH
    
    // Redeclare key events for verification
    event RoyaltyAccrued(address indexed collection, address indexed recipient, uint256 amount);
    event RoyaltyClaimed(address indexed collection, address indexed recipient, uint256 amount);
    
    function setUp() public {
        // Deploy distributor and set up roles
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        
        // Deploy NFT contract and register with distributor
        nft = new DiamondGenesisPass(address(distributor), royaltyFee, creator);
        
        // Make sure the collection is registered (should happen in constructor, but double check)
        if (!distributor.isCollectionRegistered(address(nft))) {
            distributor.registerCollection(address(nft), royaltyFee, MINTER_SHARES, CREATOR_SHARES, creator);
        }
        
        // Set up NFT for minting
        nft.setPublicMintActive(true);
        vm.stopPrank();
        
        // Fund accounts
        vm.deal(minter, 10 ether);
        vm.deal(buyer, 10 ether);
        vm.deal(service, 10 ether);
        
        // Mint an NFT to the minter
        vm.prank(minter);
        nft.mint{value: 0.1 ether}(minter);
        
        // Disable transfer validator to allow transfers
        vm.prank(admin);
        nft.setTransferValidator(address(0));
    }
    
    function testInitialState() public view {
        // Initial accrued and claimed royalties should be zero
        assertEq(distributor.totalAccrued(), 0, "Total accrued should be 0");
        assertEq(distributor.totalClaimed(), 0, "Total claimed should be 0");
        
        // Minter and creator should have no claimable royalties
        assertEq(distributor.getClaimableRoyalties(address(nft), minter), 0, "Minter claimable should be 0");
        assertEq(distributor.getClaimableRoyalties(address(nft), creator), 0, "Creator claimable should be 0");
        
        // Collection should have no unclaimed royalties
        assertEq(distributor.collectionUnclaimed(address(nft)), 0, "Collection unclaimed should be 0");
        assertEq(distributor.totalUnclaimed(), 0, "Total unclaimed should be 0");
    }
    
    function testUpdateAccruedRoyalties() public {
        // Simulate a marketplace sending royalties to the distributor
        vm.deal(service, ROYALTY_AMOUNT);
        vm.prank(service);
        distributor.addCollectionRoyalties{value: ROYALTY_AMOUNT}(address(nft));
        
        // Calculate expected shares
        uint256 minterShare = (ROYALTY_AMOUNT * MINTER_SHARES) / 10000; // 20%
        uint256 creatorShare = (ROYALTY_AMOUNT * CREATOR_SHARES) / 10000; // 80%
        
        // Set up recipients and amounts for accrual
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        recipients[0] = minter;
        recipients[1] = creator;
        amounts[0] = minterShare;
        amounts[1] = creatorShare;
        
        // Update accrued royalties via service account
        vm.expectEmit(true, true, true, true);
        emit RoyaltyAccrued(address(nft), minter, minterShare);
        vm.expectEmit(true, true, true, true);
        emit RoyaltyAccrued(address(nft), creator, creatorShare);
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // Verify accrued royalties updated correctly
        assertEq(distributor.getClaimableRoyalties(address(nft), minter), minterShare, "Minter accrued incorrect");
        assertEq(distributor.getClaimableRoyalties(address(nft), creator), creatorShare, "Creator accrued incorrect");
        
        // Total accrued should equal royalty amount
        assertEq(distributor.totalAccrued(), ROYALTY_AMOUNT, "Total accrued incorrect");
        
        // Collection unclaimed should equal royalty amount
        assertEq(distributor.collectionUnclaimed(address(nft)), ROYALTY_AMOUNT, "Collection unclaimed incorrect");
    }
    
    function testClaimRoyalties() public {
        // First accrue royalties
        vm.deal(service, ROYALTY_AMOUNT);
        vm.prank(service);
        distributor.addCollectionRoyalties{value: ROYALTY_AMOUNT}(address(nft));
        
        // Calculate expected shares
        uint256 minterShare = (ROYALTY_AMOUNT * MINTER_SHARES) / 10000; // 20%
        uint256 creatorShare = (ROYALTY_AMOUNT * CREATOR_SHARES) / 10000; // 80%
        
        // Update accrued royalties
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        recipients[0] = minter;
        recipients[1] = creator;
        amounts[0] = minterShare;
        amounts[1] = creatorShare;
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // Check balances before claiming
        uint256 minterBalanceBefore = minter.balance;
        uint256 creatorBalanceBefore = creator.balance;
        
        // Minter claims royalties
        vm.expectEmit(true, true, true, true);
        emit RoyaltyClaimed(address(nft), minter, minterShare);
        
        vm.prank(minter);
        distributor.claimRoyalties(address(nft), minterShare);
        
        // Creator claims royalties
        vm.expectEmit(true, true, true, true);
        emit RoyaltyClaimed(address(nft), creator, creatorShare);
        
        vm.prank(creator);
        distributor.claimRoyalties(address(nft), creatorShare);
        
        // Verify balances increased correctly
        assertEq(minter.balance - minterBalanceBefore, minterShare, "Minter payment incorrect");
        assertEq(creator.balance - creatorBalanceBefore, creatorShare, "Creator payment incorrect");
        
        // Verify analytics
        assertEq(distributor.totalClaimed(), ROYALTY_AMOUNT, "Total claimed incorrect");
        assertEq(distributor.totalUnclaimed(), 0, "Total unclaimed should be 0");
        assertEq(distributor.collectionUnclaimed(address(nft)), 0, "Collection unclaimed should be 0");
        
        // Verify claimable royalties are now zero
        assertEq(distributor.getClaimableRoyalties(address(nft), minter), 0, "Minter claimable should be 0");
        assertEq(distributor.getClaimableRoyalties(address(nft), creator), 0, "Creator claimable should be 0");
    }
    
    function testPartialClaims() public {
        // First accrue royalties
        vm.deal(service, ROYALTY_AMOUNT);
        vm.prank(service);
        distributor.addCollectionRoyalties{value: ROYALTY_AMOUNT}(address(nft));
        
        // Calculate expected shares
        uint256 minterShare = (ROYALTY_AMOUNT * MINTER_SHARES) / 10000; // 20%
        uint256 creatorShare = (ROYALTY_AMOUNT * CREATOR_SHARES) / 10000; // 80%
        
        // Update accrued royalties
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        recipients[0] = minter;
        recipients[1] = creator;
        amounts[0] = minterShare;
        amounts[1] = creatorShare;
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // Minter claims half their share
        uint256 halfMinterShare = minterShare / 2;
        
        vm.prank(minter);
        distributor.claimRoyalties(address(nft), halfMinterShare);
        
        // Verify partial claim analytics
        assertEq(distributor.getClaimableRoyalties(address(nft), minter), minterShare - halfMinterShare, "Minter remaining incorrect");
        assertEq(distributor.totalClaimed(), halfMinterShare, "Total claimed incorrect");
        assertEq(distributor.totalUnclaimed(), ROYALTY_AMOUNT - halfMinterShare, "Total unclaimed incorrect");
        
        // Claim remaining
        vm.prank(minter);
        distributor.claimRoyalties(address(nft), minterShare - halfMinterShare);
        
        // Creator claims their share
        vm.prank(creator);
        distributor.claimRoyalties(address(nft), creatorShare);
        
        // Verify final analytics
        assertEq(distributor.totalClaimed(), ROYALTY_AMOUNT, "Total claimed incorrect");
        assertEq(distributor.totalUnclaimed(), 0, "Total unclaimed should be 0");
    }
    
    function testMultipleAccrualsAndClaims() public {
        // First sale
        uint256 firstSaleRoyalty = ROYALTY_AMOUNT;
        
        // Add royalties for first sale
        vm.deal(service, firstSaleRoyalty);
        vm.prank(service);
        distributor.addCollectionRoyalties{value: firstSaleRoyalty}(address(nft));
        
        // Accrue royalties for first sale
        uint256 firstMinterShare = (firstSaleRoyalty * MINTER_SHARES) / 10000;
        uint256 firstCreatorShare = (firstSaleRoyalty * CREATOR_SHARES) / 10000;
        
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        recipients[0] = minter;
        recipients[1] = creator;
        amounts[0] = firstMinterShare;
        amounts[1] = firstCreatorShare;
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // Second sale (double the price)
        uint256 secondSaleRoyalty = ROYALTY_AMOUNT * 2;
        
        // Add royalties for second sale
        vm.deal(service, secondSaleRoyalty);
        vm.prank(service);
        distributor.addCollectionRoyalties{value: secondSaleRoyalty}(address(nft));
        
        // Accrue royalties for second sale
        uint256 secondMinterShare = (secondSaleRoyalty * MINTER_SHARES) / 10000;
        uint256 secondCreatorShare = (secondSaleRoyalty * CREATOR_SHARES) / 10000;
        
        recipients[0] = minter;
        recipients[1] = creator;
        amounts[0] = secondMinterShare;
        amounts[1] = secondCreatorShare;
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // Total royalties
        uint256 totalRoyalty = firstSaleRoyalty + secondSaleRoyalty;
        uint256 totalMinterShare = firstMinterShare + secondMinterShare;
        uint256 totalCreatorShare = firstCreatorShare + secondCreatorShare;
        
        // Verify accrued amounts
        assertEq(distributor.getClaimableRoyalties(address(nft), minter), totalMinterShare, "Total minter share incorrect");
        assertEq(distributor.getClaimableRoyalties(address(nft), creator), totalCreatorShare, "Total creator share incorrect");
        assertEq(distributor.totalAccrued(), totalRoyalty, "Total accrued incorrect");
        
        // Claim all royalties
        vm.prank(minter);
        distributor.claimRoyalties(address(nft), totalMinterShare);
        
        vm.prank(creator);
        distributor.claimRoyalties(address(nft), totalCreatorShare);
        
        // Verify final state
        assertEq(distributor.totalClaimed(), totalRoyalty, "Total claimed incorrect");
        assertEq(distributor.totalUnclaimed(), 0, "Total unclaimed should be 0");
        assertEq(distributor.getClaimableRoyalties(address(nft), minter), 0, "Minter claimable should be 0");
        assertEq(distributor.getClaimableRoyalties(address(nft), creator), 0, "Creator claimable should be 0");
    }
    
    function testRoyaltyTracking() public {
        // Mock a secondary market sale
        vm.prank(minter);
        nft.transferFrom(minter, buyer, 1);
        
        // Update royalty data with batchUpdateRoyaltyData
        uint256[] memory tokenIds = new uint256[](1);
        address[] memory minters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);
        
        tokenIds[0] = 1;
        minters[0] = minter;
        salePrices[0] = SALE_PRICE;
        txHashes[0] = keccak256(abi.encodePacked("tx1"));
        
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            minters,
            salePrices,
            txHashes
        );
        
        // Add royalties to the distributor
        vm.deal(service, ROYALTY_AMOUNT);
        vm.prank(service);
        distributor.addCollectionRoyalties{value: ROYALTY_AMOUNT}(address(nft));
        
        // Check token royalty data
        (
            address storedMinter,
            address tokenHolder,
            uint256 transactionCount,
            uint256 totalVolume,
            uint256 minterRoyaltyEarned,
            uint256 creatorRoyaltyEarned
        ) = distributor.getTokenRoyaltyData(address(nft), 1);
        
        // Verify token royalty data
        assertEq(storedMinter, minter, "Minter incorrect");
        assertEq(tokenHolder, buyer, "Token holder incorrect");
        assertEq(transactionCount, 1, "Transaction count incorrect");
        assertEq(totalVolume, SALE_PRICE, "Total volume incorrect");
        
        // Calculate expected royalties
        uint256 expectedMinterRoyalty = (ROYALTY_AMOUNT * MINTER_SHARES) / 10000;
        uint256 expectedCreatorRoyalty = (ROYALTY_AMOUNT * CREATOR_SHARES) / 10000;
        
        assertEq(minterRoyaltyEarned, expectedMinterRoyalty, "Minter royalty earned incorrect");
        assertEq(creatorRoyaltyEarned, expectedCreatorRoyalty, "Creator royalty earned incorrect");
        
        // Check collection data
        (uint256 colVolume, uint256 lastBlock, uint256 collectedRoyalty) = distributor.getCollectionRoyaltyData(address(nft));
        
        assertEq(colVolume, SALE_PRICE, "Collection volume incorrect");
        assertEq(lastBlock, block.number, "Last synced block incorrect");
        assertEq(collectedRoyalty, ROYALTY_AMOUNT, "Collected royalty incorrect");
    }
    
    function testNonAdminCannotAccrueRoyalties() public {
        // Prepare recipients and amounts
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = minter;
        amounts[0] = 0.1 ether;
        
        // Non-admin/service account should not be able to update accrued royalties
        vm.prank(buyer);
        vm.expectRevert();
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // Admin should be able to update accrued royalties
        vm.prank(admin);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // Service account should be able to update accrued royalties
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
    }
    
    function testInsufficientClaimReverts() public {
        // Add some royalties
        vm.deal(service, ROYALTY_AMOUNT);
        vm.prank(service);
        distributor.addCollectionRoyalties{value: ROYALTY_AMOUNT}(address(nft));
        
        // Update accrued royalties
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = minter;
        amounts[0] = 0.1 ether;
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // Try to claim more than accrued
        vm.prank(minter);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__InsufficientUnclaimedRoyalties.selector);
        distributor.claimRoyalties(address(nft), 0.2 ether);
        
        // Try to claim someone else's royalties
        vm.prank(buyer);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__InsufficientUnclaimedRoyalties.selector);
        distributor.claimRoyalties(address(nft), 0.1 ether);
    }
    
    function testOracleRateLimiting() public {
        // Default rate limit is 0, so this should succeed
        distributor.updateRoyaltyDataViaOracle(address(nft));
        
        // Set rate limit to 10 blocks
        vm.prank(admin);
        distributor.setOracleUpdateMinBlockInterval(address(nft), 10);
        
        // Try to update again (should fail)
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__OracleUpdateTooFrequent.selector);
        distributor.updateRoyaltyDataViaOracle(address(nft));
        
        // Advance 10 blocks
        vm.roll(block.number + 10);
        
        // Now it should succeed
        distributor.updateRoyaltyDataViaOracle(address(nft));
    }
    
    function testCreatorAddressUpdate() public {
        // New creator address
        address newCreator = address(0xABCD);
        
        // Only admin, current creator, or collection should be able to update
        vm.prank(buyer);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__NotCollectionCreatorOrAdmin.selector);
        distributor.updateCreatorAddress(address(nft), newCreator);
        
        // Update creator as admin
        vm.prank(admin);
        distributor.updateCreatorAddress(address(nft), newCreator);
        
        // Verify creator was updated
        (, , , address updatedCreator) = distributor.getCollectionConfig(address(nft));
        assertEq(updatedCreator, newCreator, "Creator address not updated");
        
        // Accrue and claim royalties for new creator
        vm.deal(service, ROYALTY_AMOUNT);
        vm.prank(service);
        distributor.addCollectionRoyalties{value: ROYALTY_AMOUNT}(address(nft));
        
        // Calculate shares
        uint256 creatorShare = (ROYALTY_AMOUNT * CREATOR_SHARES) / 10000;
        
        // Update accrued royalties for new creator
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = newCreator;
        amounts[0] = creatorShare;
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // New creator claims royalties
        uint256 newCreatorBalanceBefore = newCreator.balance;
        
        vm.prank(newCreator);
        distributor.claimRoyalties(address(nft), creatorShare);
        
        // Verify new creator got paid
        assertEq(newCreator.balance - newCreatorBalanceBefore, creatorShare, "New creator payment incorrect");
    }
} 