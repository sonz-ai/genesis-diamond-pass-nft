// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/programmable-royalties/CentralizedRoyaltyAdapter.sol";
import "src/DiamondGenesisPass.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";

// Mock implementation of the adapter for testing constructor error cases
contract MockRoyaltyAdapter is CentralizedRoyaltyAdapter {
    constructor(address distributor_, uint256 feeNumerator_) 
        CentralizedRoyaltyAdapter(distributor_, feeNumerator_) {}
}

// Mock extension of the adapter to test the behavior when the distributor is unregistered
contract UnregisteredCollectionAdapter is CentralizedRoyaltyAdapter {
    constructor(address distributor_, uint256 feeNumerator_)
        CentralizedRoyaltyAdapter(distributor_, feeNumerator_) {}
        
    // Override to test unregistered collection behavior
    function forceRevertsOnConfig() public view {
        // This should revert since this contract is not registered with the distributor
        this.minterShares();
    }
}

contract CentralizedRoyaltyAdapterExtendedTest is Test {
    CentralizedRoyaltyDistributor public distributor;
    DiamondGenesisPass public nft;
    MockRoyaltyAdapter public mockAdapter;
    UnregisteredCollectionAdapter public unregisteredAdapter;
    
    address public admin = address(0x1001);
    address public service = address(0x1002);
    address public creator = address(0x1003);
    address public user1 = address(0x1111);
    address public user2 = address(0x2222);
    
    // Events for testing
    event RoyaltyDistributorSet(address indexed distributor);
    event RoyaltyFeeNumeratorSet(uint256 feeNumerator);
    
    function setUp() public {
        // Deploy distributor and set roles
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        
        // Deploy NFT with adapter
        nft = new DiamondGenesisPass(address(distributor), 750, creator);
        distributor.registerCollection(address(nft), 750, 2000, 8000, creator);
        
        // Deploy unregistered adapter for testing
        unregisteredAdapter = new UnregisteredCollectionAdapter(address(distributor), 500);
        
        vm.stopPrank();
        
        // Fund accounts
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
    }
    
    // Test 1: Constructor error cases
    function testConstructorZeroAddressRevert() public {
        vm.expectRevert(CentralizedRoyaltyAdapter.CentralizedRoyaltyAdapter__DistributorCannotBeZeroAddress.selector);
        mockAdapter = new MockRoyaltyAdapter(address(0), 500);
    }
    
    function testConstructorExcessFeeRevert() public {
        vm.expectRevert(CentralizedRoyaltyAdapter.CentralizedRoyaltyAdapter__RoyaltyFeeWillExceedSalePrice.selector);
        mockAdapter = new MockRoyaltyAdapter(address(distributor), 15000); // 150% fee
    }
    
    function testConstructorWithMaxFee() public {
        // Test with maximum allowed fee (100%)
        mockAdapter = new MockRoyaltyAdapter(address(distributor), 10000);
        assertEq(mockAdapter.royaltyFeeNumerator(), 10000);
    }
    
    function testConstructorEmitsEvents() public {
        vm.expectEmit(true, false, false, true);
        emit RoyaltyDistributorSet(address(distributor));
        
        vm.expectEmit(false, false, false, true);
        emit RoyaltyFeeNumeratorSet(500);
        
        mockAdapter = new MockRoyaltyAdapter(address(distributor), 500);
    }
    
    // Test 2: Token royalty data functionality
    function testTokenRoyaltyDataAfterBatchUpdate() public {
        // Mint a token
        vm.prank(admin);
        nft.mintOwner(user1);
        
        // Prepare batch data for a simulated sale
        uint256[] memory tokenIds = new uint256[](1);
        address[] memory minters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        uint256[] memory timestamps = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);
        
        tokenIds[0] = 1;
        minters[0] = user1;
        salePrices[0] = 1 ether;
        timestamps[0] = block.timestamp;
        txHashes[0] = keccak256(abi.encodePacked("tx1"));
        
        // Update royalty data
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            minters,
            salePrices,
            timestamps,
            txHashes
        );
        
        // Query token royalty data through adapter
        (
            address minter,
            address currentOwner,
            uint256 transactionCount,
            uint256 totalVolume,
            uint256 minterRoyaltyEarned,
            uint256 creatorRoyaltyEarned
        ) = nft.tokenRoyaltyData(1);
        
        // Verify data is correct
        assertEq(minter, user1);
        assertEq(currentOwner, user1); // Initially set to minter
        assertEq(transactionCount, 1);
        assertEq(totalVolume, 1 ether);
        
        // Verify royalties are split correctly
        uint256 royaltyAmount = (1 ether * 750) / 10000; // 7.5% of 1 ETH
        uint256 expectedMinterShare = (royaltyAmount * 2000) / 10000; // 20% to minter
        uint256 expectedCreatorShare = (royaltyAmount * 8000) / 10000; // 80% to creator
        
        assertEq(minterRoyaltyEarned, expectedMinterShare);
        assertEq(creatorRoyaltyEarned, expectedCreatorShare);
    }
    
    // Test 3: Unregistered collection behavior
    function testUnregisteredCollectionCalls() public {
        // The unregistered adapter should revert when trying to access distributor data
        vm.expectRevert(CentralizedRoyaltyDistributor.RoyaltyDistributor__CollectionNotRegistered.selector);
        unregisteredAdapter.forceRevertsOnConfig();
    }
    
    // Test 4: Interface support
    function testSupportsMultipleInterfaces() public {
        // Test basic interfaces beyond just IERC2981
        assertTrue(nft.supportsInterface(type(IERC2981).interfaceId));
        assertTrue(nft.supportsInterface(type(IERC165).interfaceId));
        
        // Test non-supported interface
        bytes4 nonSupportedInterface = bytes4(keccak256("nonSupportedInterface()"));
        assertFalse(nft.supportsInterface(nonSupportedInterface));
    }
    
    // Test 5: Royalty calculation with edge cases
    function testRoyaltyCalculationEdgeCases() public {
        // Test zero sale price
        (address receiver, uint256 amount) = nft.royaltyInfo(1, 0);
        assertEq(receiver, address(distributor));
        assertEq(amount, 0);
        
        // Test with very large sale price
        uint256 bigSalePrice = 1000000 ether;
        (receiver, amount) = nft.royaltyInfo(1, bigSalePrice);
        assertEq(receiver, address(distributor));
        assertEq(amount, (bigSalePrice * 750) / 10000);
        
        // Test with very small sale price (smaller than denominator)
        uint256 smallSalePrice = 100; // Very small amount
        (receiver, amount) = nft.royaltyInfo(1, smallSalePrice);
        assertEq(receiver, address(distributor));
        // For very small prices, the royalty might be 0 due to integer division
        assertEq(amount, (smallSalePrice * 750) / 10000);
    }
    
    // Test 6: Local royalty fee vs distributor royalty fee
    function testLocalVsDistributorRoyaltyFee() public {
        // Deploy a new NFT with different fee
        vm.startPrank(admin);
        DiamondGenesisPass newNft = new DiamondGenesisPass(address(distributor), 500, creator);
        // Register with a DIFFERENT fee than passed to constructor
        distributor.registerCollection(address(newNft), 750, 2000, 8000, creator);
        vm.stopPrank();
        
        // The adapter's royaltyInfo should use the local fee (500)
        (address receiver, uint256 amount) = newNft.royaltyInfo(1, 1 ether);
        assertEq(receiver, address(distributor));
        assertEq(amount, (1 ether * 500) / 10000); // Uses 500, not 750
        
        // The distributorRoyaltyFeeNumerator view function should return the distributor's fee
        assertEq(newNft.distributorRoyaltyFeeNumerator(), 750);
        
        // This demonstrates the fee used for royaltyInfo can be different than the one in the distributor
    }
    
    // Test 7: Gas usage for view functions
    function testGasUsageForViewFunctions() public {
        // Create token and batch update with many transactions to simulate realistic data
        vm.prank(admin);
        nft.mintOwner(user1);
        
        // Set up batch data generation
        uint256 batchSize = 10;
        uint256[] memory tokenIds = new uint256[](batchSize);
        address[] memory minters = new address[](batchSize);
        uint256[] memory salePrices = new uint256[](batchSize);
        uint256[] memory timestamps = new uint256[](batchSize);
        bytes32[] memory txHashes = new bytes32[](batchSize);
        
        // Generate batch data (all for token 1)
        for (uint256 i = 0; i < batchSize; i++) {
            tokenIds[i] = 1;
            minters[i] = user1;
            salePrices[i] = 1 ether * (i + 1);
            timestamps[i] = block.timestamp + i;
            txHashes[i] = keccak256(abi.encodePacked("tx", i));
        }
        
        // Update batch data
        vm.prank(service);
        distributor.batchUpdateRoyaltyData(
            address(nft),
            tokenIds,
            minters,
            salePrices,
            timestamps,
            txHashes
        );
        
        // Measure gas usage for different view functions
        uint256 gasStart = gasleft();
        nft.royaltyInfo(1, 1 ether);
        uint256 royaltyInfoGas = gasStart - gasleft();
        
        gasStart = gasleft();
        nft.tokenRoyaltyData(1);
        uint256 tokenRoyaltyDataGas = gasStart - gasleft();
        
        gasStart = gasleft();
        nft.minterOf(1);
        uint256 minterOfGas = gasStart - gasleft();
        
        // No assertions, but we log the gas usage for monitoring
        console.log("Gas usage - royaltyInfo:", royaltyInfoGas);
        console.log("Gas usage - tokenRoyaltyData:", tokenRoyaltyDataGas);
        console.log("Gas usage - minterOf:", minterOfGas);
    }
    
    // Test 8: activeMerkleRoot changes properly when updated in distributor
    function testActiveMerkleRootUpdates() public {
        // Initially zero
        assertEq(nft.activeMerkleRoot(), bytes32(0));
        
        // Submit a merkle root
        bytes32 newRoot = keccak256(abi.encodePacked("test root"));
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), newRoot, 0);
        
        // Check that the adapter returns the updated value
        assertEq(nft.activeMerkleRoot(), newRoot);
        
        // Submit a different root
        bytes32 anotherRoot = keccak256(abi.encodePacked("another root"));
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), anotherRoot, 0);
        
        // Verify it updates again
        assertEq(nft.activeMerkleRoot(), anotherRoot);
    }
    
    // Test 9: Verify tokenRoyaltyData for nonexistent token
    function testTokenRoyaltyDataForNonexistentToken() public {
        // Query data for token that doesn't exist yet
        (
            address minter,
            address currentOwner,
            uint256 transactionCount,
            uint256 totalVolume,
            uint256 minterRoyaltyEarned,
            uint256 creatorRoyaltyEarned
        ) = nft.tokenRoyaltyData(999);
        
        // All values should be zero/empty
        assertEq(minter, address(0));
        assertEq(currentOwner, address(0));
        assertEq(transactionCount, 0);
        assertEq(totalVolume, 0);
        assertEq(minterRoyaltyEarned, 0);
        assertEq(creatorRoyaltyEarned, 0);
    }
} 