// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "../access/OwnablePermissions.sol";
import "./CentralizedRoyaltyDistributor.sol";

/**
 * @title CentralizedRoyaltyAdapter
 * @author Custom implementation based on Limit Break, Inc. patterns
 * @notice An adapter that implements IERC2981 and forwards royalty information requests to a centralized distributor.
 *         This makes the collection compatible with OpenSea's single-address royalty model.
 */
abstract contract CentralizedRoyaltyAdapter is IERC2981, ERC165, OwnablePermissions {
    address public royaltyDistributor;
    uint256 public royaltyFeeNumerator;
    uint256 public constant FEE_DENOMINATOR = 10_000;

    error CentralizedRoyaltyAdapter__DistributorCannotBeZeroAddress();
    error CentralizedRoyaltyAdapter__RoyaltyFeeWillExceedSalePrice();
    error CentralizedRoyaltyAdapter__CollectionNotRegistered();
    error CentralizedRoyaltyAdapter__CallerIsNotContractOwner();

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
     *      centralized royalty distributor as the recipient.
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
     * @notice Indicates whether the contract implements the specified interface.
     * @dev Overrides supportsInterface in ERC165.
     * @param interfaceId The interface id
     * @return true if the contract implements the specified interface, false otherwise
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }
    
    /**
     * @notice Implementation of the OwnablePermissions abstract function
     * @dev This function is called by functions that require the caller to be the contract owner
     */
    function _requireCallerIsContractOwner() internal view virtual override {
        if (msg.sender != owner()) {
            revert CentralizedRoyaltyAdapter__CallerIsNotContractOwner();
        }
    }
    
    /**
     * @notice Returns the contract owner
     * @dev This function should be implemented by the inheriting contract
     */
    function owner() public view virtual returns (address);
}