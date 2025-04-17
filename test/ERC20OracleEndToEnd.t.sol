// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock Chainlink Oracle for testing
contract MockOracle {
    event OracleRequest(bytes32 requestId, address requester, bytes data);
    
    function requestData(address collection, uint256 fromBlock) external returns (bytes32) {
        bytes32 requestId = keccak256(abi.encodePacked(collection, fromBlock, block.timestamp));
        emit OracleRequest(requestId, msg.sender, abi.encodePacked(collection, fromBlock));
        return requestId;
    }
    
    function fulfillRequest(
        bytes32 requestId,
        address distributor,
        address collection,
        uint256[] calldata tokenIds,
        address[] calldata minters,
        uint256[] calldata salePrices,
        uint256[] calldata timestamps,
        bytes32[] calldata txHashes
    ) external {
        // Call the fulfillment function on the distributor
        CentralizedRoyaltyDistributor(payable(distributor)).fulfillRoyaltyData(
            requestId,
            collection,
            tokenIds,
            minters,
            salePrices,
            timestamps,
            txHashes
        );
    }
}

// Mock ERC20 token
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1000000 * 10**18);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ERC20OracleEndToEndTest is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass nft;
    MockERC20 token;
    MockOracle oracle;
    
    address admin = address(0xA11CE);
    address service = address(0xBEEF);
    address creator = address(0xC0FFEE);
    address minter = address(0x1);
    address buyer = address(0x2);
    
    uint96 royaltyFee = 750; // 7.5%
    
    function setUp() public {
        // Deploy contracts
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        
        nft = new DiamondGenesisPass(address(distributor), royaltyFee, creator);
        distributor.registerCollection(address(nft), royaltyFee, 2000, 8000, creator);
        
        nft.setPublicMintActive(true);
        vm.stopPrank();
        
        // Deploy mock ERC20 token and oracle
        token = new MockERC20();
        oracle = new MockOracle();
        
        // Fund accounts
        vm.deal(minter, 10 ether);
        vm.deal(buyer, 10 ether);
        
        // Set oracle update interval
        vm.prank(admin);
        distributor.setOracleUpdateMinBlockInterval(address(nft), 1);
    }
    
    function testERC20AndOracleFlow() public {
        // Step 1: Mint NFT
        vm.prank(minter);
        nft.mint{value: 0.1 ether}(minter);
        
        // Step 2: Transfer NFT to simulate sale
        vm.prank(minter);
        nft.approve(buyer, 1);
        
        vm.prank(minter);
        nft.transferFrom(minter, buyer, 1);
        
        // Step 3: Record sale via service account
        vm.prank(service);
        nft.recordSale(1, 1 ether);
        
        // Step 4: Add ERC20 royalties to the distributor
        token.approve(address(distributor), 1000 * 10**18);
        distributor.addCollectionERC20Royalties(address(nft), token, 100 * 10**18);
        
        // Verify ERC20 royalties were added
        assertEq(distributor.getCollectionERC20Royalties(address(nft), token), 100 * 10**18);
        
        // Step 5: Trigger oracle update
        vm.roll(block.number + 2); // Advance blocks to pass rate limit
        vm.prank(service);
        distributor.updateRoyaltyDataViaOracle(address(nft));
        
        // Step 6: Simulate oracle callback with sale data
        uint256[] memory tokenIds = new uint256[](1);
        address[] memory minters = new address[](1);
        uint256[] memory salePrices = new uint256[](1);
        uint256[] memory timestamps = new uint256[](1);
        bytes32[] memory txHashes = new bytes32[](1);
        
        tokenIds[0] = 1;
        minters[0] = minter;
        salePrices[0] = 1 ether;
        timestamps[0] = block.timestamp;
        txHashes[0] = keccak256(abi.encodePacked("sale1"));
        
        bytes32 requestId = keccak256(abi.encodePacked(address(nft), uint256(0), block.timestamp));
        
        oracle.fulfillRequest(
            requestId,
            address(distributor),
            address(nft),
            tokenIds,
            minters,
            salePrices,
            timestamps,
            txHashes
        );
        
        // Step 7: Submit Merkle roots for ETH and ERC20 claims
        uint256 minterERC20Share = (100 * 10**18 * 2000) / 10000; // 20 tokens
        uint256 creatorERC20Share = (100 * 10**18 * 8000) / 10000; // 80 tokens
        
        bytes32 erc20Root = keccak256(abi.encodePacked(
            keccak256(abi.encodePacked(address(minter), address(token), minterERC20Share)),
            keccak256(abi.encodePacked(address(creator), address(token), creatorERC20Share))
        ));
        
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), erc20Root, 0);
        
        // Step 8: Claim ERC20 royalties
        bytes32[] memory minterProof = new bytes32[](1);
        minterProof[0] = keccak256(abi.encodePacked(address(creator), address(token), creatorERC20Share));
        
        vm.prank(minter);
        distributor.claimERC20RoyaltiesMerkle(
            address(nft),
            minter,
            token,
            minterERC20Share,
            minterProof
        );
        
        // Verify minter received their ERC20 tokens
        assertEq(token.balanceOf(minter), minterERC20Share);
        
        // Creator claims their ERC20 tokens
        bytes32[] memory creatorProof = new bytes32[](1);
        creatorProof[0] = keccak256(abi.encodePacked(address(minter), address(token), minterERC20Share));
        
        vm.prank(creator);
        distributor.claimERC20RoyaltiesMerkle(
            address(nft),
            creator,
            token,
            creatorERC20Share,
            creatorProof
        );
        
        // Verify creator received their ERC20 tokens
        assertEq(token.balanceOf(creator), creatorERC20Share);
        
        // Verify ERC20 royalties were distributed
        assertEq(distributor.getCollectionERC20Royalties(address(nft), token), 0);
    }
}
