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
        
        // Disable transfer validator for testing purposes
        pass.setTransferValidator(address(0));
        
        // Give service account role to test contract for minting
        pass.grantRole(pass.SERVICE_ACCOUNT_ROLE(), address(this));
        pass.mintOwner(minter);
    }

    function testCurrentOwnerUpdatesOnTransfer() public {
        vm.prank(minter);
        pass.approve(buyer, 1);
        
        vm.prank(minter);
        pass.transferFrom(minter, buyer, 1);

        (
            ,               // storedMinter
            address current,// tokenHolder (was currentOwner)
            ,               // txnCount
            ,               // volume
            ,               // minterEarned
            /* creatorEarned */
        ) = distributor.getTokenRoyaltyData(address(pass), 1);

        assertEq(current, buyer);
    }
}