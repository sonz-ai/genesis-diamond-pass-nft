// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/DiamondGenesisPass.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";

contract RoyaltyAnalyticsTest is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass            pass;

    address internal constant CREATOR = address(0xC0FFEE);
    address internal constant MINTER  = address(0xBEEF);

    function setUp() public {
        vm.deal(address(this), 20 ether);
        vm.deal(MINTER,         10 ether);

        distributor = new CentralizedRoyaltyDistributor();
        pass        = new DiamondGenesisPass(address(distributor), 750, CREATOR);

        pass.mintOwner(MINTER);
    }

    function testAccruedAndClaimedFlow() public {
        uint256 tokenId   = 1;
        uint256 salePrice = 1 ether;
        bytes32 txHash    = keccak256("txHash");

        uint256[] memory tokenIds = new uint256[](1);
        address[] memory tokenMinters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        uint256[] memory timestamps = new uint256[](1);
        bytes32[] memory hashes = new bytes32[](1);

        tokenIds[0]     = tokenId;
        tokenMinters[0] = MINTER;
        salePrices[0]   = salePrice;
        timestamps[0]   = block.timestamp;
        hashes[0]       = txHash;

        distributor.batchUpdateRoyaltyData(
            address(pass),
            tokenIds,
            tokenMinters,
            salePrices,
            hashes
        );

        uint256 royalty = (salePrice * 750) / 10_000;
        assertEq(distributor.totalAccrued(), royalty);

        distributor.addCollectionRoyalties{value: royalty}(address(pass));

        uint256 minterShare = (royalty * 2000) / 10_000;
        bytes32 merkleRoot  = keccak256(abi.encodePacked(MINTER, minterShare));

        distributor.submitRoyaltyMerkleRoot(address(pass), merkleRoot, minterShare);

        bytes32[] memory emptyProof = new bytes32[](0);

        vm.prank(MINTER);
        distributor.claimRoyaltiesMerkle(address(pass), MINTER, minterShare, emptyProof);

        assertEq(distributor.totalClaimed(), minterShare);

        vm.prank(MINTER);
        vm.expectRevert();
        distributor.claimRoyaltiesMerkle(address(pass), MINTER, minterShare, emptyProof);
    }
}