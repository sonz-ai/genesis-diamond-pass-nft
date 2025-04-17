// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/DiamondGenesisPass.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DummyERC20 is ERC20 {
    constructor() ERC20("DummyToken", "DUM") {}
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract CentralizedRoyaltyDistributorERC20FlowTest is Test {
    CentralizedRoyaltyDistributor distributor;
    DiamondGenesisPass nft;
    DummyERC20 token;
    address admin = address(0xA11CE);
    address service = address(0xBEEF);
    address creator = address(0xC0FFEE);
    address user = address(0x1);

    function setUp() public {
        // Deploy distributor and grant service role
        vm.startPrank(admin);
        distributor = new CentralizedRoyaltyDistributor();
        distributor.grantRole(distributor.SERVICE_ACCOUNT_ROLE(), service);
        vm.stopPrank();
        
        // Deploy NFT contract and register with distributor
        vm.startPrank(admin);
        nft = new DiamondGenesisPass(address(distributor), 500, creator);
        distributor.registerCollection(address(nft), 500, 2000, 8000, creator);
        vm.stopPrank();

        // Deploy dummy ERC20 token
        token = new DummyERC20();
    }

    function testAddERC20RoyaltiesAndClaim() public {
        // Mint and approve tokens to distributor
        vm.startPrank(service);
        token.mint(service, 1000 ether);
        token.approve(address(distributor), 1000 ether);
        distributor.addCollectionERC20Royalties(address(nft), token, 100 ether);
        vm.stopPrank();

        // Create single-leaf Merkle root for claim
        uint256 amount = 10 ether;
        bytes32 leaf = keccak256(abi.encodePacked(address(user), address(token), amount));
        bytes32 root = leaf;
        bytes32[] memory proof = new bytes32[](0);

        // Submit Merkle root
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), root, 0); // Change to 0 since we're testing ERC20, not ETH

        // Claim tokens
        vm.prank(user);
        distributor.claimERC20RoyaltiesMerkle(address(nft), user, token, amount, proof);

        assertEq(token.balanceOf(user), amount);
    }

    function testClaimERC20RoyaltiesNoRootReverts() public {
        vm.expectRevert(
            CentralizedRoyaltyDistributor.RoyaltyDistributor__NoActiveMerkleRoot.selector
        );
        distributor.claimERC20RoyaltiesMerkle(address(nft), user, token, 1 ether, new bytes32[](0));
    }

    function testClaimERC20RoyaltiesInvalidProofReverts() public {
        // Deposit tokens
        vm.startPrank(service);
        token.mint(service, 50 ether);
        token.approve(address(distributor), 50 ether);
        distributor.addCollectionERC20Royalties(address(nft), token, 50 ether);
        vm.stopPrank();
        
        // Submit root with amount 5 ether
        uint256 claimAmount = 5 ether;
        bytes32 root = keccak256(abi.encodePacked(address(user), address(token), claimAmount));
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), root, 0); // Change to 0 since we're testing ERC20, not ETH

        // Attempt claim with bad proof
        vm.prank(user);
        vm.expectRevert(
            CentralizedRoyaltyDistributor.RoyaltyDistributor__InvalidProof.selector
        );
        distributor.claimERC20RoyaltiesMerkle(address(nft), user, token, claimAmount, new bytes32[](1));
    }

    function testClaimERC20RoyaltiesInsufficientBalanceReverts() public {
        // Deposit less tokens than claimable
        vm.startPrank(service);
        token.mint(service, 5 ether);
        token.approve(address(distributor), 5 ether);
        distributor.addCollectionERC20Royalties(address(nft), token, 5 ether);
        vm.stopPrank();

        // Submit root for 10 ether
        uint256 claimAmount = 10 ether;
        bytes32 leaf = keccak256(abi.encodePacked(address(user), address(token), claimAmount));
        bytes32 root = leaf;
        vm.prank(service);
        distributor.submitRoyaltyMerkleRoot(address(nft), root, 0); // Change to 0 since we're testing ERC20, not ETH

        // Claim should revert
        vm.prank(user);
        vm.expectRevert(
            CentralizedRoyaltyDistributor.RoyaltyDistributor__NotEnoughTokensToDistributeForCollection.selector
        );
        distributor.claimERC20RoyaltiesMerkle(address(nft), user, token, claimAmount, new bytes32[](0));
    }
}
