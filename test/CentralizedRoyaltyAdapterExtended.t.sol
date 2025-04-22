// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/programmable-royalties/CentralizedRoyaltyAdapter.sol";
import "src/DiamondGenesisPass.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";

contract MockRoyaltyAdapter is CentralizedRoyaltyAdapter {
    constructor(address distributor_, uint256 feeNumerator_)
        CentralizedRoyaltyAdapter(distributor_, feeNumerator_) {}
}

contract UnregisteredCollectionAdapter is CentralizedRoyaltyAdapter {
    constructor(address distributor_, uint256 feeNumerator_)
        CentralizedRoyaltyAdapter(distributor_, feeNumerator_) {}

    function forceRevertsOnConfig() public view {
        this.minterShares();
    }
}

contract CentralizedRoyaltyAdapterExtendedTest is Test {
    CentralizedRoyaltyDistributor public distributor;
    DiamondGenesisPass             public nft;
    MockRoyaltyAdapter             public mockAdapter;
    UnregisteredCollectionAdapter  public unregisteredAdapter;

    address public admin    = address(0x1001);
    address public service  = address(0x1002);
    address public creator  = address(0x1003);
    address public user1    = address(0x1111);
    address public user2    = address(0x2222);

    event RoyaltyDistributorSet(address indexed distributor);
    event RoyaltyFeeNumeratorSet(uint256 feeNumerator);

    function setUp() public {
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);

        nft = new DiamondGenesisPass(address(distributor), 750, creator);

        unregisteredAdapter = new UnregisteredCollectionAdapter(address(distributor), 500);
        vm.stopPrank();

        vm.deal(admin, 10 ether);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
    }

    /* ───────── constructor guards ───────── */
    function testConstructorZeroAddressRevert() public {
        vm.expectRevert(
            CentralizedRoyaltyAdapter
                .CentralizedRoyaltyAdapter__DistributorCannotBeZeroAddress
                .selector
        );
        mockAdapter = new MockRoyaltyAdapter(address(0), 500);
    }

    function testConstructorExcessFeeRevert() public {
        vm.expectRevert(
            CentralizedRoyaltyAdapter
                .CentralizedRoyaltyAdapter__RoyaltyFeeWillExceedSalePrice
                .selector
        );
        mockAdapter = new MockRoyaltyAdapter(address(distributor), 15_000);
    }

    function testConstructorWithMaxFee() public {
        mockAdapter = new MockRoyaltyAdapter(address(distributor), 10_000);
        assertEq(mockAdapter.royaltyFeeNumerator(), 10_000);
    }

    function testConstructorEmitsEvents() public {
        vm.expectEmit(true, false, false, true);
        emit RoyaltyDistributorSet(address(distributor));

        vm.expectEmit(false, false, false, true);
        emit RoyaltyFeeNumeratorSet(500);

        mockAdapter = new MockRoyaltyAdapter(address(distributor), 500);
    }

    /* ───────── distributor analytics ───────── */
    function testTokenRoyaltyDataAfterBatchUpdate() public {
        vm.prank(admin);
        nft.mintOwner(user1);

        uint256[] memory tokenIds = new uint256[](1);
        address[] memory minters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);

        tokenIds[0]   = 1;
        minters[0]    = user1;
        salePrices[0] = 1 ether;
        txHashes[0]   = keccak256("tx1");

        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            minters,
            salePrices,
            txHashes
        );

        (
            address minter,
            address currentOwner,
            uint256 transactionCount,
            uint256 totalVolume,
            uint256 minterRoyaltyEarned,
            uint256 creatorRoyaltyEarned
        ) = nft.tokenRoyaltyData(1);

        assertEq(minter, user1);
        assertEq(currentOwner, user1);
        assertEq(transactionCount, 1);
        assertEq(totalVolume, 1 ether);

        uint256 royaltyAmount        = (1 ether * 750) / 10_000;
        uint256 expectedMinterShare  = (royaltyAmount * 2000) / 10_000;
        uint256 expectedCreatorShare = (royaltyAmount * 8000) / 10_000;

        assertEq(minterRoyaltyEarned, expectedMinterShare);
        assertEq(creatorRoyaltyEarned, expectedCreatorShare);
    }

    /* ───────── reverts on unregistered collection ───────── */
    function testUnregisteredCollectionCalls() public {
        vm.expectRevert(
            CentralizedRoyaltyDistributor.RoyaltyDistributor__CollectionNotRegistered.selector
        );
        unregisteredAdapter.forceRevertsOnConfig();
    }

    /* ───────── interface support ───────── */
    function testSupportsMultipleInterfaces() public view {
        assertTrue(nft.supportsInterface(type(IERC2981).interfaceId));
        assertTrue(nft.supportsInterface(type(IERC165).interfaceId));

        bytes4 nonSupported = bytes4(keccak256("nonSupportedInterface()"));
        assertFalse(nft.supportsInterface(nonSupported));
    }

    /* ───────── royalty calc edge cases ───────── */
    function testRoyaltyCalculationEdgeCases() public view {
        (address recv, uint256 amt) = nft.royaltyInfo(1, 0);
        assertEq(recv, address(distributor));
        assertEq(amt, 0);

        uint256 bigPrice = 1_000_000 ether;
        (recv, amt) = nft.royaltyInfo(1, bigPrice);
        assertEq(recv, address(distributor));
        assertEq(amt, (bigPrice * 750) / 10_000);

        uint256 tinyPrice = 100;
        (recv, amt) = nft.royaltyInfo(1, tinyPrice);
        assertEq(recv, address(distributor));
        assertEq(amt, (tinyPrice * 750) / 10_000);
    }

    /* ───────── local vs distributor fee ───────── */
    function testLocalVsDistributorRoyaltyFee() public {
        vm.startPrank(admin);
        DiamondGenesisPass newNft = new DiamondGenesisPass(
            address(distributor),
            500,      // local fee 5 %
            creator
        );
        vm.stopPrank();

        (address recv, uint256 amt) = newNft.royaltyInfo(1, 1 ether);
        assertEq(recv, address(distributor));
        assertEq(amt, (1 ether * 500) / 10_000);
        assertEq(newNft.distributorRoyaltyFeeNumerator(), 500);
    }

    /* ───────── gas snapshots (non‑assert) ───────── */
    function testGasUsageForViewFunctions() public {
        vm.prank(admin);
        nft.mintOwner(user1);

        uint256 batchSize = 10;
        uint256[] memory ids  = new uint256[](batchSize);
        address[] memory mtrs = new address[](batchSize);
        uint256[] memory prc  = new uint256[](batchSize);
        bytes32[] memory txh  = new bytes32[](batchSize);

        for (uint256 i; i < batchSize; ++i) {
            ids[i]  = 1;
            mtrs[i] = user1;
            prc[i]  = 1 ether * (i + 1);
            txh[i]  = keccak256(abi.encodePacked("tx", i));
        }

        vm.prank(service);
        distributor.batchUpdateRoyaltyData(address(nft), ids, mtrs, prc, txh);

        uint256 start = gasleft();
        nft.royaltyInfo(1, 1 ether);
        uint256 g1 = start - gasleft();

        start = gasleft();
        nft.tokenRoyaltyData(1);
        uint256 g2 = start - gasleft();

        start = gasleft();
        nft.minterOf(1);
        uint256 g3 = start - gasleft();

        console.log("Gas usage - royaltyInfo:", g1);
        console.log("Gas usage - tokenRoyaltyData:", g2);
        console.log("Gas usage - minterOf:", g3);
    }

    /* ───────── active merkle root flows ───────── */
    function testActiveMerkleRootUpdates() public {
        assertEq(nft.activeMerkleRoot(), bytes32(0));

        bytes32 root1 = keccak256("root1");
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), root1, 0);
        assertEq(nft.activeMerkleRoot(), root1);

        bytes32 root2 = keccak256("root2");
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), root2, 0);
        assertEq(nft.activeMerkleRoot(), root2);
    }

    /* ───────── non‑existent token data ───────── */
    function testTokenRoyaltyDataForNonexistentToken() public view {
        (
            address minter,
            address currentOwner,
            uint256 count,
            uint256 vol,
            uint256 mEarned,
            uint256 cEarned
        ) = nft.tokenRoyaltyData(999);

        assertEq(minter, address(0));
        assertEq(currentOwner, address(0));
        assertEq(count, 0);
        assertEq(vol, 0);
        assertEq(mEarned, 0);
        assertEq(cEarned, 0);
    }
}