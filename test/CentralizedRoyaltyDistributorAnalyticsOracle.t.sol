// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";

// We don't need this contract anymore since we'll use the event from the distributor directly
// // Emitted events
// contract Emitted {
//     event OracleUpdateIntervalSet(address indexed collection, uint256 minBlockInterval);
// }

contract CentralizedRoyaltyDistributorAnalyticsOracleTest is Test {
    // Declare event signature for expectEmit
    // Emitted emitted; // Remove this line
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass nft;
    address admin = address(0xA11CE);
    address service = address(0xBEEF);
    address creator = address(0xC0FFEE);
    address user = address(0x1234);
    uint96 royaltyNum = 500; // 5%
    
    // Redeclare the event for testing
    event OracleUpdateIntervalSet(address indexed collection, uint256 minBlockInterval);

    function setUp() public {
        // Deploy and configure distributor
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        vm.stopPrank();

        // Deploy NFT and register collection
        vm.startPrank(admin);
        nft = new DiamondGenesisPass(address(distributor), royaltyNum, creator);
        distributor.registerCollection(address(nft), royaltyNum, 2000, 8000, creator);
        vm.stopPrank();
    }

    function testInitialAnalyticsAndViews() public {
        // Initial totals
        assertEq(distributor.totalAccrued(), 0);
        assertEq(distributor.totalClaimed(), 0);

        // Collection royalties
        assertEq(distributor.getCollectionRoyalties(address(nft)), 0);
        (uint256 vol, uint256 lastBlock, uint256 collected) = distributor.getCollectionRoyaltyData(address(nft));
        assertEq(vol, 0);
        // Block number should be set during registration in setUp
        uint256 expectedBlock = block.number; 
        assertEq(lastBlock, expectedBlock);
        assertEq(collected, 0);

        // Merkle root and claims
        assertEq(distributor.getActiveMerkleRoot(address(nft)), bytes32(0));
        assertFalse(distributor.hasClaimedMerkle(bytes32(0), user));
        (uint256 totalAmt, uint256 ts) = distributor.getMerkleRootInfo(bytes32(0));
        assertEq(totalAmt, 0);
        assertEq(ts, 0);
    }

    function testSetOracleIntervalAndUnauthorized() public {
        // Only admin can set interval
        vm.prank(admin);
        vm.expectEmit(true, true, false, true, address(distributor));
        emit OracleUpdateIntervalSet(address(nft), 3);
        distributor.setOracleUpdateMinBlockInterval(address(nft), 3);

        // Non-admin revert
        vm.prank(user);
        vm.expectRevert();
        distributor.setOracleUpdateMinBlockInterval(address(nft), 1);
    }

    function testUpdateRoyaltyDataViaOracleRateLimit() public {
        // Default minInterval = 0, should succeed
        vm.prank(user);
        distributor.updateRoyaltyDataViaOracle(address(nft));

        // Set interval to 2
        vm.prank(admin);
        distributor.setOracleUpdateMinBlockInterval(address(nft), 2);

        // First call after setting, lastOracle=0, block < 0+2 => revert
        vm.prank(user);
        vm.expectRevert(
            CentralizedRoyaltyDistributor.RoyaltyDistributor__OracleUpdateTooFrequent.selector
        );
        distributor.updateRoyaltyDataViaOracle(address(nft));

        // Advance blocks
        vm.roll(block.number + 2);
        vm.prank(user);
        distributor.updateRoyaltyDataViaOracle(address(nft));
    }

    function testUpdateOracleUnregisteredReverts() public {
        address fake = address(0x999);
        vm.prank(user);
        vm.expectRevert(
            CentralizedRoyaltyDistributor.RoyaltyDistributor__CollectionNotRegistered.selector
        );
        distributor.updateRoyaltyDataViaOracle(fake);
    }
}
