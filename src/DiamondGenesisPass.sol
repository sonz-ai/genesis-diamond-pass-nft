// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// import "src/access/OwnableBasic.sol"; // Using OpenZeppelin's Ownable instead
import "src/erc721c/ERC721C.sol";
import "src/programmable-royalties/CentralizedRoyaltyAdapter.sol"; // Now inheriting
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";
import "src/token/erc721/MetadataURI.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol"; // Using OpenZeppelin standard Ownable
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Diamond Genesis Pass
 * @author Custom implementation based on Limit Break, Inc. patterns
 * @notice Extension of ERC721C that works with a centralized royalty distributor,
 *         which is compatible with OpenSea's single-address royalty model while
 *         still supporting minter/creator royalty sharing based on accumulated pool distribution.
 * @dev Inherits from CentralizedRoyaltyAdapter to handle royalty info and views.
 * 
 * @notice IMPORTANT: After deployment, the contract owner must:
 *         1. Set the merkle root using setMerkleRoot(bytes32 merkleRoot_)
 *         2. To enable public minting, use setPublicMintActive(true)
 */
contract DiamondGenesisPass is 
    ERC721C, 
    MetadataURI, // Inherits OwnablePermissions via MetadataURI
    CentralizedRoyaltyAdapter, // Inherit the adapter
    Ownable, // Keep standard Ownable for contract-level ownership
    AccessControl // Add AccessControl for role management
{ 
    using Strings for uint256;
    
    // Fixed max supply value
    uint256 private constant MAX_SUPPLY = 888;
    
    // Fixed royalty shares (used only during registration with distributor)
    uint256 private constant MINTER_SHARES = 2000; // 20% in basis points
    uint256 private constant CREATOR_SHARES = 8000; // 80% in basis points
    
    // Public mint price in ETH
    uint256 public constant PUBLIC_MINT_PRICE = 0.28 ether;
    
    // Boolean to control if public minting is active
    bool private isPublicMintActive;
    
    // Merkle root for whitelist verification
    bytes32 private merkleRoot;
    
    // Track claimed whitelist addresses
    mapping(address => bool) private whitelistClaimed;
    
    // Count of minted tokens - used to determine next tokenId
    uint256 private _mintedCount;
    
    // Reference to the distributor - still needed for mint/recordSale
    CentralizedRoyaltyDistributor public immutable centralizedDistributor;

    // royaltyDistributor and royaltyFeeNumerator are now inherited from CentralizedRoyaltyAdapter
    // uint256 public constant FEE_DENOMINATOR = 10_000; // Also inherited

    // Error definitions
    error InsufficientPayment();
    error PublicMintNotActive();
    error MerkleRootNotSet();
    error InvalidMerkleProof();
    error AddressAlreadyClaimed();
    error MaxSupplyExceeded();
    error CallerIsNotOwner(); // For OwnablePermissions compatibility
    error CallerIsNotAdminOrServiceAccount(); // New error for role checks
    
    // Events
    event PublicMintStatusUpdated(bool isActive);
    event MerkleRootSet(bytes32 merkleRoot);
    event WhitelistMinted(address indexed to, uint256 quantity, uint256 startTokenId);
    event PublicMinted(address indexed to, uint256 tokenId);
    event SaleRecorded(address indexed collection, uint256 indexed tokenId, uint256 salePrice);
    // event TreasuryAddressUpdated(address indexed newTreasuryAddress); // REMOVED event
    // RoyaltyDistributorSet and RoyaltyFeeNumeratorSet events are emitted by the adapter's constructor
    // BaseURISet and SuffixURISet events are emitted by the parent MetadataURI contract
    
    // Role definition
    bytes32 public constant SERVICE_ACCOUNT_ROLE = keccak256("SERVICE_ACCOUNT_ROLE");
    
    // address public treasuryAddress; // Address to receive mint payments - REMOVED

    constructor(
        address royaltyDistributor_,
        uint96 royaltyFeeNumerator_, 
        address creator_
    ) 
    ERC721OpenZeppelin("Diamond Genesis Pass", "DiamondGenesisPass") 
    CentralizedRoyaltyAdapter(royaltyDistributor_, royaltyFeeNumerator_) 
    {
        _transferOwnership(msg.sender); // Set initial owner here

        centralizedDistributor = CentralizedRoyaltyDistributor(payable(royaltyDistributor_));
        // treasuryAddress = msg.sender; // Set initial treasury to owner (deployer) - REMOVED
        // emit TreasuryAddressUpdated(msg.sender); // REMOVED emit

        // Grant AccessControl roles to the initial owner (deployer)
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); 
        _grantRole(SERVICE_ACCOUNT_ROLE, msg.sender); 
        _setRoleAdmin(SERVICE_ACCOUNT_ROLE, DEFAULT_ADMIN_ROLE); // Owner (Admin) manages service role

        // Register collection with distributor
        // Note: Assumes distributor's registerCollection is onlyOwner
        // The deployer of this contract must ensure they are owner of the distributor or call register separately.
        try centralizedDistributor.registerCollection(
            address(this),
            royaltyFeeNumerator_, // Use the same numerator passed to adapter
            MINTER_SHARES,
            CREATOR_SHARES,
            creator_
        ) {}
        catch {
            revert("Failed to register collection with distributor");
        }
    }

    /**
     * @dev Modifier that checks if the caller is the owner() or has the SERVICE_ACCOUNT_ROLE.
     */
    modifier onlyOwnerOrServiceAccount() {
        if (msg.sender != owner() && !hasRole(SERVICE_ACCOUNT_ROLE, _msgSender())) {
             revert CallerIsNotAdminOrServiceAccount(); // Re-use error for simplicity
        }
        _;
    }

    /**
     * @notice Get the current total supply of minted tokens
     * @return The number of tokens minted
     */
    function totalSupply() public view returns (uint256) {
        return _mintedCount;
    }

    /**
     * @notice Check if an address has already claimed from the whitelist
     * @param account The address to check
     * @return Whether the address has claimed
     */
    function isWhitelistClaimed(address account) public view returns (bool) {
        return whitelistClaimed[account];
    }
    
    /**
     * @notice Get the current merkle root
     * @return The merkle root
     */
    function getMerkleRoot() public view returns (bytes32) {
        return merkleRoot;
    }

    // --- Interface Support --- 

    // Fix Linting: supportsInterface override needs to include AccessControl
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721C, CentralizedRoyaltyAdapter, AccessControl) returns (bool) {
        // Checks ERC721C, IERC2981 (via Adapter), ERC165 (via Adapter), IAccessControl
        return super.supportsInterface(interfaceId);
    }

    // --- Royalty Info (IERC2981) --- 
    // royaltyInfo is now inherited from CentralizedRoyaltyAdapter
    /*
    function royaltyInfo(
        uint256 tokenId,
        uint256 salePrice
    ) external view override returns (address receiver, uint256 royaltyAmount) {
        return (royaltyDistributor, (salePrice * royaltyFeeNumerator) / FEE_DENOMINATOR);
    }
    */

    // --- View functions mirroring CentralizedRoyaltyAdapter pattern --- 
    // These are now inherited from CentralizedRoyaltyAdapter
    /*
    function minterShares() public view returns (uint256) {
        // ... implementation removed ...
    }
    function creatorShares() public view returns (uint256) {
         // ... implementation removed ...
    }
    function creator() public view returns (address) {
        // ... implementation removed ...
    }
    function minterOf(uint256 tokenId) external view returns (address) {
        // ... implementation removed ...
    }
    function distributorRoyaltyFeeNumerator() public view returns (uint256) {
        // ... implementation removed ...
    }
    */

    // --- Minting Functions --- 

    /**
     * @notice Whitelist minting function with payment.
     * @dev Mints `quantity` tokens to the sender if they provide a valid Merkle proof and haven't claimed yet.
     * @param quantity The quantity to mint
     * @param merkleProof The merkle proof to verify the caller is on the whitelist
     */
    function whitelistMint(uint256 quantity, bytes32[] calldata merkleProof) external payable {
        if (merkleRoot == bytes32(0)) {
            revert MerkleRootNotSet();
        }
        if (quantity == 0) {
            revert("Quantity cannot be zero");
        }
        
        uint256 requiredPayment = PUBLIC_MINT_PRICE * quantity;
        if (msg.value < requiredPayment) {
            revert InsufficientPayment();
        }
        
        address sender = _msgSender();
        
        if (whitelistClaimed[sender]) {
            revert AddressAlreadyClaimed();
        }
        
        if (!MerkleProof.verify(merkleProof, merkleRoot, keccak256(abi.encodePacked(sender, quantity)))) {
            revert InvalidMerkleProof();
        }
        
        uint256 currentSupply = _mintedCount;
        if (currentSupply + quantity > MAX_SUPPLY) {
            revert MaxSupplyExceeded();
        }
        
        whitelistClaimed[sender] = true;
        
        uint256 firstTokenId = currentSupply + 1;
        for (uint256 i = 0; i < quantity; i++) {
            _mint(sender, firstTokenId + i); 
        }
        
        _mintedCount += quantity; // Optimized count update
        
        // Forward payment to the CentralizedRoyaltyDistributor for this collection
        centralizedDistributor.addCollectionRoyalties{value: msg.value}(address(this));
        
        emit WhitelistMinted(sender, quantity, firstTokenId);
    }

    /**
     * @notice Public mint function, only active when isPublicMintActive is true.
     * @dev Mints one token to the specified recipient `to`.
     * @param to The recipient of the token
     */
    function mint(address to) external payable {
        if (!isPublicMintActive) {
            revert PublicMintNotActive();
        }
        if (msg.value < PUBLIC_MINT_PRICE) {
            revert InsufficientPayment();
        }
        
        uint256 currentSupply = _mintedCount;
        if (currentSupply + 1 > MAX_SUPPLY) {
            revert MaxSupplyExceeded();
        }

        uint256 tokenId = currentSupply + 1;
        _mint(to, tokenId);
        _mintedCount++; // Optimized count update
        
        // Forward payment to the CentralizedRoyaltyDistributor for this collection
        centralizedDistributor.addCollectionRoyalties{value: msg.value}(address(this));

        emit PublicMinted(to, tokenId);
    }
    
    /**
     * @notice Safe version of the public mint function.
     * @dev Mints one token safely to the specified recipient `to`.
     * @param to The recipient of the token
     */
    function safeMint(address to) external payable {
        if (!isPublicMintActive) {
            revert PublicMintNotActive();
        }
        if (msg.value < PUBLIC_MINT_PRICE) {
            revert InsufficientPayment();
        }
        
        uint256 currentSupply = _mintedCount;
        if (currentSupply + 1 > MAX_SUPPLY) {
            revert MaxSupplyExceeded();
        }

        uint256 tokenId = currentSupply + 1;
        _safeMint(to, tokenId);
        _mintedCount++; // Optimized count update
        
        // Forward payment to the CentralizedRoyaltyDistributor for this collection
        centralizedDistributor.addCollectionRoyalties{value: msg.value}(address(this));

         emit PublicMinted(to, tokenId);
    }
    
    /**
     * @notice Mint function for the owner or service account to mint to a specific address.
     * @dev Only callable by owner or SERVICE_ACCOUNT_ROLE. Mints one token sequentially.
     * @param to The recipient of the token
     */
    function mintOwner(address to) external onlyOwnerOrServiceAccount { // Use new modifier
        uint256 currentSupply = _mintedCount;
        if (currentSupply + 1 > MAX_SUPPLY) {
            revert MaxSupplyExceeded();
        }

        uint256 tokenId = currentSupply + 1;
        _mint(to, tokenId);
        _mintedCount++; 

        emit PublicMinted(to, tokenId);
    }

    /**
     * @notice Safe mint function for the owner or service account to mint to a specific address.
     * @dev Only callable by owner or SERVICE_ACCOUNT_ROLE. Mints one token safely and sequentially.
     * @param to The recipient of the token
     */
    function safeMintOwner(address to) external onlyOwnerOrServiceAccount { // Use new modifier
        uint256 currentSupply = _mintedCount;
        if (currentSupply + 1 > MAX_SUPPLY) {
            revert MaxSupplyExceeded();
        }

        uint256 tokenId = currentSupply + 1;
        _safeMint(to, tokenId);
         _mintedCount++;

        emit PublicMinted(to, tokenId);
    }

    /**
     * @notice Burn a token.
     * @dev Only callable by contract owner (Uses Ownable modifier).
     * @param tokenId The ID of the token to burn.
     */
    function burn(uint256 tokenId) external onlyOwner { // Keep onlyOwner
        _burn(tokenId); 
    }

    /**
     * @notice Internal mint function override.
     * @dev Registers the minter with the centralized distributor before calling super._mint.
     */
    function _mint(address to, uint256 tokenId) internal virtual override {
        // Use the immutable distributor reference
        centralizedDistributor.setTokenMinter(address(this), tokenId, to);
        super._mint(to, tokenId);
    }

    /**
     * @notice Internal safe mint function override.
     * @dev Registers the minter with the centralized distributor before calling super._safeMint.
     */
    function _safeMint(address to, uint256 tokenId) internal virtual override {
        centralizedDistributor.setTokenMinter(address(this), tokenId, to);
        super._safeMint(to, tokenId);
    }
     function _safeMint(address to, uint256 tokenId, bytes memory data) internal virtual override {
        centralizedDistributor.setTokenMinter(address(this), tokenId, to);
        super._safeMint(to, tokenId, data);
    }
    
    // --- Sale Recording --- 

    /**
     * @notice Record a sale's royalty contribution in the centralized distributor.
     * @dev Only callable by the owner or SERVICE_ACCOUNT_ROLE.
     *      Caller must have appropriate permissions on the CentralizedRoyaltyDistributor contract.
     * @param tokenId The token ID that was sold
     * @param salePrice The sale price in ETH
     */
    function recordSale(uint256 tokenId, uint256 salePrice) external onlyOwnerOrServiceAccount { // Use new modifier
        // Use the immutable distributor reference
        // Note: The distributor's recordSaleRoyalty function performs its own role check 
        // (DEFAULT_ADMIN_ROLE or SERVICE_ACCOUNT_ROLE on the distributor).
        // The caller of this function (owner or service account) must have one of those roles on the distributor.
        centralizedDistributor.recordSaleRoyalty(address(this), tokenId, salePrice);
        emit SaleRecorded(address(this), tokenId, salePrice); 
    }

    // --- Metadata URI Handling (Inherited from MetadataURI) --- 

    /**
     * @notice Get the base URI for token metadata
     * @dev Uses `baseTokenURI` state variable from `MetadataURI` contract.
     */
    function baseURI() public view virtual returns (string memory) {
        return baseTokenURI; 
    }

    /**
     * @notice Get the token URI for a specific token
     * @param tokenId The token ID to get the URI for
     * @return The token URI
     */
    function tokenURI(uint256 tokenId) public view virtual override(ERC721) returns (string memory) {
        if (!_exists(tokenId)) {
            revert("ERC721Metadata: URI query for nonexistent token");
        }
        
        string memory currentBaseURI = baseURI();
        string memory currentSuffixURI = suffixURI; // Access public state var from MetadataURI
        
        return bytes(currentBaseURI).length > 0 
            ? string(abi.encodePacked(currentBaseURI, tokenId.toString(), currentSuffixURI))
            : "";
    }

    // NOTE: setBaseURI and setSuffixURI are inherited directly from MetadataURI.sol
    // They use _requireCallerIsContractOwner internally.

    // --- ERC721C Hook --- 

    /**
     * @dev Hook that is called before any token transfer.
     *      Needed for ERC721C compatibility.
     */
    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 quantity) internal virtual override(ERC721C) {
        super._beforeTokenTransfer(from, to, firstTokenId, quantity);
    }
    
    // --- OwnablePermissions Implementation --- 

    /**
     * @notice Implementation of the OwnablePermissions abstract function `_requireCallerIsContractOwner`.
     * @dev This function is called by functions in `MetadataURI` (like setBaseURI) that require the caller 
     *      to be the contract owner. It uses the `owner()` function from the standard OpenZeppelin `Ownable` contract.
     */
    function _requireCallerIsContractOwner() internal view virtual override {
        // Keep Ownable check for MetadataURI compatibility
        if (msg.sender != owner()) { 
            revert CallerIsNotOwner();
        }
    }
}