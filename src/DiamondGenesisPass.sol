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
    error SelfBiddingNotAllowed(); // Cannot bid on and accept your own bid
    
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
    ERC721OpenZeppelin("Sonzai Diamond Genesis Pass", "SonzaiGenesis") 
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
            if (_msgSender() != minterOverride) {
                revert NotTokenMinter();
            }
        } else {
            // If no override, check the distributor
            address minter = centralizedDistributor.getMinter(address(this), tokenId);
            if (_msgSender() != minter) {
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
        
        if (_msgSender() != ownerOf(tokenId)) {
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
            uint256 tokenId = firstTokenId + i;
            _mint(sender, tokenId);
            
            // Register the minter with the distributor
            _ensureDistributorRegistration();
            centralizedDistributor.setTokenMinter(address(this), tokenId, sender);
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
        if (_msgSender() != owner()) { 
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
     * @return unclaimedAmount The unclaimed royalties amount
     */
    function totalUnclaimedRoyalties() external view override returns (uint256 unclaimedAmount) {
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
     * @notice Accept the highest bid for minter status
     * @dev Transfers minter status to the highest bidder, and distributes ETH
     * @param tokenId The token ID
     */
    function acceptHighestBid(uint256 tokenId) external nonReentrant onlyTokenMinter(tokenId) {
        // Get the highest bid (token-specific and collection-wide)
        (address tokenBidder, uint256 tokenBidAmount, uint256 tokenBidIndex) = getHighestBid(tokenId, false);
        (address collectionBidder, uint256 collectionBidAmount, uint256 collectionBidIndex) = getHighestBid(0, true);
        
        // No bids available
        if (tokenBidAmount == 0 && collectionBidAmount == 0) {
            revert NoBidsAvailable();
        }
        
        // Determine which bid to accept
        bool useTokenBid = tokenBidAmount >= collectionBidAmount;
        address highestBidder = useTokenBid ? tokenBidder : collectionBidder;
        uint256 highestAmount = useTokenBid ? tokenBidAmount : collectionBidAmount;
        
        // Check that highest bidder is not the current minter (prevent self-bidding)
        if (highestBidder == msg.sender) {
            revert SelfBiddingNotAllowed();
        }
        
        // Store original minter
        address oldMinter = msg.sender;
        
        // First transfer the minter status to the highest bidder
        _tokenMinterOverrides[tokenId] = highestBidder;
        
        // Update the minter in the centralized distributor 
        try centralizedDistributor.setTokenMinter(address(this), tokenId, highestBidder) {
            // No need to do anything here, the function succeeded
        } catch {
            // If updating the minter in the distributor fails, we still want to proceed with
            // the bid acceptance, as the override in this contract will take precedence
        }
        
        // All royalties go to contract owner for minter status trades
        // Send the entire amount to the contract owner
        (bool success, ) = payable(owner()).call{value: highestAmount}("");
        if (!success) {
            revert TransferFailed();
        }
        
        // Remove the accepted bid
        if (useTokenBid) {
            // Remove the accepted bid from token-specific bids
            if (tokenBidIndex < _tokenBids[tokenId].length - 1) {
                _tokenBids[tokenId][tokenBidIndex] = _tokenBids[tokenId][_tokenBids[tokenId].length - 1];
            }
            delete _tokenBids[tokenId];
        } else {
            // Remove the accepted bid from collection-wide bids
            if (collectionBidIndex < _collectionBids.length - 1) {
                _collectionBids[collectionBidIndex] = _collectionBids[_collectionBids.length - 1];
            }
            _collectionBids.pop();
        }
        
        // Refund all other bids (excluding the accepted bid)
        _refundAllOtherBids(tokenId, highestBidder);
        
        // Emit assignment event
        emit MinterStatusAssigned(tokenId, highestBidder, oldMinter);
        
        // Emit bid acceptance event
        emit BidAccepted(oldMinter, highestBidder, tokenId, highestAmount);
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
     * @notice Accept the highest token purchase bid for a token to sell it
     * @dev Transfers the token to the highest bidder and sends the ETH to the seller
     * @param tokenId The token ID
     */
    function acceptHighestTokenBid(uint256 tokenId) external nonReentrant onlyTokenOwner(tokenId) {
        // Get the highest bid (token-specific and collection-wide)
        (address tokenBidder, uint256 tokenBidAmount, uint256 tokenBidIndex) = getHighestTokenBid(tokenId, false);
        (address collectionBidder, uint256 collectionBidAmount, uint256 collectionBidIndex) = getHighestTokenBid(0, true);
        
        // No bids available
        if (tokenBidAmount == 0 && collectionBidAmount == 0) {
            revert NoBidsAvailable();
        }
        
        // Determine which bid to accept
        bool useTokenBid = tokenBidAmount >= collectionBidAmount;
        address highestBidder = useTokenBid ? tokenBidder : collectionBidder;
        uint256 highestAmount = useTokenBid ? tokenBidAmount : collectionBidAmount;
        
        // Check that highest bidder is not the token owner (prevent self-bidding)
        if (highestBidder == msg.sender) {
            revert SelfBiddingNotAllowed();
        }
        
        // Store seller for event emission and refund handling
        address seller = msg.sender;
        
        // Handle royalty distribution
        uint256 royaltyAmount = (highestAmount * royaltyFeeNumerator) / FEE_DENOMINATOR; // calculate royalty
        uint256 sellerProceeds = highestAmount - royaltyAmount; // calculate proceeds after royalty
        
        // Send royalty to the distributor directly
        (bool sentRoyalty, ) = payable(royaltyDistributor).call{value: royaltyAmount}("");
        if (!sentRoyalty) {
            revert TransferFailed();
        }
        
        // Send seller proceeds
        (bool sentProceeds, ) = payable(seller).call{value: sellerProceeds}("");
        if (!sentProceeds) {
            revert TransferFailed();
        }
        
        // Update bid arrays
        if (useTokenBid) {
            // Remove the accepted bid from the token-specific bids
            if (tokenBidIndex < _tokenPurchaseBids[tokenId].length - 1) {
                _tokenPurchaseBids[tokenId][tokenBidIndex] = _tokenPurchaseBids[tokenId][_tokenPurchaseBids[tokenId].length - 1];
            }
            _tokenPurchaseBids[tokenId].pop();
        } else {
            // Remove the accepted bid from the collection-wide bids
            if (_collectionTokenBids.length > 0) {
                if (collectionBidIndex < _collectionTokenBids.length - 1) {
                    _collectionTokenBids[collectionBidIndex] = _collectionTokenBids[_collectionTokenBids.length - 1];
                }
                _collectionTokenBids.pop();
            }
        }
        
        // Refund all other bids for this token (excluding the accepted bid)
        _refundAllOtherTokenBids(tokenId, highestBidder);
        
        // Transfer token to highest bidder
        _safeTransfer(seller, highestBidder, tokenId, "");
        
        // Record the sale in our own contract for analytics and emit event
        try this.recordSale(tokenId, highestAmount) {
            // Successfully recorded the sale
        } catch {
            // If recording fails, continue with the sale but don't emit the event
        }
        
        // Update token holder in the distributor for analytics
        try centralizedDistributor.updateTokenHolder(address(this), tokenId, highestBidder) {} catch {}
        
        // Emit acceptance event
        emit TokenBidAccepted(seller, highestBidder, tokenId, highestAmount);
    }
    
    /**
     * @dev Helper function to clear token-specific bids for a token (not collection-wide bids)
     * @param tokenId The token ID
     */
    function _clearTokenSpecificBids(uint256 tokenId) internal {
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
        }
    }
    
    /**
     * @dev Helper function to clear all bids for a token (including remaining collection-wide bids)
     * @param tokenId The token ID
     * @dev This is kept for backward compatibility but is no longer used in acceptHighestTokenBid
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

    /**
     * @notice Refund all other bidders for a specific token (excluding the winner)
     * @dev Called when a bid is accepted to return ETH to other bidders
     * @param tokenId The token ID
     * @param winningBidder The address of the winning bidder who shouldn't be refunded
     */
    function _refundAllOtherTokenBids(uint256 tokenId, address winningBidder) internal {
        // Refund token-specific bidders
        TokenBid[] storage bids = _tokenPurchaseBids[tokenId];
        for (uint256 i = 0; i < bids.length; i++) {
            address bidder = bids[i].bidder;
            uint256 amount = bids[i].amount;
            
            // Skip the winning bidder as they've already had their bid accepted
            if (bidder != winningBidder && bidder != address(0) && amount > 0) {
                // Reset bid data before making external call
                bids[i].amount = 0;
                
                // Send refund
                (bool success, ) = payable(bidder).call{value: amount}("");
                if (success) {
                    emit TokenBidWithdrawn(bidder, tokenId, amount, false);
                }
                // Even if transfer fails, we continue processing other refunds
            }
        }
        
        // Clear the array after processing all bids
        delete _tokenPurchaseBids[tokenId];
    }

    /**
     * @notice Refund all other bidders for a minter status (excluding the winner)
     * @dev Called when a bid is accepted to return ETH to other bidders
     * @param tokenId The token ID
     * @param winningBidder The address of the winning bidder who shouldn't be refunded
     */
    function _refundAllOtherBids(uint256 tokenId, address winningBidder) internal {
        // Refund token-specific bidders
        Bid[] storage bids = _tokenBids[tokenId];
        for (uint256 i = 0; i < bids.length; i++) {
            address bidder = bids[i].bidder;
            uint256 amount = bids[i].amount;
            
            // Skip the winning bidder as they've already had their bid accepted
            if (bidder != winningBidder && bidder != address(0) && amount > 0) {
                // Reset bid data before making external call
                bids[i].amount = 0;
                
                // Send refund
                (bool success, ) = payable(bidder).call{value: amount}("");
                if (success) {
                    emit BidWithdrawn(bidder, tokenId, amount, false);
                }
                // Even if transfer fails, we continue processing other refunds
            }
        }
        
        // Clear the array after processing all bids
        // Note: This is already done in acceptHighestBid with "delete _tokenBids[tokenId]"
    }
}