// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/SonzaiGenesisPass.sol";

contract SonzaiGenesisPassTest is Test {
    SonzaiGenesisPass public nft;
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public royaltyReceiver = address(0x4);
    address public functionsRouter = address(0x5);
    
    // Chainlink Functions variables
    bytes32 public donId = bytes32(uint256(1));
    uint64 public subscriptionId = 1;
    uint32 public callbackGasLimit = 300000;
    string public apiKey = "test-api-key";
    string public encryptedSecretsReference = "test-secrets-reference";
    
    // Mock request IDs for Chainlink Functions
    bytes32 public user1RequestId = bytes32(uint256(100));
    bytes32 public user2RequestId = bytes32(uint256(200));
    
    function setUp() public {
        // Set up the test environment
        vm.startPrank(owner);
        
        // Deploy the contract
        nft = new SonzaiGenesisPass(
            royaltyReceiver,
            "https://api.sonzai.io/metadata/",
            functionsRouter,
            donId,
            subscriptionId,
            callbackGasLimit,
            apiKey,
            encryptedSecretsReference
        );
        
        vm.stopPrank();
    }
    
    function testConstructor() public {
        assertEq(nft.getMaxSupply(), 10000);
        assertEq(nft.getMintPrice(), 0.28 ether);
        assertEq(nft.ROYALTY_PERCENTAGE(), 1100); // 11%
        assertEq(nft.donId(), donId);
        assertEq(nft.subscriptionId(), subscriptionId);
        assertEq(nft.callbackGasLimit(), callbackGasLimit);
        assertEq(nft.apiKey(), apiKey);
    }
    
    // Mock the Chainlink Functions request and response
    function testWhitelistVerificationAndMint() public {
        // Request whitelist verification for user1
        vm.startPrank(user1);
        
        // Mock the Chainlink Functions request
        vm.mockCall(
            functionsRouter,
            abi.encodeWithSelector(bytes4(keccak256(bytes("sendRequest(uint64,bytes,uint16,uint32,bytes32)")))),
            abi.encode(user1RequestId)
        );
        
        // Request whitelist verification
        bytes32 requestId = nft.requestWhitelistVerification();
        assertEq(requestId, user1RequestId);
        
        vm.stopPrank();
        
        // Mock the Chainlink Functions response (as the router)
        vm.startPrank(functionsRouter);
        
        // Encode a successful response (1 = whitelisted)
        bytes memory response = abi.encode(uint256(1));
        bytes memory err = new bytes(0);
        
        // Call the fulfillment function
        nft.handleOracleFulfillment(user1RequestId, response, err);
        
        vm.stopPrank();
        
        // Verify user1 is now whitelisted
        assertTrue(nft.isWhitelisted(user1));
        
        // Now user1 can mint
        vm.startPrank(user1);
        vm.deal(user1, 1 ether); // Give user1 some ETH
        
        nft.whitelistMint{value: 0.28 ether}();
        
        assertEq(nft.totalSupply(), 1);
        assertEq(nft.ownerOf(0), user1);
        assertTrue(nft.whitelistMinted(user1));
        
        vm.stopPrank();
    }
    
    function testFailWhitelistMintWithoutVerification() public {
        // Try to mint without being verified
        vm.startPrank(user1);
        vm.deal(user1, 1 ether);
        
        nft.whitelistMint{value: 0.28 ether}();
        
        vm.stopPrank();
    }
    
    function testPublicMint() public {
        // Enable public mint
        vm.startPrank(owner);
        nft.togglePublicMint(true);
        vm.stopPrank();
        
        // Mint as user2
        vm.startPrank(user2);
        vm.deal(user2, 1 ether); // Give user2 some ETH
        
        nft.publicMint{value: 0.28 ether}();
        
        assertEq(nft.totalSupply(), 1);
        assertEq(nft.ownerOf(0), user2);
        
        vm.stopPrank();
    }
    
    function testFailPublicMintWhenDisabled() public {
        // Public mint is disabled by default
        vm.startPrank(user2);
        vm.deal(user2, 1 ether);
        
        nft.publicMint{value: 0.28 ether}();
        
        vm.stopPrank();
    }
    
    function testFailInsufficientPayment() public {
        // Enable public mint
        vm.startPrank(owner);
        nft.togglePublicMint(true);
        vm.stopPrank();
        
        // Try to mint with insufficient payment
        vm.startPrank(user2);
        vm.deal(user2, 1 ether);
        
        nft.publicMint{value: 0.27 ether}(); // Less than required
        
        vm.stopPrank();
    }
    
    function testBatchMint() public {
        vm.startPrank(owner);
        
        nft.mintBatch(owner, 5);
        
        assertEq(nft.totalSupply(), 5);
        for (uint256 i = 0; i < 5; i++) {
            assertEq(nft.ownerOf(i), owner);
        }
        
        vm.stopPrank();
    }
    
    function testBurn() public {
        // Mint a token first
        vm.startPrank(owner);
        nft.mintBatch(owner, 1);
        
        // Burn the token
        nft.burn(0);
        
        // Verify it's burned (should revert when trying to get owner)
        vm.expectRevert();
        nft.ownerOf(0);
        
        vm.stopPrank();
    }
    
    function testRoyaltyInfo() public {
        // Mint a token
        vm.startPrank(owner);
        nft.mintBatch(owner, 1);
        vm.stopPrank();
        
        // Check royalty info
        (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(0, 100 ether);
        
        assertEq(receiver, royaltyReceiver);
        assertEq(royaltyAmount, 11 ether); // 11% of 100 ether
    }
    
    function testWithdraw() public {
        // Enable public mint
        vm.startPrank(owner);
        nft.togglePublicMint(true);
        vm.stopPrank();
        
        // Mint as user2 to add funds to contract
        vm.startPrank(user2);
        vm.deal(user2, 1 ether);
        nft.publicMint{value: 0.28 ether}();
        vm.stopPrank();
        
        // Check contract balance
        assertEq(address(nft).balance, 0.28 ether);
        
        // Withdraw as owner
        uint256 ownerBalanceBefore = owner.balance;
        vm.startPrank(owner);
        nft.withdraw();
        vm.stopPrank();
        
        // Check balances after withdrawal
        assertEq(address(nft).balance, 0);
        assertEq(owner.balance, ownerBalanceBefore + 0.28 ether);
    }
}
