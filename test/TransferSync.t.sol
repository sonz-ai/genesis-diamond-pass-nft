// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/DiamondGenesisPass.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";

contract TransferSyncTest is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass            pass;

    address creator = address(0xC0FFEE);
    address minter  = address(0xBEEF);
    address buyer   = address(0xD00D);

    function setUp() public {
        vm.deal(minter, 1 ether);
        vm.deal(buyer,  1 ether);

        distributor = new CentralizedRoyaltyDistributor();
        pass        = new DiamondGenesisPass(address(distributor), 750, creator);

        pass.mintOwner(minter);
    }

    function testCurrentOwnerUpdatesOnTransfer() public {
        vm.prank(minter);
        pass.transferFrom(minter, buyer, 1);

        (
            ,               // storedMinter
            address current,// currentOwner
            ,               // txnCount
            ,               // volume
            ,               // minterEarned
            /* creatorEarned */
        ) = distributor.getTokenRoyaltyData(address(pass), 1);

        assertEq(current, buyer);
    }
}