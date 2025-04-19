// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestERC20 is ERC20 {
    constructor() ERC20("TestToken", "TTK") {
        _mint(msg.sender, 1000 ether);
    }
}

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
    TestERC20 token;

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
        vm.expectEmit(true, true, true, true);
        emit RoyaltyAttributed(address(nft), 1, user1, 1 ether, 15000000000000000, 60000000000000000, txHashes[0]);
        distributor.batchUpdateRoyaltyData(address(nft), tokenIds, minters, salePrices, txHashes);
        vm.stopPrank();

        uint256 expectedRoyalty = (1 ether * 750) / 10000;
        assertEq(distributor.totalAccrued(), expectedRoyalty);
    }

    function testUnauthorizedBatchUpdateRevert() public {
        uint256[] memory t = new uint256[](0);
        vm.prank(user2);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__CallerIsNotAdminOrServiceAccount.selector);
        distributor.batchUpdateRoyaltyData(address(nft), t, new address[](0), new uint256[](0), new bytes32[](0));
    }

    function testSubmitMerkleRootInsufficientBalanceRevert() public {
        // deposit small ETH
        vm.deal(address(this), 0.1 ether);
        distributor.addCollectionRoyalties{value: 0.1 ether}(address(nft));
        bytes32 root = keccak256(abi.encodePacked(user1, uint256(0.05 ether)));
        vm.prank(service);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__InsufficientBalanceForRoot.selector);
        distributor.submitRoyaltyMerkleRoot(address(nft), root, 0.2 ether);
    }

    function testClaimRoyaltiesMerkleInvalidProofRevert() public {
        // deposit ETH to service and submit root for 0.05 ETH
        vm.deal(service, 0.1 ether);
        vm.startPrank(service);
        distributor.addCollectionRoyalties{value: 0.1 ether}(address(nft));
        bytes32 root = keccak256(abi.encodePacked(user1, uint256(0.05 ether)));
        distributor.submitRoyaltyMerkleRoot(address(nft), root, 0.05 ether);
        vm.stopPrank();

        // Claim with wrong amount should revert InvalidProof
        vm.prank(user1);
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__InvalidProof.selector);
        distributor.claimRoyaltiesMerkle(address(nft), user1, 0.06 ether, new bytes32[](0));
    }

    function testTotalClaimedIncrements() public {
        vm.deal(address(this), 0.1 ether);
        distributor.addCollectionRoyalties{value: 0.1 ether}(address(nft));
        bytes32 root = keccak256(abi.encodePacked(user1, uint256(0.08 ether)));
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), root, 0.08 ether);
        assertEq(distributor.totalClaimed(), 0);
        vm.prank(user1);
        distributor.claimRoyaltiesMerkle(address(nft), user1, 0.08 ether, new bytes32[](0));
        assertEq(distributor.totalClaimed(), 0.08 ether);
    }

    function testAddAndClaimERC20RoyaltiesMerkle() public {
        // setup ERC20 and deposit ERC20 royalties
        token = new TestERC20();
        uint256 ercAmount = 100 ether;
        // approve and add
        token.approve(address(distributor), ercAmount);
        distributor.addCollectionERC20Royalties(address(nft), IERC20(token), ercAmount);
        assertEq(distributor.getCollectionERC20Royalties(address(nft), IERC20(token)), ercAmount);

        // deposit ETH for merkle root
        vm.deal(address(this), 1 ether);
        distributor.addCollectionRoyalties{value: 1 ether}(address(nft));

        // submit root including token info
        bytes32 root = keccak256(abi.encodePacked(user2, address(token), ercAmount));
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), root, 0);

        // claim ERC20
        vm.prank(user2);
        distributor.claimERC20RoyaltiesMerkle(address(nft), user2, IERC20(token), ercAmount, new bytes32[](0));
        assertEq(token.balanceOf(user2), ercAmount);
    }
} 