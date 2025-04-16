// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "src/access/OwnableBasic.sol";
import "src/erc721c/ERC721C.sol";
import "src/programmable-royalties/CentralizedRoyaltyAdapter.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/token/erc721/MetadataURI.sol";
import "src/minting/MerkleWhitelistMint.sol";
import "src/minting/MaxSupply.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

/**
 * @title Diamond Genesis Pass
 * @author Custom implementation based on Limit Break, Inc. patterns
 * @notice Extension of ERC721C that works with a centralized royalty distributor,
 *         which is compatible with OpenSea's single-address royalty model while
 *         still supporting minter/creator royalty sharing.
 * @dev These contracts are intended for example use and are not intended for production deployments as-is.
 * 
 * @notice IMPORTANT: After deployment, the contract owner must:
 *         1. Set the merkle root using setMerkleRoot(bytes32 merkleRoot_) 
 *         2. Open the claim period using openClaims(uint256 closingTimestamp)
 *         3. To enable public minting, use setPublicMintActive(true)
 */
contract ERC721CWithCentralizedRoyalties is 
    ERC721C, 
    MetadataURI,
    MerkleWhitelistMint,
    IERC2981,
    Ownable {
    using Strings for uint256;
    
    // Fixed max supply value
    uint256 private constant MAX_SUPPLY = 888;
    
    // Fixed royalty shares
    uint256 private constant MINTER_SHARES = 20;
    uint256 private constant CREATOR_SHARES = 80;
    
    // Public mint price in ETH
    uint256 private constant PUBLIC_MINT_PRICE = 0.28 ether;
    
    // Boolean to control if public minting is active
    bool private isPublicMintActive;
    
    // Reference to the distributor for tracking token minting
    CentralizedRoyaltyDistributor public centralizedDistributor;

    // Royalty related variables
    address public royaltyDistributor;
    uint256 public royaltyFeeNumerator;
    uint256 public constant FEE_DENOMINATOR = 10_000;
    
    // Error definitions
    error InsufficientPayment();
    error PublicMintNotActive();
    error CentralizedRoyaltyAdapter__DistributorCannotBeZeroAddress();
    error CentralizedRoyaltyAdapter__RoyaltyFeeWillExceedSalePrice();
    error CentralizedRoyaltyAdapter__CollectionNotRegistered();
    
    // Events
    event PublicMintStatusUpdated(bool isActive);
    event RoyaltyDistributorSet(address indexed distributor);
    event RoyaltyFeeNumeratorSet(uint256 feeNumerator);
    
    constructor(
        address royaltyDistributor_,
        uint96 royaltyFeeNumerator_,
        address creator_) 
        ERC721OpenZeppelin("Diamond Genesis Pass Beta", "BetaDiamondGenesisPass") 
        MaxSupply(MAX_SUPPLY, MAX_SUPPLY)
        MerkleWhitelistMint(1, type(uint256).max) { // Each whitelisted address can mint only 1, infinite merkle root changes
            
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
            
            centralizedDistributor = CentralizedRoyaltyDistributor(payable(royaltyDistributor_));
            
            // Register this collection with the distributor during construction
            // This avoids redundant storage of config values
            centralizedDistributor.registerCollection(
                address(this),
                royaltyFeeNumerator_,
                MINTER_SHARES,
                CREATOR_SHARES,
                creator_
            );
    }

    /**
     * @notice Set whether public minting is active
     * @dev Only callable by contract owner
     * @param _isActive Whether public minting should be active
     */
    function setPublicMintActive(bool _isActive) external {
        _requireCallerIsContractOwner();
        isPublicMintActive = _isActive;
        emit PublicMintStatusUpdated(_isActive);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721C, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || 
            ERC721C.supportsInterface(interfaceId);
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
        (, uint256 minterSharesValue,,) = centralizedDistributor.getCollectionConfig(address(this));
        return minterSharesValue;
    }

    /**
     * @notice Returns the creator shares from the centralized distributor for this collection
     * @return The creator shares
     */
    function creatorShares() public view returns (uint256) {
        (, , uint256 creatorSharesValue,) = centralizedDistributor.getCollectionConfig(address(this));
        return creatorSharesValue;
    }

    /**
     * @notice Returns the creator address from the centralized distributor for this collection
     * @return The creator address
     */
    function creator() public view returns (address) {
        (,, , address creatorAddress) = centralizedDistributor.getCollectionConfig(address(this));
        return creatorAddress;
    }

    /**
     * @notice Returns the minter of the token with id `tokenId`
     * @param tokenId The id of the token whose minter is being queried
     * @return The minter of the token with id `tokenId`
     */
    function minterOf(uint256 tokenId) external view returns (address) {
        return centralizedDistributor.getMinter(address(this), tokenId);
    }

    /**
     * @notice Returns the royalty fee numerator from the centralized distributor for this collection
     * @return The royalty fee numerator
     */
    function distributorRoyaltyFeeNumerator() public view returns (uint256) {
        (uint256 royaltyFeeNum,,,) = centralizedDistributor.getCollectionConfig(address(this));
        return royaltyFeeNum;
    }

    /**
     * @notice Override of the whitelist minting function that adds payment functionality
     * @dev Uses a custom implementation with payment functionality
     * @param quantity The quantity to mint (should be 1 for this implementation)
     */
    function whitelistMint(uint256 quantity, bytes32[] calldata /* merkleProof */) external payable override {
        // Check payment
        if (msg.value < PUBLIC_MINT_PRICE) {
            revert InsufficientPayment();
        }
        
        // Check total supply
        _requireLessThanMaxSupply(mintedSupply() + quantity);
        
        // Mint the token(s)
        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = mintedSupply() + i + 1;
            _mint(_msgSender(), tokenId);
        }
        
        // Forward payment to the contract owner
        (bool success, ) = payable(owner()).call{value: msg.value}("");
        require(success, "Payment forwarding failed");
    }

    /**
     * @notice Public mint function, only active when isPublicMintActive is true
     * @dev Throws if public mint is not active
     * @param to The recipient of the token
     * @param tokenId The ID of the token to mint
     */
    function mint(address to, uint256 tokenId) external payable {
        // Check if public mint is active
        if (!isPublicMintActive) {
            revert PublicMintNotActive();
        }
        
        // Check payment
        if (msg.value < PUBLIC_MINT_PRICE) {
            revert InsufficientPayment();
        }
        
        // Check total supply
        _requireLessThanMaxSupply(mintedSupply() + 1);
        
        // Mint the token
        _mint(to, tokenId);
        
        // Forward payment to the contract owner
        (bool success, ) = payable(owner()).call{value: msg.value}("");
        require(success, "Payment forwarding failed");
    }
    
    /**
     * @notice Safe version of the public mint function
     * @dev Throws if public mint is not active
     * @param to The recipient of the token
     * @param tokenId The ID of the token to mint
     */
    function safeMint(address to, uint256 tokenId) external payable {
        // Check if public mint is active
        if (!isPublicMintActive) {
            revert PublicMintNotActive();
        }
        
        // Check payment
        if (msg.value < PUBLIC_MINT_PRICE) {
            revert InsufficientPayment();
        }
        
        // Check total supply
        _requireLessThanMaxSupply(mintedSupply() + 1);
        
        // Mint the token
        _safeMint(to, tokenId);
        
        // Forward payment to the contract owner
        (bool success, ) = payable(owner()).call{value: msg.value}("");
        require(success, "Payment forwarding failed");
    }
    
    /**
     * @notice Simple mint function that owner can use to mint to another address
     * @dev Only callable by the contract owner
     * @param to The recipient of the token
     * @param tokenId The ID of the token to mint
     */
    function mintOwner(address to, uint256 tokenId) external {
        _requireCallerIsContractOwner();
        _mint(to, tokenId);
    }

    function safeMintOwner(address to, uint256 tokenId) external {
        _requireCallerIsContractOwner();
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
    }

    function _mint(address to, uint256 tokenId) internal virtual override {
        // Register the minter with the centralized distributor
        centralizedDistributor.setTokenMinter(address(this), tokenId, to);
        super._mint(to, tokenId);
    }

    /**
     * @notice Get the base URI for token metadata
     * @dev This is used by the tokenURI function
     */
    function baseURI() public view virtual returns (string memory) {
        return _baseURI();
    }

    /**
     * @notice Get the token URI for a specific token
     * @param tokenId The token ID to get the URI for
     * @return The token URI
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) {
            revert("ERC721: URI query for nonexistent token");
        }
        
        string memory base = baseURI();
        
        return bytes(base).length > 0 
            ? string(abi.encodePacked(base, tokenId.toString(), suffixURI))
            : "";
    }

    function _burn(uint256 tokenId) internal virtual override {
        super._burn(tokenId);
        // No need to handle anything with the distributor when burning
    }

    /**
     * @notice Implementation of the OwnablePermissions abstract function
     * @dev This function is called by functions that require the caller to be the contract owner
     */
    function _requireCallerIsContractOwner() internal view virtual override {
        if (msg.sender != owner()) {
            revert("Caller is not the contract owner");
        }
    }
}