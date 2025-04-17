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
    uint96 royaltyNum = 750; // 7.5%

    function setUp() public {
        // Deploy and configure
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        nft = new DiamondGenesisPass(address(distributor), royaltyNum, creator);
        distributor.registerCollection(address(nft), royaltyNum, 2000, 8000, creator);
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
        uint256[] memory txTimes = new uint256[](1);
        txTimes[0] = block.timestamp;
        bytes32[] memory txHashes = new bytes32[](1);
        txHashes[0] = keccak256(abi.encodePacked("sale1"));

        // Expect event and execute
        vm.startPrank(service);
        vm.expectEmit(true, true, false, true);
        emit RoyaltyAttributed(address(nft), 1, user1, 1 ether, 15000000000000000, 60000000000000000, txHashes[0]);
        distributor.batchUpdateRoyaltyData(address(nft), tokenIds, minters, salePrices, txTimes, txHashes);
        vm.stopPrank();

        // Validate token-level data
        (address minter, , uint256 count, uint256 vol, uint256 mEarned, uint256 cEarned) = distributor.getTokenRoyaltyData(address(nft), 1);
        assertEq(minter, user1);
        assertEq(count, 1);
        assertEq(vol, 1 ether);
        assertEq(mEarned, (1 ether * 2000) / 10000);
        assertEq(cEarned, (1 ether * 8000) / 10000);

        // Validate collection-level analytics
        (uint256 colVol, , ) = distributor.getCollectionRoyaltyData(address(nft));
        assertEq(colVol, 1 ether);
        assertEq(distributor.totalAccrued(), 1 ether);
    }

    // Unauthorized batch update reverts
    function testBatchUpdateUnauthorized() public {
        uint256[] memory emptyUint = new uint256[](0);
        address[] memory emptyAddress = new address[](0);
        bytes32[] memory emptyBytes32 = new bytes32[](0);
        vm.prank(user1);
        vm.expectRevert();
        distributor.batchUpdateRoyaltyData(
            address(nft),
            emptyUint,
            emptyAddress,
            emptyUint,
            emptyUint,
            emptyBytes32
        );
    }

    // submitMerkleRoot insufficient funds revert
    function testSubmitMerkleRootInsufficientFunds() public {
        // deposit only 0.1 ETH
        vm.deal(address(this), 0.1 ether);
        distributor.addCollectionRoyalties{value: 0.1 ether}(address(nft));
        bytes32 root = keccak256(abi.encodePacked(user1, uint256(0.5 ether)));
        vm.prank(service);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__InsufficientBalanceForRoot.selector);
        distributor.submitRoyaltyMerkleRoot(address(nft), root, 0.5 ether);
    }

    // submitMerkleRoot unauthorized revert
    function testSubmitMerkleRootUnauthorized() public {
        vm.prank(user2);
        vm.expectRevert();
        distributor.submitRoyaltyMerkleRoot(address(nft), bytes32(0), 0);
    }

    // invalid claim proof revert
    function testInvalidClaimProof() public {
        bytes32 root = keccak256(abi.encodePacked(user1, uint256(1 ether)));
        vm.prank(service);
        distributor.addCollectionRoyalties{value: 1 ether}(address(nft));
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), root, 1 ether);
        vm.prank(user1);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__InvalidProof.selector);
        distributor.claimRoyaltiesMerkle(address(nft), user1, 1 ether, new bytes32[](1));
    }

    // totalClaimed analytics update
    function testTotalClaimedAnalytics() public {
        vm.deal(address(this), 1 ether);
        distributor.addCollectionRoyalties{value: 1 ether}(address(nft));
        bytes32 root = keccak256(abi.encodePacked(user1, uint256(0.3 ether)));
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), root, 0.3 ether);
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        distributor.claimRoyaltiesMerkle(address(nft), user1, 0.3 ether, new bytes32[](0));
        assertEq(distributor.totalClaimed(), 0.3 ether);
    }

    // helper for verifying event signature
    event RoyaltyAttributed(address indexed collection, uint256 indexed tokenId, address indexed minter, uint256 salePrice, uint256 minterShare, uint256 creatorShare, bytes32 txHash);
} 