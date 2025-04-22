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
import "@openzeppelin/contracts/security/ReentrancyGuard.sol"; // Add ReentrancyGuard

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
    AccessControl, // Add AccessControl for role management
    ReentrancyGuard // Add ReentrancyGuard for secure bid/sale operations
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

    // ============== MINTER STATUS TRADING SYSTEM ================
    // Struct to represent a bid for minter status
    struct Bid {
        address bidder;
        uint256 amount;
        uint256 timestamp;
    }

    // Tracks bids for specific tokenIds
    mapping(uint256 => Bid[]) private _tokenBids;
    
    // Tracks collection-wide bids
    Bid[] private _collectionBids;
    
    // Token minter overrides - if set, this takes precedence over the one in distributor
    mapping(uint256 => address) private _tokenMinterOverrides;
    
    // ================= END MINTER STATUS SYSTEM =================

    // ============== TOKEN TRADING SYSTEM ================
    // Struct to represent a bid for token purchase
    struct TokenBid {
        address bidder;
        uint256 amount;
        uint256 timestamp;
    }

    // Tracks token purchase bids for specific tokenIds
    mapping(uint256 => TokenBid[]) private _tokenPurchaseBids;
    
    // Tracks collection-wide token purchase bids
    TokenBid[] private _collectionTokenBids;
    // ================= END TOKEN TRADING SYSTEM =================

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
    error NotTokenMinter(); // Can't sell minter status if not current minter
    error NotTokenOwner(); // Can't sell token if not owner
    error InsufficientBidAmount(); // Bid amount too low
    error BidNotFound(); // Bid not found for withdrawal
    error NoBidsAvailable(); // No bids to accept
    error TokenNotMinted(); // Token doesn't exist
    error TransferFailed(); // ETH transfer failed
    
    /*───────────────────*/
    /*     ✨ Events      */
    /*───────────────────*/
    event PublicMintStatusUpdated(bool isActive);
    event MerkleRootSet(bytes32 indexed merkleRoot);
    event WhitelistMinted(address indexed to, uint256 quantity, uint256 startTokenId);
    event PublicMinted(address indexed to, uint256 indexed tokenId);
    event SaleRecorded(address indexed collection, uint256 indexed tokenId, uint256 salePrice);
    event CreatorAddressUpdated(address indexed oldCreator, address indexed newCreator); // New event for creator updates
    event RoyaltyRecipientUpdated(address indexed oldRecipient, address indexed newRecipient); // Updated event name for clarity
    event BidPlaced(address indexed bidder, uint256 indexed tokenId, uint256 amount, bool isCollectionBid);
    event BidWithdrawn(address indexed bidder, uint256 indexed tokenId, uint256 amount, bool isCollectionBid);
    event BidAccepted(address indexed seller, address indexed buyer, uint256 indexed tokenId, uint256 amount);
    event MinterStatusAssigned(uint256 indexed tokenId, address indexed newMinter, address indexed oldMinter);
    event MinterStatusRevoked(uint256 indexed tokenId, address indexed oldMinter);
    event CollectionRegistered(address indexed collection, uint96 royaltyFeeNumerator, address creator);
    event RegistrationFailed(address indexed collection, string reason);
    // New events for token bidding
    event TokenBidPlaced(address indexed bidder, uint256 indexed tokenId, uint256 amount, bool isCollectionBid);
    event TokenBidWithdrawn(address indexed bidder, uint256 indexed tokenId, uint256 amount, bool isCollectionBid);
    event TokenBidAccepted(address indexed seller, address indexed buyer, uint256 indexed tokenId, uint256 amount);
    event RoyaltySent(uint256 indexed tokenId, uint256 indexed royaltyAmount);

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

    /**
     * @notice Modifier to ensure the caller is the current minter of a token
     * @param tokenId The token ID
     */
    modifier onlyTokenMinter(uint256 tokenId) {
        if (!_exists(tokenId)) {
            revert TokenNotMinted();
        }
        
        // First check local override
        address minterOverride = _tokenMinterOverrides[tokenId];
        if (minterOverride != address(0)) {
            if (msg.sender != minterOverride) {
                revert NotTokenMinter();
            }
        } else {
            // If no override, check the distributor
            address minter = centralizedDistributor.getMinter(address(this), tokenId);
            if (msg.sender != minter) {
                revert NotTokenMinter();
            }
        }
        _;
    }

    /**
     * @notice Modifier to ensure the caller is the owner of a token
     * @param tokenId The token ID
     */
    modifier onlyTokenOwner(uint256 tokenId) {
        if (!_exists(tokenId)) {
            revert TokenNotMinted();
        }
        
        if (msg.sender != ownerOf(tokenId)) {
            revert NotTokenOwner();
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
        // Forward payment directly to the creator/royalty recipient
        address creatorAddress = creator();
        (bool success, ) = creatorAddress.call{value: msg.value}("");
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
        // Forward payment directly to the creator/royalty recipient
        address creatorAddress = creator();
        (bool success, ) = creatorAddress.call{value: msg.value}("");
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
        // Forward payment directly to the creator/royalty recipient
        address creatorAddress = creator();
        (bool success, ) = creatorAddress.call{value: msg.value}("");
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
        // Also update the token holder (initial holder is the same as minter)
        centralizedDistributor.updateTokenHolder(address(this), tokenId, to);
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

    /**
     * @notice Legacy alias for setRoyaltyRecipient for backward compatibility
     * @dev Only callable by the contract owner
     * @param newCreator The new address to receive creator royalties
     */
    function updateCreatorAddress(address newCreator) external onlyOwner {
        // Get current creator from the distributor
        (,,, address oldCreator) = centralizedDistributor.getCollectionConfig(address(this));
        
        // Update the creator in the royalty distributor
        centralizedDistributor.updateCreatorAddress(address(this), newCreator);
        
        emit CreatorAddressUpdated(oldCreator, newCreator);
    }
    
    /**
     * @notice Update the royalty recipient address that receives creator royalties
     * @dev Only callable by the contract owner. This changes who receives the creator's 
     *      share (80%) of royalties, not who controls the contract.
     * @param newRecipient The new address to receive creator royalties
     */
    function setRoyaltyRecipient(address newRecipient) external onlyOwner {
        // Get current creator from the distributor
        (,,, address oldCreator) = centralizedDistributor.getCollectionConfig(address(this));
        
        // Update the creator in the royalty distributor
        centralizedDistributor.updateCreatorAddress(address(this), newRecipient);
        
        emit RoyaltyRecipientUpdated(oldCreator, newRecipient);
    }

    /*───────────────────*/
    /*  🌀 Transfer Hook  */
    /*───────────────────*/
    /// @dev keep royalty analytics' token holder in sync after every transfer
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override {
        super._afterTokenTransfer(from, to, firstTokenId, batchSize);

        for (uint256 i; i < batchSize; ++i) {
            centralizedDistributor.updateTokenHolder(
                address(this),
                firstTokenId + i,
                to
            );
        }
    }

    // ================== MINTER STATUS TRADING FUNCTIONS ==================

    /**
     * @notice Get the current minter for a token, respecting any overrides 
     * @param tokenId The token ID
     * @return The address of the current minter
     */
    function getMinterOf(uint256 tokenId) public view returns (address) {
        if (!_exists(tokenId)) {
            revert TokenNotMinted();
        }
        
        // First check local override
        address minterOverride = _tokenMinterOverrides[tokenId];
        if (minterOverride != address(0)) {
            return minterOverride;
        }
        
        // If no override, get from distributor
        return centralizedDistributor.getMinter(address(this), tokenId);
    }
    
    /**
     * @notice Allow contract owner to assign minter status for a token
     * @dev Only callable by contract owner
     * @param tokenId The token ID
     * @param newMinter The new minter address
     */
    function setMinterStatus(uint256 tokenId, address newMinter) external onlyOwner {
        if (!_exists(tokenId)) {
            revert TokenNotMinted();
        }
        
        address oldMinter = getMinterOf(tokenId);
        
        // Set override in local mapping
        _tokenMinterOverrides[tokenId] = newMinter;
        
        emit MinterStatusAssigned(tokenId, newMinter, oldMinter);
    }
    
    /**
     * @notice Allow contract owner to revoke minter status for a token
     * @dev Only callable by contract owner
     * @param tokenId The token ID
     */
    function revokeMinterStatus(uint256 tokenId) external onlyOwner {
        if (!_exists(tokenId)) {
            revert TokenNotMinted();
        }
        
        address oldMinter = getMinterOf(tokenId);
        
        // Delete minter status override
        delete _tokenMinterOverrides[tokenId];
        
        emit MinterStatusRevoked(tokenId, oldMinter);
    }
    
    /**
     * @notice Place a bid for minter status of a specific token or collection-wide
     * @param tokenId The token ID to bid on (0 for collection-wide)
     * @param isCollectionBid Whether this is a collection-wide bid
     */
    function placeBid(uint256 tokenId, bool isCollectionBid) external payable nonReentrant {
        // Non-zero bid requirement
        if (msg.value == 0) {
            revert InsufficientBidAmount();
        }
        
        // For token-specific bids, validate token exists
        if (!isCollectionBid) {
            if (tokenId == 0 || !_exists(tokenId)) {
                revert TokenNotMinted();
            }
        }
        
        // Get the bids array to update
        Bid[] storage bids = isCollectionBid ? _collectionBids : _tokenBids[tokenId];
        
        // Check if the bidder already has a bid
        bool bidExists = false;
        for (uint i = 0; i < bids.length; i++) {
            if (bids[i].bidder == msg.sender) {
                // Increase existing bid
                bids[i].amount += msg.value;
                bids[i].timestamp = block.timestamp;
                bidExists = true;
                break;
            }
        }
        
        // Create new bid if none exists
        if (!bidExists) {
            bids.push(Bid({
                bidder: msg.sender,
                amount: msg.value,
                timestamp: block.timestamp
            }));
        }
        
        emit BidPlaced(msg.sender, isCollectionBid ? 0 : tokenId, msg.value, isCollectionBid);
    }
    
    /**
     * @notice View all bids for a specific token
     * @param tokenId The token ID
     * @return Array of Bid structs
     */
    function viewBids(uint256 tokenId) external view returns (Bid[] memory) {
        return _tokenBids[tokenId];
    }
    
    /**
     * @notice View all collection-wide bids
     * @return Array of Bid structs
     */
    function viewCollectionBids() external view returns (Bid[] memory) {
        return _collectionBids;
    }
    
    /**
     * @notice Find the highest bid for a specific token or collection-wide
     * @param tokenId The token ID (0 for collection-wide)
     * @param isCollectionBid Whether to check collection-wide bids
     * @return bidder The address of the highest bidder
     * @return amount The highest bid amount
     * @return index The index of the highest bid in the array
     */
    function getHighestBid(uint256 tokenId, bool isCollectionBid) public view returns (
        address bidder,
        uint256 amount,
        uint256 index
    ) {
        Bid[] storage bids = isCollectionBid ? _collectionBids : _tokenBids[tokenId];
        
        if (bids.length == 0) {
            return (address(0), 0, 0);
        }
        
        uint256 highestAmount = 0;
        uint256 highestIndex = 0;
        
        for (uint i = 0; i < bids.length; i++) {
            if (bids[i].amount > highestAmount) {
                highestAmount = bids[i].amount;
                highestIndex = i;
            }
        }
        
        return (bids[highestIndex].bidder, highestAmount, highestIndex);
    }
    
    /**
     * @notice Withdraw a bid if outbid or no longer interested
     * @param tokenId The token ID (0 for collection-wide)
     * @param isCollectionBid Whether this was a collection-wide bid
     */
    function withdrawBid(uint256 tokenId, bool isCollectionBid) external nonReentrant {
        // Get the appropriate bids array
        Bid[] storage bids = isCollectionBid ? _collectionBids : _tokenBids[tokenId];
        
        // Find the bidder's bid
        uint256 bidIndex = type(uint256).max;
        uint256 bidAmount = 0;
        
        for (uint i = 0; i < bids.length; i++) {
            if (bids[i].bidder == msg.sender) {
                bidIndex = i;
                bidAmount = bids[i].amount;
                break;
            }
        }
        
        if (bidIndex == type(uint256).max) {
            revert BidNotFound();
        }
        
        // Remove bid by swapping with the last element and popping
        if (bidIndex != bids.length - 1) {
            bids[bidIndex] = bids[bids.length - 1];
        }
        bids.pop();
        
        // Return funds to bidder
        (bool success, ) = msg.sender.call{value: bidAmount}("");
        if (!success) {
            revert TransferFailed();
        }
        
        emit BidWithdrawn(msg.sender, isCollectionBid ? 0 : tokenId, bidAmount, isCollectionBid);
    }
    
    /**
     * @notice Accept the highest bid for a token's minter status
     * @dev Only callable by the current minter of the token
     * @param tokenId The token ID
     */
    function acceptHighestBid(uint256 tokenId) external nonReentrant onlyTokenMinter(tokenId) {
        // Check for token-specific bids first
        (address tokenBidder, uint256 tokenBidAmount, uint256 tokenBidIndex) = getHighestBid(tokenId, false);
        
        // Then check collection-wide bids
        (address collectionBidder, uint256 collectionBidAmount, uint256 collectionBidIndex) = getHighestBid(0, true);
        
        // Determine the highest bid between token-specific and collection-wide
        bool useTokenBid = tokenBidAmount >= collectionBidAmount;
        address highestBidder = useTokenBid ? tokenBidder : collectionBidder;
        uint256 highestAmount = useTokenBid ? tokenBidAmount : collectionBidAmount;
        
        // Ensure there's a valid bid
        if (highestBidder == address(0) || highestAmount == 0) {
            revert NoBidsAvailable();
        }
        
        // Remove the accepted bid and clear all other bids for this token
        if (useTokenBid) {
            // Clear all token bids (not just the highest one)
            delete _tokenBids[tokenId];
        } else {
            // Remove collection bid
            if (collectionBidIndex != _collectionBids.length - 1) {
                _collectionBids[collectionBidIndex] = _collectionBids[_collectionBids.length - 1];
            }
            _collectionBids.pop();
            
            // Also clear token-specific bids
            delete _tokenBids[tokenId];
        }
        
        // Update minter status to the new minter
        address oldMinter = msg.sender;
        _tokenMinterOverrides[tokenId] = highestBidder;
        
        // 100% of the payment goes to the contract owner (not to the seller)
        (bool success, ) = owner().call{value: highestAmount}("");
        if (!success) {
            revert TransferFailed();
        }
        
        emit BidAccepted(oldMinter, highestBidder, tokenId, highestAmount);
        emit MinterStatusAssigned(tokenId, highestBidder, oldMinter);
    }

    // ================== TOKEN TRADING FUNCTIONS ==================

    /**
     * @notice Place a bid to purchase a specific token or any token in the collection
     * @param tokenId The token ID to bid on (0 for collection-wide)
     * @param isCollectionBid Whether this is a collection-wide bid
     */
    function placeTokenBid(uint256 tokenId, bool isCollectionBid) external payable nonReentrant {
        // Non-zero bid requirement
        if (msg.value == 0) {
            revert InsufficientBidAmount();
        }
        
        // For token-specific bids, validate token exists
        if (!isCollectionBid) {
            if (tokenId == 0 || !_exists(tokenId)) {
                revert TokenNotMinted();
            }
        }
        
        // Get the bids array to update
        TokenBid[] storage bids = isCollectionBid ? _collectionTokenBids : _tokenPurchaseBids[tokenId];
        
        // Check if the bidder already has a bid
        bool bidExists = false;
        for (uint i = 0; i < bids.length; i++) {
            if (bids[i].bidder == msg.sender) {
                // Increase existing bid
                bids[i].amount += msg.value;
                bids[i].timestamp = block.timestamp;
                bidExists = true;
                break;
            }
        }
        
        // Create new bid if none exists
        if (!bidExists) {
            bids.push(TokenBid({
                bidder: msg.sender,
                amount: msg.value,
                timestamp: block.timestamp
            }));
        }
        
        emit TokenBidPlaced(msg.sender, isCollectionBid ? 0 : tokenId, msg.value, isCollectionBid);
    }
    
    /**
     * @notice View all token purchase bids for a specific token
     * @param tokenId The token ID
     * @return Array of TokenBid structs
     */
    function viewTokenBids(uint256 tokenId) external view returns (TokenBid[] memory) {
        return _tokenPurchaseBids[tokenId];
    }
    
    /**
     * @notice View all collection-wide token purchase bids
     * @return Array of TokenBid structs
     */
    function viewCollectionTokenBids() external view returns (TokenBid[] memory) {
        return _collectionTokenBids;
    }
    
    /**
     * @notice Find the highest token purchase bid for a specific token or collection-wide
     * @param tokenId The token ID (0 for collection-wide)
     * @param isCollectionBid Whether to check collection-wide bids
     * @return bidder The address of the highest bidder
     * @return amount The highest bid amount
     * @return index The index of the highest bid in the array
     */
    function getHighestTokenBid(uint256 tokenId, bool isCollectionBid) public view returns (
        address bidder,
        uint256 amount,
        uint256 index
    ) {
        TokenBid[] storage bids = isCollectionBid ? _collectionTokenBids : _tokenPurchaseBids[tokenId];
        
        if (bids.length == 0) {
            return (address(0), 0, 0);
        }
        
        uint256 highestAmount = 0;
        uint256 highestIndex = 0;
        
        for (uint i = 0; i < bids.length; i++) {
            if (bids[i].amount > highestAmount) {
                highestAmount = bids[i].amount;
                highestIndex = i;
            }
        }
        
        return (bids[highestIndex].bidder, highestAmount, highestIndex);
    }
    
    /**
     * @notice Withdraw a token purchase bid if outbid or no longer interested
     * @param tokenId The token ID (0 for collection-wide)
     * @param isCollectionBid Whether this was a collection-wide bid
     */
    function withdrawTokenBid(uint256 tokenId, bool isCollectionBid) external nonReentrant {
        // Get the appropriate bids array
        TokenBid[] storage bids = isCollectionBid ? _collectionTokenBids : _tokenPurchaseBids[tokenId];
        
        // Find the bidder's bid
        uint256 bidIndex = type(uint256).max;
        uint256 bidAmount = 0;
        
        for (uint i = 0; i < bids.length; i++) {
            if (bids[i].bidder == msg.sender) {
                bidIndex = i;
                bidAmount = bids[i].amount;
                break;
            }
        }
        
        if (bidIndex == type(uint256).max) {
            revert BidNotFound();
        }
        
        // Remove bid by swapping with the last element and popping
        if (bidIndex != bids.length - 1) {
            bids[bidIndex] = bids[bids.length - 1];
        }
        bids.pop();
        
        // Return funds to bidder
        (bool success, ) = msg.sender.call{value: bidAmount}("");
        if (!success) {
            revert TransferFailed();
        }
        
        emit TokenBidWithdrawn(msg.sender, isCollectionBid ? 0 : tokenId, bidAmount, isCollectionBid);
    }
    
    /**
     * @notice Accept the highest token purchase bid for a token
     * @dev Only callable by the current owner of the token
     * @param tokenId The token ID
     */
    function acceptHighestTokenBid(uint256 tokenId) external nonReentrant onlyTokenOwner(tokenId) {
        // Check for token-specific bids first
        (address tokenBidder, uint256 tokenBidAmount, uint256 tokenBidIndex) = getHighestTokenBid(tokenId, false);
        
        // Then check collection-wide bids
        (address collectionBidder, uint256 collectionBidAmount, uint256 collectionBidIndex) = getHighestTokenBid(0, true);
        
        // Determine the highest bid between token-specific and collection-wide
        bool useTokenBid = tokenBidAmount >= collectionBidAmount;
        address highestBidder = useTokenBid ? tokenBidder : collectionBidder;
        uint256 highestAmount = useTokenBid ? tokenBidAmount : collectionBidAmount;
        
        // Ensure there's a valid bid
        if (highestBidder == address(0) || highestAmount == 0) {
            revert NoBidsAvailable();
        }

        // Store seller address before any state changes
        address seller = msg.sender;
        
        // Calculate royalty amount based on the royalty fee numerator
        uint256 salePrice = highestAmount;
        uint256 royaltyAmount = (salePrice * royaltyFeeNumerator) / FEE_DENOMINATOR;
        uint256 sellerProceeds = salePrice - royaltyAmount;
        
        // Save bid info - remove from state before making external calls
        if (useTokenBid) {
            // Remove token bid by copying the last element to the index position and popping the last element
            if (_tokenPurchaseBids[tokenId].length > 0) {
                if (tokenBidIndex < _tokenPurchaseBids[tokenId].length - 1) {
                    _tokenPurchaseBids[tokenId][tokenBidIndex] = _tokenPurchaseBids[tokenId][_tokenPurchaseBids[tokenId].length - 1];
                }
                _tokenPurchaseBids[tokenId].pop();
            }
        } else {
            // Remove collection bid
            if (_collectionTokenBids.length > 0) {
                if (collectionBidIndex < _collectionTokenBids.length - 1) {
                    _collectionTokenBids[collectionBidIndex] = _collectionTokenBids[_collectionTokenBids.length - 1];
                }
                _collectionTokenBids.pop();
            }
        }
        
        // First approve and transfer the token to the buyer
        // Make sure the token can be transferred using transferFrom instead of internal _transfer
        // to ensure compatibility with ERC721C
        address tokenOwner = ownerOf(tokenId);
        
        // The seller is the msg.sender and has already been verified by the onlyTokenOwner modifier
        
        // Approve this contract to handle the transfer
        _approve(address(this), tokenId);
        
        // Use safeTransferFrom to ensure safer transfer
        safeTransferFrom(seller, highestBidder, tokenId);
        
        // Now handle payments
        // 1. Send royalty to the distributor
        (bool royaltySuccess, ) = payable(royaltyDistributor).call{value: royaltyAmount}("");
        require(royaltySuccess, "Royalty transfer failed");
        
        // 2. Send proceeds to seller
        (bool sellerSuccess, ) = payable(seller).call{value: sellerProceeds}("");
        require(sellerSuccess, "Seller payment failed");
        
        // 3. Process remaining bids for this token
        _clearAllTokenBids(tokenId);
        
        // Emit events
        emit SaleRecorded(address(this), tokenId, salePrice);
        emit TokenBidAccepted(seller, highestBidder, tokenId, highestAmount);
        emit RoyaltySent(tokenId, royaltyAmount);
    }
    
    /**
     * @dev Helper function to clear all bids for a token
     * @param tokenId The token ID
     */
    function _clearAllTokenBids(uint256 tokenId) internal {
        TokenBid[] storage bids = _tokenPurchaseBids[tokenId];
        uint256 bidCount = bids.length;
        
        if (bidCount == 0) {
            return; // No bids to clear
        }
        
        // Create a temporary array of addresses and amounts to refund
        // This prevents issues with modifying the array while iterating
        address[] memory refundAddresses = new address[](bidCount);
        uint256[] memory refundAmounts = new uint256[](bidCount);
        uint256 validRefunds = 0;
        
        // Collect all valid bids to refund
        for (uint i = 0; i < bidCount; i++) {
            address bidder = bids[i].bidder;
            uint256 amount = bids[i].amount;
            
            if (bidder != address(0) && amount > 0) {
                refundAddresses[validRefunds] = bidder;
                refundAmounts[validRefunds] = amount;
                validRefunds++;
            }
        }
        
        // Clear the bids array first to prevent reentrancy
        delete _tokenPurchaseBids[tokenId];
        
        // Process refunds after clearing state
        for (uint i = 0; i < validRefunds; i++) {
            address bidder = refundAddresses[i];
            uint256 amount = refundAmounts[i];
            
            // Transfer funds back to the bidder
            (bool success, ) = payable(bidder).call{value: amount}("");
            
            // Emit event for successful refunds
            if (success) {
                emit TokenBidWithdrawn(bidder, tokenId, amount, false);
            }
            // If refund fails, we still continue with other refunds
            // This is an acceptable risk as we've already deleted the bids from state
        }
    }
}