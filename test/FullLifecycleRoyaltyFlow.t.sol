// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FullLifecycleRoyaltyFlowTest is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass nft;
    
    address admin = address(0xA11CE);
    address service = address(0xBEEF);
    address creator = address(0xC0FFEE);
    address buyer1 = address(0x1);
    address buyer2 = address(0x2);
    
    uint96 royaltyFee = 750; // 7.5%
    uint256 mintPrice = 0.1 ether;
    uint256 salePrice = 1 ether;
    
    function setUp() public {
        // Deploy distributor and set up roles
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        
        // Deploy NFT contract and register with distributor
        nft = new DiamondGenesisPass(address(distributor), royaltyFee, creator);
        if (!distributor.isCollectionRegistered(address(nft))) {
            distributor.registerCollection(address(nft), royaltyFee, 2000, 8000, creator);
        }
        
        // Set up NFT for minting
        nft.setPublicMintActive(true);
        
        // Disable transfer validation completely for testing
        nft.setTransferValidator(address(0));
        
        vm.stopPrank();
        
        // Fund accounts
        vm.deal(buyer1, 10 ether);
        vm.deal(buyer2, 10 ether);
        vm.deal(admin, 10 ether);
    }
    
    function testFullLifecycle() public {
        // Step 1: Mint NFT to buyer1
        vm.prank(buyer1);
        nft.mint{value: mintPrice}(buyer1);
        
        // Verify mint was successful
        assertEq(nft.ownerOf(1), buyer1);
        
        // Step 2: Secondary sale (buyer1 -> buyer2)
        // First approve the transfer
        vm.prank(buyer1);
        nft.approve(buyer2, 1);
        
        // Simulate the sale by transferring the NFT using transferFrom
        vm.prank(buyer1);
        nft.transferFrom(buyer1, buyer2, 1);
        
        // Verify transfer was successful
        assertEq(nft.ownerOf(1), buyer2);
        
        // Step 3: Record the sale for royalty tracking
        vm.prank(service);
        nft.recordSale(1, salePrice);
        
        // Step 4: Simulate marketplace sending royalty payment to distributor
        uint256 royaltyAmount = (salePrice * royaltyFee) / 10000;
        vm.deal(address(this), royaltyAmount);
        distributor.addCollectionRoyalties{value: royaltyAmount}(address(nft));
        
        // Step 5: Service account processes royalty data and updates accrued royalties
        // Calculate expected royalty shares
        uint256 minterShare = (royaltyAmount * 2000) / 10000; // 20% to minter
        uint256 creatorShare = (royaltyAmount * 8000) / 10000; // 80% to creator
        
        // Create arrays for updateAccruedRoyalties
        address[] memory recipients = new address[](2);
        recipients[0] = buyer1;  // minter
        recipients[1] = creator;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = minterShare;
        amounts[1] = creatorShare;
        
        console2.log("Minter (buyer1): %s, share: %d", vm.toString(buyer1), minterShare);
        console2.log("Creator: %s, share: %d", vm.toString(creator), creatorShare);
        
        // Update accrued royalties for both recipients
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // Step 6: Verify claimable amounts
        uint256 minterClaimable = distributor.getClaimableRoyalties(address(nft), buyer1);
        uint256 creatorClaimable = distributor.getClaimableRoyalties(address(nft), creator);
        
        console2.log("Minter claimable: %d", minterClaimable);
        console2.log("Creator claimable: %d", creatorClaimable);
        
        assertEq(minterClaimable, minterShare);
        assertEq(creatorClaimable, creatorShare);
        
        // Step 7: Minter claims their share
        console2.log("Claiming for buyer1");
        uint256 minterBalanceBefore = buyer1.balance;
        vm.prank(buyer1);
        distributor.claimRoyalties(address(nft), minterShare);
        uint256 minterBalanceAfter = buyer1.balance;
        
        // Verify minter received their share
        assertEq(minterBalanceAfter - minterBalanceBefore, minterShare);
        
        // Verify minter's claimable royalties are now 0
        assertEq(distributor.getClaimableRoyalties(address(nft), buyer1), 0);
        
        // Step 8: Creator claims their share
        console2.log("Claiming for creator");
        uint256 creatorBalanceBefore = creator.balance;
        vm.prank(creator);
        distributor.claimRoyalties(address(nft), creatorShare);
        uint256 creatorBalanceAfter = creator.balance;
        
        // Verify creator received their share
        assertEq(creatorBalanceAfter - creatorBalanceBefore, creatorShare);
        
        // Verify creator's claimable royalties are now 0
        assertEq(distributor.getClaimableRoyalties(address(nft), creator), 0);
        
        // Verify analytics
        assertEq(distributor.totalAccrued(), royaltyAmount);
        assertEq(distributor.totalClaimed(), royaltyAmount);
    }
    
    function testPartialClaims() public {
        // First set up the same scenario as before
        vm.prank(buyer1);
        nft.mint{value: mintPrice}(buyer1);
        
        vm.prank(buyer1);
        nft.approve(buyer2, 1);
        
        vm.prank(buyer1);
        nft.transferFrom(buyer1, buyer2, 1);
        
        vm.prank(service);
        nft.recordSale(1, salePrice);
        
        uint256 royaltyAmount = (salePrice * royaltyFee) / 10000;
        vm.deal(address(this), royaltyAmount);
        distributor.addCollectionRoyalties{value: royaltyAmount}(address(nft));
        
        // Calculate shares
        uint256 minterShare = (royaltyAmount * 2000) / 10000;
        uint256 creatorShare = (royaltyAmount * 8000) / 10000;
        
        // Update accrued royalties
        address[] memory recipients = new address[](2);
        recipients[0] = buyer1;
        recipients[1] = creator;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = minterShare;
        amounts[1] = creatorShare;
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // Test partial claims - claim half now and half later
        uint256 halfMinterShare = minterShare / 2;
        
        // First half claim
        vm.prank(buyer1);
        distributor.claimRoyalties(address(nft), halfMinterShare);
        
        // Verify claimable amount is now half
        assertEq(distributor.getClaimableRoyalties(address(nft), buyer1), halfMinterShare);
        
        // Second half claim
        vm.prank(buyer1);
        distributor.claimRoyalties(address(nft), halfMinterShare);
        
        // Verify nothing left to claim
        assertEq(distributor.getClaimableRoyalties(address(nft), buyer1), 0);
    }
    
    function testMultipleSalesAccrual() public {
        // First sale
        vm.prank(buyer1);
        nft.mint{value: mintPrice}(buyer1);
        
        vm.prank(buyer1);
        nft.approve(buyer2, 1);
        
        vm.prank(buyer1);
        nft.transferFrom(buyer1, buyer2, 1);
        
        vm.prank(service);
        nft.recordSale(1, salePrice);
        
        uint256 royaltyAmount1 = (salePrice * royaltyFee) / 10000;
        vm.deal(address(this), royaltyAmount1);
        distributor.addCollectionRoyalties{value: royaltyAmount1}(address(nft));
        
        // Calculate shares for first sale
        uint256 minterShare1 = (royaltyAmount1 * 2000) / 10000;
        uint256 creatorShare1 = (royaltyAmount1 * 8000) / 10000;
        
        // Update accrued royalties for first sale
        address[] memory recipients = new address[](2);
        recipients[0] = buyer1;
        recipients[1] = creator;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = minterShare1;
        amounts[1] = creatorShare1;
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // Second sale (higher price)
        uint256 salePrice2 = 2 ether;
        
        address buyer3 = address(0x3);
        vm.deal(buyer3, 10 ether);
        
        vm.prank(buyer2);
        nft.approve(buyer3, 1);
        
        vm.prank(buyer2);
        nft.transferFrom(buyer2, buyer3, 1);
        
        vm.prank(service);
        nft.recordSale(1, salePrice2);
        
        uint256 royaltyAmount2 = (salePrice2 * royaltyFee) / 10000;
        vm.deal(address(this), royaltyAmount2);
        distributor.addCollectionRoyalties{value: royaltyAmount2}(address(nft));
        
        // Calculate shares for second sale
        uint256 minterShare2 = (royaltyAmount2 * 2000) / 10000;
        uint256 creatorShare2 = (royaltyAmount2 * 8000) / 10000;
        
        // Update accrued royalties for second sale
        recipients[0] = buyer1; // Same minter
        recipients[1] = creator;
        
        amounts[0] = minterShare2;
        amounts[1] = creatorShare2;
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // Verify total accrued for each party
        assertEq(distributor.getClaimableRoyalties(address(nft), buyer1), minterShare1 + minterShare2);
        assertEq(distributor.getClaimableRoyalties(address(nft), creator), creatorShare1 + creatorShare2);
        
        // Claim total amounts
        vm.prank(buyer1);
        distributor.claimRoyalties(address(nft), minterShare1 + minterShare2);
        
        vm.prank(creator);
        distributor.claimRoyalties(address(nft), creatorShare1 + creatorShare2);
        
        // Verify nothing left to claim
        assertEq(distributor.getClaimableRoyalties(address(nft), buyer1), 0);
        assertEq(distributor.getClaimableRoyalties(address(nft), creator), 0);
        
        // Verify analytics
        assertEq(distributor.totalAccrued(), royaltyAmount1 + royaltyAmount2);
        assertEq(distributor.totalClaimed(), royaltyAmount1 + royaltyAmount2);
    }
    
    function testRaceConditionResistance() public {
        // Set up initial state
        vm.prank(buyer1);
        nft.mint{value: mintPrice}(buyer1);
        
        vm.prank(buyer1);
        nft.transferFrom(buyer1, buyer2, 1);
        
        vm.prank(service);
        nft.recordSale(1, salePrice);
        
        uint256 royaltyAmount = (salePrice * royaltyFee) / 10000;
        vm.deal(address(this), royaltyAmount);
        distributor.addCollectionRoyalties{value: royaltyAmount}(address(nft));
        
        // Update initial accrued royalties
        uint256 minterShare = (royaltyAmount * 2000) / 10000;
        uint256 creatorShare = (royaltyAmount * 8000) / 10000;
        
        address[] memory recipients = new address[](2);
        recipients[0] = buyer1;
        recipients[1] = creator;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = minterShare;
        amounts[1] = creatorShare;
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients, amounts);
        
        // Simulate race condition: buyer1 claims while service is updating more accruals
        
        // Buyer1 claims their initial share
        vm.prank(buyer1);
        distributor.claimRoyalties(address(nft), minterShare);
        
        // A second sale happens and service adds more accruals
        uint256 salePrice2 = 1.5 ether;
        uint256 royaltyAmount2 = (salePrice2 * royaltyFee) / 10000;
        vm.deal(address(this), royaltyAmount2);
        distributor.addCollectionRoyalties{value: royaltyAmount2}(address(nft));
        
        uint256 minterShare2 = (royaltyAmount2 * 2000) / 10000;
        uint256 creatorShare2 = (royaltyAmount2 * 8000) / 10000;
        
        address[] memory recipients2 = new address[](2);
        recipients2[0] = buyer1;
        recipients2[1] = creator;
        
        uint256[] memory amounts2 = new uint256[](2);
        amounts2[0] = minterShare2;
        amounts2[1] = creatorShare2;
        
        vm.prank(service);
        distributor.updateAccruedRoyalties(address(nft), recipients2, amounts2);
        
        // Verify that buyer1 has exactly the new amount available
        assertEq(distributor.getClaimableRoyalties(address(nft), buyer1), minterShare2);
        
        // Buyer1 can claim the new amount
        vm.prank(buyer1);
        distributor.claimRoyalties(address(nft), minterShare2);
        
        // Verify nothing left
        assertEq(distributor.getClaimableRoyalties(address(nft), buyer1), 0);
        
        // Creator claims their total amount
        vm.prank(creator);
        distributor.claimRoyalties(address(nft), creatorShare + creatorShare2);
        
        assertEq(distributor.getClaimableRoyalties(address(nft), creator), 0);
    }
}
