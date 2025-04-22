// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./CentralizedRoyaltyDistributor.sol";

/**
 * @title CentralizedRoyaltyAdapter
 * @author Custom implementation based on Limit Break, Inc. patterns
 * @notice An adapter that implements IERC2981 and forwards royalty information requests to a centralized distributor.
 *         This makes the collection compatible with OpenSea's single-address royalty model while allowing royalties
 *         to be split between minters and the creator using a Merkle distributor pattern for gas-efficient claims.
 */
abstract contract CentralizedRoyaltyAdapter is IERC2981, ERC165 {
    address public royaltyDistributor;
    uint256 public royaltyFeeNumerator;
    uint256 public constant FEE_DENOMINATOR = 10_000;

    error CentralizedRoyaltyAdapter__DistributorCannotBeZeroAddress();
    error CentralizedRoyaltyAdapter__RoyaltyFeeWillExceedSalePrice();
    error CentralizedRoyaltyAdapter__CollectionNotRegistered();

    event RoyaltyDistributorSet(address indexed distributor);
    event RoyaltyFeeNumeratorSet(uint256 feeNumerator);

    /**
     * @notice Constructor to initialize the adapter with a royalty distributor and fee
     * @param royaltyDistributor_ The address of the centralized royalty distributor
     * @param royaltyFeeNumerator_ The royalty fee numerator (e.g., 750 for 7.5%)
     */
    constructor(address royaltyDistributor_, uint256 royaltyFeeNumerator_) {
        if (royaltyDistributor_ == address(0)) {
            revert CentralizedRoyaltyAdapter__DistributorCannotBeZeroAddress();
        }
        
        if (royaltyFeeNumerator_ > FEE_DENOMINATOR) {
            revert CentralizedRoyaltyAdapter__RoyaltyFeeWillExceedSalePrice();
        }
        
        royaltyDistributor = royaltyDistributor_;
        royaltyFeeNumerator = royaltyFeeNumerator_;
        
        emit RoyaltyDistributorSet(royaltyDistributor_);
        emit RoyaltyFeeNumeratorSet(royaltyFeeNumerator_);
    }

    /**
     * @notice Returns the royalty info for a given token ID and sale price.
     * @dev Instead of returning the token-specific payment splitter, it returns the
     *      centralized royalty distributor as the recipient. Marketplaces will send the full
     *      royalty amount to the distributor which will use a Merkle distribution system for claims.
     * @param salePrice The sale price
     * @return receiver The royalty distributor address
     * @return royaltyAmount The royalty amount
     */
    function royaltyInfo(
        uint256 /* tokenId */,
        uint256 salePrice
    ) external view override returns (address receiver, uint256 royaltyAmount) {
        return (royaltyDistributor, (salePrice * royaltyFeeNumerator) / FEE_DENOMINATOR);
    }

    /**
     * @notice Returns the minter shares from the centralized distributor for this collection
     * @return The minter shares
     */
    function minterShares() public view returns (uint256) {
        CentralizedRoyaltyDistributor distributor = CentralizedRoyaltyDistributor(payable(royaltyDistributor));
        (, uint256 minterSharesValue,,) = distributor.getCollectionConfig(address(this));
        return minterSharesValue;
    }

    /**
     * @notice Returns the creator shares from the centralized distributor for this collection
     * @return The creator shares
     */
    function creatorShares() public view returns (uint256) {
        CentralizedRoyaltyDistributor distributor = CentralizedRoyaltyDistributor(payable(royaltyDistributor));
        (, , uint256 creatorSharesValue,) = distributor.getCollectionConfig(address(this));
        return creatorSharesValue;
    }

    /**
     * @notice Returns the creator address from the centralized distributor for this collection
     * @return The creator address
     */
    function creator() public view returns (address) {
        CentralizedRoyaltyDistributor distributor = CentralizedRoyaltyDistributor(payable(royaltyDistributor));
        (,,, address creatorAddress) = distributor.getCollectionConfig(address(this));
        return creatorAddress;
    }

    /**
     * @notice Returns the minter of the token with id `tokenId`
     * @param tokenId The id of the token whose minter is being queried
     * @return The minter of the token with id `tokenId`
     */
    function minterOf(uint256 tokenId) external view returns (address) {
        CentralizedRoyaltyDistributor distributor = CentralizedRoyaltyDistributor(payable(royaltyDistributor));
        return distributor.getMinter(address(this), tokenId);
    }

    /**
     * @notice Returns the royalty fee numerator from the centralized distributor for this collection
     * @return The royalty fee numerator
     */
    function distributorRoyaltyFeeNumerator() public view returns (uint256) {
        CentralizedRoyaltyDistributor distributor = CentralizedRoyaltyDistributor(payable(royaltyDistributor));
        (uint256 royaltyFeeNum,,,) = distributor.getCollectionConfig(address(this));
        return royaltyFeeNum;
    }

    /**
     * @notice Get the active Merkle root for this collection
     * @return The active Merkle root
     */
    function activeMerkleRoot() public view returns (bytes32) {
        CentralizedRoyaltyDistributor distributor = CentralizedRoyaltyDistributor(payable(royaltyDistributor));
        return distributor.getActiveMerkleRoot(address(this));
    }

    /**
     * @notice Get royalty data for a token
     * @param tokenId The token ID
     * @return minter The token minter
     * @return currentOwner The current owner
     * @return transactionCount Number of transactions
     * @return totalVolume Total sales volume
     * @return minterRoyaltyEarned Total royalties earned by the minter
     * @return creatorRoyaltyEarned Total royalties earned by the creator
     */
    function tokenRoyaltyData(uint256 tokenId) external view returns (
        address minter,
        address currentOwner,
        uint256 transactionCount,
        uint256 totalVolume,
        uint256 minterRoyaltyEarned,
        uint256 creatorRoyaltyEarned
    ) {
        CentralizedRoyaltyDistributor distributor = CentralizedRoyaltyDistributor(payable(royaltyDistributor));
        return distributor.getTokenRoyaltyData(address(this), tokenId);
    }

    /**
     * @notice Get the total royalties earned for a specific token
     * @param tokenId The token ID
     * @return totalRoyalties Total royalties earned for this token
     */
    function getTotalTokenRoyalties(uint256 tokenId) external view returns (uint256 totalRoyalties) {
        CentralizedRoyaltyDistributor distributor = CentralizedRoyaltyDistributor(payable(royaltyDistributor));
        (,,,, uint256 minterShare, uint256 creatorShare) = distributor.getTokenRoyaltyData(address(this), tokenId);
        return minterShare + creatorShare;
    }

    /**
     * @notice Indicates whether the contract implements the specified interface.
     * @dev Overrides supportsInterface in ERC165.
     * @param interfaceId The interface id
     * @return true if the contract implements the specified interface, false otherwise
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }    
}