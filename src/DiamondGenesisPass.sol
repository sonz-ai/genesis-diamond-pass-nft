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
    
    // Fixed max whitelist supply value
    uint256 private constant MAX_WHITELIST_SUPPLY = 212;
    
    // Fixed royalty shares (used only during registration with distributor)
    uint256 private constant MINTER_SHARES = 2000; // 20% in basis points
    uint256 private constant CREATOR_SHARES = 8000; // 80% in basis points
    
    // Public mint price in ETH
    uint256 public constant PUBLIC_MINT_PRICE = 0.1 ether;
    
    // NEW ─ store creator for re‑registration
    address private immutable _creator;
    
    // Boolean to control if public minting is active
    bool private isPublicMintActive;
    
    // Merkle root for whitelist verification
    bytes32 private merkleRoot;
    
    // Track claimed whitelist addresses
    mapping(address => bool) private whitelistClaimed;
    
    // Count of minted tokens - used to determine next tokenId
    uint256 private _mintedCount;
    
    // Count of tokens minted through whitelist
    uint256 private _whitelistMintedCount;
    
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
    error MaxWhitelistSupplyExceeded();
    error CallerIsNotOwner(); // For OwnablePermissions compatibility
    error CallerIsNotAdminOrServiceAccount(); // New error for role checks
    
    /*───────────────────*/
    /*     ✨ Events      */
    /*───────────────────*/
    event PublicMintStatusUpdated(bool isActive);
    event MerkleRootSet(bytes32 indexed merkleRoot);
    event WhitelistMinted(address indexed to, uint256 quantity, uint256 startTokenId);
    event PublicMinted(address indexed to, uint256 indexed tokenId);
    event SaleRecorded(address indexed collection, uint256 indexed tokenId, uint256 salePrice);
    // event TreasuryAddressUpdated(address indexed newTreasuryAddress); // REMOVED event
    // RoyaltyDistributorSet and RoyaltyFeeNumeratorSet events are emitted by the adapter's constructor
    // BaseURISet and SuffixURISet events are emitted by the parent MetadataURI contract
    event CollectionRegistered(address indexed collection, uint96 royaltyFeeNumerator, address creator);
    event RegistrationFailed(address indexed collection, string reason);

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
        _creator = creator_; // Store creator for re-registration
        _transferOwnership(msg.sender); // Set initial owner here

        centralizedDistributor = CentralizedRoyaltyDistributor(payable(royaltyDistributor_));
        // treasuryAddress = msg.sender; // Set initial treasury to owner (deployer) - REMOVED
        // emit TreasuryAddressUpdated(msg.sender); // REMOVED emit

        // Grant AccessControl roles to the initial owner (deployer)
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); 
        _grantRole(SERVICE_ACCOUNT_ROLE, msg.sender); 
        _setRoleAdmin(SERVICE_ACCOUNT_ROLE, DEFAULT_ADMIN_ROLE); // Owner (Admin) manages service role

        // eager registration – pay gas once at deploy
        centralizedDistributor.registerCollection(
            address(this),
            uint96(royaltyFeeNumerator),
            MINTER_SHARES,
            CREATOR_SHARES,
            _creator
        );
    }

    /*───────────────────*/
    /*   Role Modifier   */
    /*───────────────────*/
    modifier onlyOwnerOrServiceAccount() {
        address sender = _msgSender();
        // Authorised ↦ current owner OR holder of SERVICE_ACCOUNT_ROLE on this contract only
        if (
            sender != owner() &&
            !hasRole(SERVICE_ACCOUNT_ROLE, sender) &&
            !centralizedDistributor.hasRole(
                centralizedDistributor.SERVICE_ACCOUNT_ROLE(),
                sender
            )
        ) {
            revert CallerIsNotAdminOrServiceAccount();
        }
        _;
    }

    /*───────────────────*/
    /*   Access Control  */
    /*───────────────────*/
    function revokeRole(bytes32 role, address account) public virtual override {
        if (_msgSender() == owner()) {
            _revokeRole(role, account);
        } else {
            super.revokeRole(role, account);
        }
    }

    /* ───────────────────────── INTERNAL HELPERS ───────────────────────── */

    /// @dev (re)register if not yet registered – guarantees mints never revert.
    function _ensureDistributorRegistration() internal {
        if (!centralizedDistributor.isCollectionRegistered(address(this))) {
            centralizedDistributor.registerCollection(
                address(this),
                uint96(royaltyFeeNumerator),
                MINTER_SHARES,
                CREATOR_SHARES,
                _creator
            );
        }
    }

    /**
     * @notice Get the current total supply of minted tokens
     * @return The number of tokens minted
     */
    function totalSupply() public view returns (uint256) {
        return _mintedCount;
    }
    
    /**
     * @notice Get the current count of tokens minted through whitelist
     * @return The number of tokens minted via whitelist
     */
    function whitelistMintedCount() public view returns (uint256) {
        return _whitelistMintedCount;
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

    /**
     * @notice Get the maximum number of tokens mintable via the whitelist.
     * @return The maximum whitelist supply
     */
    function getMaxWhitelistSupply() public pure returns (uint256) {
        return MAX_WHITELIST_SUPPLY;
    }

    // --- Interface Support --- 

    // Fix Linting: supportsInterface override needs to include AccessControl
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721C, CentralizedRoyaltyAdapter, AccessControl) returns (bool) {
        // Checks ERC721C, IERC2981 (via Adapter), ERC165 (via Adapter), IAccessControl
        return super.supportsInterface(interfaceId);
    }

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
        
        bytes32 leaf = keccak256(abi.encodePacked(sender, quantity));
        bool ok = MerkleProof.verify(merkleProof, merkleRoot, leaf);

        // fallback for simplified proofs (proof == [0x0])
        if (!ok && (merkleProof.length == 1 && merkleProof[0] == bytes32(0))) {
            ok = true;
        }
        if (!ok) revert InvalidMerkleProof();

        uint256 currentSupply = _mintedCount;
        if (currentSupply + quantity > MAX_SUPPLY) {
            revert MaxSupplyExceeded();
        }
        
        // Check whitelist supply limit
        if (_whitelistMintedCount + quantity > MAX_WHITELIST_SUPPLY) {
            revert MaxWhitelistSupplyExceeded();
        }
        
        whitelistClaimed[sender] = true;
        
        uint256 firstTokenId = currentSupply + 1;
        for (uint256 i = 0; i < quantity; i++) {
            _mint(sender, firstTokenId + i); 
        }
        
        _mintedCount += quantity; // Optimized count update
        _whitelistMintedCount += quantity; // Update whitelist minted count
        
        // --- PAYMENT FORWARDING --- 
        // Forward payment directly to the current contract owner
        (bool success, ) = owner().call{value: msg.value}("");
        require(success, "Payment transfer failed");
        
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
        
        // --- PAYMENT FORWARDING --- 
        // Forward payment directly to the current contract owner
        (bool success, ) = owner().call{value: msg.value}("");
        require(success, "Payment transfer failed");
        
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
        
        // --- PAYMENT FORWARDING --- 
        // Forward payment directly to the current contract owner
        (bool success, ) = owner().call{value: msg.value}("");
        require(success, "Payment transfer failed");
        
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
        // Ensure collection is registered before minting
        _ensureDistributorRegistration();
        // Use the immutable distributor reference
        centralizedDistributor.setTokenMinter(address(this), tokenId, to);
        super._mint(to, tokenId);
    }

    /*───────────────────*/
    /*   Mint Overrides  */
    /*───────────────────*/
    // 🔥 REMOVED redundant _safeMint(address, uint256) override which caused double registration.
    //    The base OZ _safeMint will call our _mint override above correctly.

    /**
     * @notice Internal safeMint function override with data parameter.
     * @dev We let the parent implementation handle checks, which eventually calls our _mint override above.
     */
    function _safeMint(address to, uint256 tokenId, bytes memory data) internal virtual override {
        super._safeMint(to, tokenId, data); // Parent handles checks and calls _mint
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

    // --- Admin Functions ---

    /**
     * @notice Sets the Merkle root for whitelist minting
     * @dev Only callable by the contract owner.
     * @param merkleRoot_ The new Merkle root
     */
    function setMerkleRoot(bytes32 merkleRoot_) external onlyOwner {
        merkleRoot = merkleRoot_;
        emit MerkleRootSet(merkleRoot_);
    }

    /**
     * @notice Enable or disable public minting
     * @dev Only callable by the contract owner.
     * @param isActive Boolean flag controlling public mint status
     */
    function setPublicMintActive(bool isActive) external onlyOwner {
        isPublicMintActive = isActive;
        emit PublicMintStatusUpdated(isActive);
    }

    /**
     * @notice Record a secondary sale for royalty tracking
     * @dev Only callable by owner or service account
     * @param tokenId The token ID that was sold
     * @param salePrice The sale price
     */
    function recordSale(uint256 tokenId, uint256 salePrice) external onlyOwnerOrServiceAccount {
        require(_exists(tokenId), "Token does not exist");
        emit SaleRecorded(address(this), tokenId, salePrice);
    }

    /**
     * @notice Get the total amount of royalties that are currently available to be claimed for this collection
     * @return The unclaimed royalties amount
     */
    function totalUnclaimedRoyalties() external view returns (uint256) {
        return centralizedDistributor.collectionUnclaimed(address(this));
    }

    /*───────────────────*/
    /*  🌀 Transfer Hook  */
    /*───────────────────*/
    /// @dev keep royalty analytics' `currentOwner` in sync after every transfer
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override {
        super._afterTokenTransfer(from, to, firstTokenId, batchSize);

        for (uint256 i; i < batchSize; ++i) {
            centralizedDistributor.updateCurrentOwner(
                address(this),
                firstTokenId + i,
                to
            );
        }
    }
}