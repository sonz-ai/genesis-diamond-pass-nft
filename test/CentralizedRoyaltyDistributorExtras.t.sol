// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";
import "forge-std/StdCheats.sol";

contract CentralizedRoyaltyDistributorExtrasTest is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass nft;

    address admin = address(0xA11CE);
    address service = address(0xBEEF);
    address creator = address(0xC0FFEE);
    address user1 = address(0x1);
    address user2 = address(0x2);
    uint96 royaltyNum = 1000; // 10%

    function setUp() public {
        // Deploy and configure
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        nft = new DiamondGenesisPass(address(distributor), royaltyNum, creator);
        // Only register if not already registered
        if (!distributor.isCollectionRegistered(address(nft))) {
            distributor.registerCollection(address(nft), royaltyNum, 2000, 8000, creator);
        }
        vm.stopPrank();
    }

    // Test receive() fallback when called by a registered collection
    function testFallbackAttribution() public {
        // Fund NFT so it can forward
        vm.deal(address(nft), 1 ether);
        vm.prank(address(nft));
        (bool ok,) = address(distributor).call{value: 0.1 ether}("");
        assertTrue(ok);

        // Check accumulated ETH royalties
        uint256 pool = distributor.getCollectionRoyalties(address(nft));
        assertEq(pool, 0.1 ether);

        // Check analytics totalRoyaltyCollected
        (,, uint256 totalCollected) = distributor.getCollectionRoyaltyData(address(nft));
        assertEq(totalCollected, 0.1 ether);
    }

    // Test manual addCollectionRoyalties and analytics update
    function testManualAddRoyalties() public {
        vm.deal(user1, 2 ether);
        vm.prank(user1);
        distributor.addCollectionRoyalties{value: 1 ether}(address(nft));

        assertEq(distributor.getCollectionRoyalties(address(nft)), 1 ether);
        (,, uint256 totalCollected) = distributor.getCollectionRoyaltyData(address(nft));
        assertEq(totalCollected, 1 ether);
    }

    // Test batchUpdateRoyaltyData updates state and analytics
    function testBatchUpdateAndAccrualAnalytics() public {
        // Mint token to user1
        vm.prank(admin);
        nft.mintOwner(user1);

        // Prepare batch data
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        address[] memory minters = new address[](1);
        minters[0] = user1;
        uint256[] memory salePrices = new uint256[](1);
        salePrices[0] = 1 ether;
        bytes32[] memory txHashes = new bytes32[](1);
        txHashes[0] = keccak256(abi.encodePacked("sale1"));

        // Calculate expected royalty values
        // royaltyNum = 1000 (10% of sale price)
        // minterShares = 2000 (20% of royalty)
        // creatorShares = 8000 (80% of royalty)
        uint256 FEE_DENOMINATOR = 10000;
        uint256 SHARES_DENOMINATOR = 10000;
        uint256 royaltyAmount = (1 ether * royaltyNum) / FEE_DENOMINATOR; // 0.1 ether
        uint256 minterShareRoyalty = (royaltyAmount * 2000) / SHARES_DENOMINATOR; // 0.02 ether
        uint256 creatorShareRoyalty = (royaltyAmount * 8000) / SHARES_DENOMINATOR; // 0.08 ether

        // Expect event and execute
        vm.startPrank(service);
        vm.expectEmit(true, true, false, true);
        emit RoyaltyAttributed(address(nft), 1, user1, 1 ether, minterShareRoyalty, creatorShareRoyalty, txHashes[0]);
        distributor.batchUpdateRoyaltyData(address(nft), tokenIds, minters, salePrices, txHashes);
        vm.stopPrank();

        // Validate token-level data
        (address minter, , uint256 count, uint256 vol, uint256 mEarned, uint256 cEarned) = distributor.getTokenRoyaltyData(address(nft), 1);
        assertEq(minter, user1);
        assertEq(count, 1);
        assertEq(vol, 1 ether);
        assertEq(mEarned, minterShareRoyalty);
        assertEq(cEarned, creatorShareRoyalty);

        // Validate collection-level analytics
        (uint256 colVol, , ) = distributor.getCollectionRoyaltyData(address(nft));
        assertEq(colVol, 1 ether);
        assertEq(distributor.totalAccrued(), royaltyAmount);
    }

    // Unauthorized batch update reverts
    function testBatchUpdateUnauthorized() public {
        uint256[] memory emptyUint = new uint256[](0);
        address[] memory emptyAddress = new address[](0);
        bytes32[] memory emptyBytes32 = new bytes32[](0);
        vm.prank(user1);
        // Update expected error to match the actual error in the contract
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__CallerIsNotAdminOrServiceAccount.selector);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            emptyUint,
            emptyAddress,
            emptyUint,
            emptyBytes32
        );
    }

    // helper for verifying event signature
    event RoyaltyAttributed(address indexed collection, uint256 indexed tokenId, address indexed minter, uint256 salePrice, uint256 minterShare, uint256 creatorShare, bytes32 txHash);
} 