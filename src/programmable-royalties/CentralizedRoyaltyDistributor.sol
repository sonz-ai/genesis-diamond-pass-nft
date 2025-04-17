// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol"; // Added for merkle proof verification

/**
 * @title CentralizedRoyaltyDistributor
 * @author Custom implementation based on Limit Break, Inc. patterns
 * @notice A centralized royalty distributor that works with OpenSea's single address royalty model
 *         while maintaining the functionality to distribute royalties to minters and creators based on accumulated funds.
 * @dev This version uses a Merkle distributor pattern for efficient, gas-optimized claims. An off-chain service tracks 
 *      royalty attributions and periodically submits Merkle roots containing claimable amounts per recipient.
 */
contract CentralizedRoyaltyDistributor is ERC165, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;
    using Address for address payable;

    error RoyaltyDistributor__CollectionNotRegistered();
    error RoyaltyDistributor__MinterCannotBeZeroAddress();
    error RoyaltyDistributor__MinterHasAlreadyBeenAssignedToTokenId();
    error RoyaltyDistributor__CreatorCannotBeZeroAddress();
    error RoyaltyDistributor__SharesCannotBeZero(); // Combined error for shares
    error RoyaltyDistributor__RoyaltyFeeWillExceedSalePrice();
    error RoyaltyDistributor__CollectionAlreadyRegistered();
    error RoyaltyDistributor__NotEnoughEtherToDistributeForCollection();
    error RoyaltyDistributor__NotEnoughTokensToDistributeForCollection();
    error RoyaltyDistributor__ZeroAmountToDistribute();
    error RoyaltyDistributor__NoRoyaltiesDueForAddress();
    error RoyaltyDistributor__AddressNotMinterOrCreatorForCollection(); // Specific error for claims
    error RoyaltyDistributor__CallerIsNotCollectionOwner(); // Specific error for collection-callable functions
    error RoyaltyDistributor__SharesDoNotSumToDenominator(); // Ensure shares add up correctly
    error RoyaltyDistributor__CallerIsNotAdminOrServiceAccount(); // New error
    error RoyaltyDistributor__NoActiveMerkleRoot(); // New error for Merkle claims
    error RoyaltyDistributor__AlreadyClaimed(); // New error for Merkle claims
    error RoyaltyDistributor__InvalidProof(); // New error for Merkle claims
    error RoyaltyDistributor__InsufficientBalanceForRoot(); // New error for Merkle root submission
    error RoyaltyDistributor__OracleUpdateTooFrequent(); // New error for oracle rate limiting
    error RoyaltyDistributor__TransactionAlreadyProcessed(); // New error for batch update

    struct CollectionConfig {
        uint256 royaltyFeeNumerator;
        uint256 minterShares; // e.g., 2000 for 20% if denominator is 10000
        uint256 creatorShares; // e.g., 8000 for 80% if denominator is 10000
        address creator;
        bool registered;
    }

    struct TokenMinter {
        address minter;
        bool assigned;
    }
    
    // Struct to keep track of token info for a minter
    struct MinterTokenInfo {
        address collection;
        uint256 tokenId;
    }

    // New structs for royalty tracking
    struct TokenRoyaltyData {
        address minter;               // Original minter address
        address currentOwner;         // Current owner address
        uint256 transactionCount;     // Number of times the token has been traded
        uint256 totalVolume;          // Cumulative trading volume
        uint256 lastSyncedBlock;      // Latest block height when royalty data was updated
        uint256 minterRoyaltyEarned;  // Total royalties earned by minter
        uint256 creatorRoyaltyEarned; // Total royalties earned by creator for this token
        mapping(bytes32 => bool) processedTransactions; // Hash map to prevent duplicate processing
    }

    struct CollectionRoyaltyData {
        uint256 totalVolume;          // Total volume across all tokens
        uint256 lastSyncedBlock;      // Latest sync block for the collection
        uint256 totalRoyaltyCollected; // Total royalties received
    }

    // Using 10,000 basis points for shares as well for consistency
    uint256 public constant SHARES_DENOMINATOR = 10_000; 
    uint96 public constant FEE_DENOMINATOR = 10_000; // For royalty fee calculation

    // Mapping from collection address => collection configuration
    mapping(address => CollectionConfig) private _collectionConfigs;
    
    // Mapping from collection address => token ID => minter address
    mapping(address => mapping(uint256 => TokenMinter)) private _minters;
    
    // Mapping from minter address => collection address => list of token IDs they minted in that collection
    mapping(address => mapping(address => uint256[])) private _minterCollectionTokens;
    
    // Accumulated royalties (in ETH) for each collection
    mapping(address => uint256) private _collectionRoyalties;
    
    // Accumulated royalties (in ERC20 tokens) for each collection and token
    mapping(address => mapping(IERC20 => uint256)) private _collectionERC20Royalties;

    // NEW: Mappings for Merkle distributor pattern
    mapping(address => bytes32) private _activeMerkleRoots; // collection => root
    mapping(bytes32 => mapping(address => bool)) private _hasClaimedMerkle; // root => recipient => claimed status
    mapping(bytes32 => uint256) private _merkleRootTotalAmount; // root => totalAmount
    mapping(bytes32 => uint256) private _merkleRootSubmissionTime; // root => timestamp

    // NEW: Mappings for royalty data tracking
    mapping(address => mapping(uint256 => TokenRoyaltyData)) private _tokenRoyaltyData; // collection => tokenId => data
    mapping(address => CollectionRoyaltyData) private _collectionRoyaltyData; // collection => data

    // NEW: Mappings for oracle rate limiting
    mapping(address => uint256) private _lastOracleUpdateBlock; // collection => block number
    mapping(address => uint256) private _oracleUpdateMinBlockInterval; // collection => block interval

    // NEW: Global analytics state variables tracking
    uint256 public totalAccruedRoyalty;
    uint256 public totalClaimedRoyalty;

    // NEW: Mapping to track ERC20 claim status per merkle root
    mapping(bytes32 => mapping(address => mapping(address => bool))) private _hasClaimedERC20Merkle; // root => recipient => token => claimed

    // Role definition
    bytes32 public constant SERVICE_ACCOUNT_ROLE = keccak256("SERVICE_ACCOUNT_ROLE");

    // Events
    event CollectionRegistered(address indexed collection, uint256 royaltyFeeNumerator, uint256 minterShares, uint256 creatorShares, address creator);
    event MinterAssigned(address indexed collection, uint256 indexed tokenId, address indexed minter);
    event RoyaltyReceived(address indexed collection, address indexed sender, uint256 amount); // Added collection context
    event ERC20RoyaltyReceived(address indexed collection, address indexed token, address indexed sender, uint256 amount); // Added collection context
    
    // NEW: Events for Merkle distribution
    event MerkleRootSubmitted(address indexed collection, bytes32 indexed merkleRoot, uint256 totalAmountInTree, uint256 timestamp);
    event MerkleRoyaltyClaimed(address indexed recipient, uint256 amount, bytes32 indexed merkleRoot, address indexed collection);
    event ERC20MerkleRoyaltyClaimed(address indexed recipient, address indexed token, uint256 amount, bytes32 indexed merkleRoot, address collection);
    
    // NEW: Event for detailed royalty attribution
    event RoyaltyAttributed(
        address indexed collection,
        uint256 indexed tokenId,
        address indexed minter,
        uint256 salePrice,
        uint256 minterShareAttributed,
        uint256 creatorShareAttributed,
        bytes32 transactionHash 
    );
    
    // New event for oracle settings
    event OracleUpdateIntervalSet(address indexed collection, uint256 minBlockInterval);

    /**
     * @notice Modifier to ensure the caller is the registered collection contract
     */
    modifier onlyCollection(address collection) {
        if (!_collectionConfigs[collection].registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }
        if (msg.sender != collection) {
            revert RoyaltyDistributor__CallerIsNotCollectionOwner();
        }
        _;
    }

    constructor() { // Constructor for AccessControl setup
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); // Grant admin role to deployer
        _grantRole(SERVICE_ACCOUNT_ROLE, msg.sender); // Grant service role to deployer initially
        _setRoleAdmin(SERVICE_ACCOUNT_ROLE, DEFAULT_ADMIN_ROLE); // Admin manages service role
    }

    /**
     * @notice Receive function to accept ETH payments from marketplaces 
     * @dev Funds received will be added to the collection's royalty pool.
     *      For direct marketplaces implementing IERC2981, this will be called automatically.
     */
    receive() external payable virtual {
        // Attribute received ETH to the collection if the caller is a registered collection
        if (_collectionConfigs[msg.sender].registered) {
            // Increment per‑collection ETH pool
            _collectionRoyalties[msg.sender] += msg.value;

            // Track total royalties collected for analytics
            _collectionRoyaltyData[msg.sender].totalRoyaltyCollected += msg.value;

            // Emit event with `msg.sender` as both the collection (recipient of royalties) and sender (originator)
            emit RoyaltyReceived(msg.sender, _msgSender(), msg.value);
        }
        // If the sender is not a registered collection we still accept the ETH, but the
        // funds remain unattributed until an admin manually allocates them using
        // `addCollectionRoyalties`.
    }

    /**
     * @notice Register a collection with this royalty distributor
     * @param collection The address of the collection contract itself
     * @param royaltyFeeNumerator The royalty fee numerator (basis points, e.g., 750 for 7.5%)
     * @param minterShares The shares allocated to the minter (basis points, e.g., 2000 for 20%)
     * @param creatorShares The shares allocated to the creator (basis points, e.g., 8000 for 80%)
     * @param creator The creator address for the collection
     */
    function registerCollection(
        address collection,
        uint96 royaltyFeeNumerator,
        uint256 minterShares,
        uint256 creatorShares,
        address creator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) { // Only admin can register new collections
        
        if(_collectionConfigs[collection].registered) {
            revert RoyaltyDistributor__CollectionAlreadyRegistered();
        }
        
        if(royaltyFeeNumerator > FEE_DENOMINATOR) {
            revert RoyaltyDistributor__RoyaltyFeeWillExceedSalePrice();
        }

        if (minterShares == 0 || creatorShares == 0) {
            revert RoyaltyDistributor__SharesCannotBeZero();
        }

        if (minterShares + creatorShares != SHARES_DENOMINATOR) {
             revert RoyaltyDistributor__SharesDoNotSumToDenominator();
        }

        if (creator == address(0)) {
            revert RoyaltyDistributor__CreatorCannotBeZeroAddress();
        }

        _collectionConfigs[collection] = CollectionConfig({
            royaltyFeeNumerator: royaltyFeeNumerator,
            minterShares: minterShares,
            creatorShares: creatorShares,
            creator: creator,
            registered: true
        });

        // Initialize the collection's royalty data
        _collectionRoyaltyData[collection] = CollectionRoyaltyData({
            totalVolume: 0,
            lastSyncedBlock: block.number,
            totalRoyaltyCollected: 0
        });

        // Set default oracle update interval (can be changed by admin)
        _oracleUpdateMinBlockInterval[collection] = 5760; // Default ~1 day at 15s blocks

        emit CollectionRegistered(collection, royaltyFeeNumerator, minterShares, creatorShares, creator);
    }

    /**
     * @notice Returns whether a collection is registered with this distributor
     * @param collection The collection address to check
     */
    function isCollectionRegistered(address collection) external view returns (bool) {
        return _collectionConfigs[collection].registered;
    }

    /**
     * @notice Get collection royalty configuration
     * @param collection The collection address
     * @return royaltyFeeNumerator The collection royalty fee numerator
     * @return minterShares The minter shares (basis points)
     * @return creatorShares The creator shares (basis points)
     * @return creator The creator address
     */
    function getCollectionConfig(address collection) external view returns (
        uint256 royaltyFeeNumerator,
        uint256 minterShares,
        uint256 creatorShares,
        address creator
    ) {
        CollectionConfig storage config = _collectionConfigs[collection];
        if (!config.registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }

        return (
            config.royaltyFeeNumerator,
            config.minterShares,
            config.creatorShares,
            config.creator
        );
    }

    /**
     * @notice Register a token minter for a specific collection
     * @dev Should only be called by the collection contract during its minting process.
     *      Uses the `onlyCollection` modifier.
     * @param collection The collection address (enforced by modifier)
     * @param tokenId The token ID
     * @param minter The minter address
     */
    function setTokenMinter(address collection, uint256 tokenId, address minter) external onlyCollection(collection) {
        // Modifier ensures collection is registered and caller is the collection.
        
        if (minter == address(0)) {
            revert RoyaltyDistributor__MinterCannotBeZeroAddress();
        }

        if (_minters[collection][tokenId].assigned) {
            revert RoyaltyDistributor__MinterHasAlreadyBeenAssignedToTokenId();
        }

        _minters[collection][tokenId] = TokenMinter({
            minter: minter,
            assigned: true
        });
        
        // Add this token to the minter's list for this specific collection
        _minterCollectionTokens[minter][collection].push(tokenId);

        // Initialize the token's royalty data
        TokenRoyaltyData storage tokenData = _tokenRoyaltyData[collection][tokenId];
        tokenData.minter = minter;
        tokenData.currentOwner = minter;
        tokenData.transactionCount = 0;
        tokenData.totalVolume = 0;
        tokenData.lastSyncedBlock = block.number;
        tokenData.minterRoyaltyEarned = 0;
        tokenData.creatorRoyaltyEarned = 0;

        emit MinterAssigned(collection, tokenId, minter);
    }

    /**
     * @notice Get the minter of a token
     * @param collection The collection address
     * @param tokenId The token ID
     * @return The minter address
     */
    function getMinter(address collection, uint256 tokenId) external view returns (address) {
        // We don't check if collection is registered here, allowing checks even if unregistered (returns address(0))
        return _minters[collection][tokenId].minter;
    }
    
    /**
     * @notice Get all tokens minted by a specific address within a specific collection
     * @param minter The minter address
     * @param collection The collection address
     * @return An array of token IDs minted by the minter in that collection
     */
    function getTokensByMinterForCollection(address minter, address collection) external view returns (uint256[] memory) {
        return _minterCollectionTokens[minter][collection];
    }
    
    /**
     * @notice Get the number of tokens minted by a specific address in a specific collection
     * @param minter The minter address
     * @param collection The collection address
     * @return The number of tokens minted
     */
    function getMinterTokenCountForCollection(address minter, address collection) external view returns (uint256) {
        return _minterCollectionTokens[minter][collection].length;
    }

    /**
     * @notice Get the accumulated ETH royalties for a collection
     * @param collection The collection address
     * @return The accumulated ETH royalties
     */
    function getCollectionRoyalties(address collection) external view returns (uint256) {
        return _collectionRoyalties[collection];
    }

    /**
     * @notice Get the accumulated ERC20 royalties for a collection and specific token
     * @param collection The collection address
     * @param token The ERC20 token address
     * @return The accumulated royalties for that token
     */
    function getCollectionERC20Royalties(address collection, IERC20 token) external view returns (uint256) {
        return _collectionERC20Royalties[collection][token];
    }

    /**
     * @notice Set the minimum block interval for oracle updates for a collection
     * @dev Only callable by admin
     * @param collection The collection address
     * @param interval The minimum block interval between oracle updates
     */
    function setOracleUpdateMinBlockInterval(address collection, uint256 interval) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _oracleUpdateMinBlockInterval[collection] = interval;
        emit OracleUpdateIntervalSet(collection, interval);
    }

    /**
     * @notice Process batch royalty data for multiple transactions
     * @dev Restricted to SERVICE_ACCOUNT_ROLE or DEFAULT_ADMIN_ROLE
     * @param collection The collection address
     * @param tokenIds Array of token IDs involved in sales
     * @param minters Array of minter addresses for each token
     * @param salePrices Array of sale prices for each transaction
     * @param transactionTimestamps Array of timestamps for each transaction
     * @param transactionHashes Array of transaction hashes for each sale
     */
    function batchUpdateRoyaltyData(
        address collection,
        uint256[] calldata tokenIds,
        address[] calldata minters,
        uint256[] calldata salePrices,
        uint256[] calldata transactionTimestamps,
        bytes32[] calldata transactionHashes
    ) external {
        // Check caller has permission
        if (!hasRole(DEFAULT_ADMIN_ROLE, _msgSender()) && !hasRole(SERVICE_ACCOUNT_ROLE, _msgSender())) {
            revert RoyaltyDistributor__CallerIsNotAdminOrServiceAccount();
        }

        // Check collection is registered
        CollectionConfig storage config = _collectionConfigs[collection];
        if (!config.registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }

        // Validate arrays have the same length
        uint256 length = tokenIds.length;
        require(
            minters.length == length &&
            salePrices.length == length &&
            transactionTimestamps.length == length &&
            transactionHashes.length == length,
            "Array lengths must match"
        );

        // Process each sale
        for (uint256 i = 0; i < length; i++) {
            uint256 tokenId = tokenIds[i];
            address minter = minters[i];
            uint256 salePrice = salePrices[i];
            // uint256 transactionTimestamp = transactionTimestamps[i];
            bytes32 txHash = transactionHashes[i];
            
            // Get token royalty data
            TokenRoyaltyData storage tokenData = _tokenRoyaltyData[collection][tokenId];
            
            // Skip if transaction already processed
            if (tokenData.processedTransactions[txHash]) {
                continue;
            }
            
            // Calculate royalty amount based on collection config
            uint256 royaltyAmount = (salePrice * config.royaltyFeeNumerator) / FEE_DENOMINATOR;
            
            if (royaltyAmount > 0) {
                // Calculate shares
                uint256 minterShare = (royaltyAmount * config.minterShares) / SHARES_DENOMINATOR;
                uint256 creatorShare = royaltyAmount - minterShare; // Avoid rounding errors
                
                // Update token data
                tokenData.transactionCount++;
                tokenData.totalVolume += salePrice;
                tokenData.minterRoyaltyEarned += minterShare;
                tokenData.creatorRoyaltyEarned += creatorShare;
                tokenData.lastSyncedBlock = block.number;
                tokenData.processedTransactions[txHash] = true;
                
                // Update collection data (Total Volume and Last Sync Block Only)
                CollectionRoyaltyData storage collectionData = _collectionRoyaltyData[collection];
                collectionData.totalVolume += salePrice;
                collectionData.lastSyncedBlock = block.number;
                
                // --- On‑chain analytics update ---
                totalAccruedRoyalty += royaltyAmount;

                // Emit detailed attribution event
                emit RoyaltyAttributed(
                    collection,
                    tokenId,
                    minter,
                    salePrice,
                    minterShare,
                    creatorShare,
                    txHash
                );
            }
        }
    }

    /**
     * @notice Submit a Merkle root for royalty claims
     * @dev Only callable by SERVICE_ACCOUNT_ROLE
     * @param collection The collection address
     * @param merkleRoot The Merkle root of all claimable (address, amount) pairs
     * @param totalAmountInTree The total ETH amount included in the Merkle tree
     */
    function submitRoyaltyMerkleRoot(
        address collection, 
        bytes32 merkleRoot, 
        uint256 totalAmountInTree
    ) external onlyRole(SERVICE_ACCOUNT_ROLE) {
        // Check collection is registered
        if (!_collectionConfigs[collection].registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }
        
        // Check available balance is sufficient for the total amounts in the tree
        if (totalAmountInTree > _collectionRoyalties[collection]) {
            revert RoyaltyDistributor__InsufficientBalanceForRoot();
        }
        
        // Set the active Merkle root for the collection
        _activeMerkleRoots[collection] = merkleRoot;
        _merkleRootTotalAmount[merkleRoot] = totalAmountInTree;
        _merkleRootSubmissionTime[merkleRoot] = block.timestamp;
        
        // --- On‑chain analytics update ---
        totalAccruedRoyalty += totalAmountInTree;
        
        emit MerkleRootSubmitted(
            collection, 
            merkleRoot, 
            totalAmountInTree, 
            block.timestamp
        );
    }

    /**
     * @notice Claim royalties using Merkle proof
     * @dev Verifies the proof and transfers the claimed amount to the recipient
     * @param collection The collection address
     * @param recipient The address receiving the royalties
     * @param amount The amount to claim
     * @param merkleProof The Merkle proof to verify the claim
     */
    function claimRoyaltiesMerkle(
        address collection,
        address recipient,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external nonReentrant {
        // Get active Merkle root for collection
        bytes32 activeRoot = _activeMerkleRoots[collection];
        
        // Check root exists
        if (activeRoot == bytes32(0)) {
            revert RoyaltyDistributor__NoActiveMerkleRoot();
        }
        
        // Check has not already claimed
        if (_hasClaimedMerkle[activeRoot][recipient]) {
            revert RoyaltyDistributor__AlreadyClaimed();
        }
        
        // Verify proof
        bytes32 leaf = keccak256(abi.encodePacked(recipient, amount));
        bool validProof = MerkleProof.verify(merkleProof, activeRoot, leaf);
        
        if (!validProof) {
            revert RoyaltyDistributor__InvalidProof();
        }
        
        // Mark as claimed
        _hasClaimedMerkle[activeRoot][recipient] = true;
        
        // Ensure royalty pool has enough funds
        if (_collectionRoyalties[collection] < amount) {
            revert RoyaltyDistributor__NotEnoughEtherToDistributeForCollection();
        }
        
        // Reduce collection royalties
        _collectionRoyalties[collection] -= amount;
        
        // Transfer amount to recipient
        payable(recipient).sendValue(amount);
        
        // --- On‑chain analytics update ---
        totalClaimedRoyalty += amount;
        
        emit MerkleRoyaltyClaimed(recipient, amount, activeRoot, collection);
    }

    /**
     * @notice Public function to trigger oracle update of royalty data
     * @dev Rate-limited to prevent abuse
     * @param collection The collection address
     */
    function updateRoyaltyDataViaOracle(address collection) external {
        // Check collection is registered
        if (!_collectionConfigs[collection].registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }
        
        // Check rate limit
        uint256 minInterval = _oracleUpdateMinBlockInterval[collection];
        if (block.number < _lastOracleUpdateBlock[collection] + minInterval) {
            revert RoyaltyDistributor__OracleUpdateTooFrequent();
        }
        
        // Update last call block
        _lastOracleUpdateBlock[collection] = block.number;
        
        // This is where you would make the Chainlink oracle call
        // Example (commented out as it would need the Chainlink infrastructure):
        /*
        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfillRoyaltyData.selector
        );
        req.add("collection", Chainlink.addressToString(collection));
        req.add("fromBlock", Chainlink.uintToString(_collectionRoyaltyData[collection].lastSyncedBlock));
        sendOperatorRequest(req, oracleFee);
        */
    }
    
    /**
     * @notice Chainlink callback function for oracle royalty data updates
     * @dev Would be called by the Chainlink node after processing updateRoyaltyDataViaOracle
     * @param _requestId The Chainlink request ID
     * @param collection The collection address
     * @param tokenIds Array of token IDs involved in sales
     * @param minters Array of minter addresses for each token
     * @param salePrices Array of sale prices for each transaction
     * @param transactionTimestamps Array of timestamps for each transaction
     * @param transactionHashes Array of transaction hashes for each sale
     */
    function fulfillRoyaltyData(
        bytes32 _requestId,
        address collection,
        uint256[] calldata tokenIds,
        address[] calldata minters,
        uint256[] calldata salePrices,
        uint256[] calldata transactionTimestamps,
        bytes32[] calldata transactionHashes
    ) external /* recordChainlinkFulfillment(_requestId) */ {
        // This function would need to be restricted to the Chainlink oracle node
        // For now we'll implement the same logic as batchUpdateRoyaltyData
        
        // Assuming we have verified this is from our oracle, process the data
        // This is essentially the same as batchUpdateRoyaltyData but would be
        // triggered by the Chainlink oracle instead of a service account
        
        // The implementation would be similar to batchUpdateRoyaltyData 
        // but with Chainlink-specific security checks
    }

    /**
     * @notice Get the active Merkle root for a collection
     * @param collection The collection address
     */
    function getActiveMerkleRoot(address collection) external view returns (bytes32) {
        return _activeMerkleRoots[collection];
    }

    /**
     * @notice Check if a recipient has already claimed for a specific Merkle root
     * @param merkleRoot The Merkle root to check against
     * @param recipient The recipient address
     */
    function hasClaimedMerkle(bytes32 merkleRoot, address recipient) external view returns (bool) {
        return _hasClaimedMerkle[merkleRoot][recipient];
    }

    /**
     * @notice Get information about a Merkle root
     * @param merkleRoot The Merkle root
     * @return totalAmount The total amount included in the root
     * @return submissionTime The timestamp when the root was submitted
     */
    function getMerkleRootInfo(bytes32 merkleRoot) external view returns (
        uint256 totalAmount,
        uint256 submissionTime
    ) {
        return (
            _merkleRootTotalAmount[merkleRoot],
            _merkleRootSubmissionTime[merkleRoot]
        );
    }

    /**
     * @notice Get royalty data for a specific token
     * @param collection The collection address
     * @param tokenId The token ID
     * @return minter The token minter
     * @return currentOwner The current owner
     * @return transactionCount Number of transactions
     * @return totalVolume Total sales volume
     * @return minterRoyaltyEarned Total royalties earned by the minter
     * @return creatorRoyaltyEarned Total royalties earned by the creator
     */
    function getTokenRoyaltyData(address collection, uint256 tokenId) external view returns (
        address minter,
        address currentOwner,
        uint256 transactionCount,
        uint256 totalVolume,
        uint256 minterRoyaltyEarned,
        uint256 creatorRoyaltyEarned
    ) {
        TokenRoyaltyData storage data = _tokenRoyaltyData[collection][tokenId];
        return (
            data.minter,
            data.currentOwner,
            data.transactionCount,
            data.totalVolume,
            data.minterRoyaltyEarned,
            data.creatorRoyaltyEarned
        );
    }

    /**
     * @notice Get royalty data for a collection
     * @param collection The collection address
     * @return totalVolume Total sales volume
     * @return lastSyncedBlock Last block number when data was synced
     * @return totalRoyaltyCollected Total royalties collected
     */
    function getCollectionRoyaltyData(address collection) external view returns (
        uint256 totalVolume,
        uint256 lastSyncedBlock,
        uint256 totalRoyaltyCollected
    ) {
        CollectionRoyaltyData storage data = _collectionRoyaltyData[collection];
        return (
            data.totalVolume,
            data.lastSyncedBlock,
            data.totalRoyaltyCollected
        );
    }

    /**
     * @dev Indicates whether the contract implements the specified interface.
     * @param interfaceId The interface id
     * @return true if the contract implements the specified interface, false otherwise
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, AccessControl) returns (bool) {
        // Includes ERC165 and IAccessControl
        return super.supportsInterface(interfaceId);
    }

    // REMOVED: recordSaleRoyalty, recordERC20Royalty, claimRoyalties, claimERC20Royalties functions

    // We're keeping addCollectionRoyalties and addCollectionERC20Royalties as they might be useful
    // for manual testing or in case direct contributions are needed
    
    /**
     * @notice Manually add ETH royalties for a collection (callable by anyone, requires sending ETH)
     * @dev Use this for direct contributions or if the receive() function is too restrictive.
     * @param collection The collection address
     */
    function addCollectionRoyalties(address collection) external payable {
        if (!_collectionConfigs[collection].registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }
        if (msg.value == 0) {
            revert RoyaltyDistributor__ZeroAmountToDistribute();
        }

        _collectionRoyalties[collection] += msg.value;
        // NEW: maintain totalRoyaltyCollected analytics
        _collectionRoyaltyData[collection].totalRoyaltyCollected += msg.value;
        emit RoyaltyReceived(collection, msg.sender, msg.value);
    }

    /**
     * @notice Manually add ERC20 royalties for a collection (callable by anyone)
     * @dev Requires the caller to have approved this contract to spend the tokens.
     * @param collection The collection address
     * @param token The ERC20 token address
     * @param amount The amount to add
     */
    function addCollectionERC20Royalties(address collection, IERC20 token, uint256 amount) external {
        if (!_collectionConfigs[collection].registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }
        if (amount == 0) {
            revert RoyaltyDistributor__ZeroAmountToDistribute();
        }

        token.safeTransferFrom(msg.sender, address(this), amount);
        _collectionERC20Royalties[collection][token] += amount;
        emit ERC20RoyaltyReceived(collection, address(token), msg.sender, amount);
    }

    /**
     * @notice Claim ERC20 royalties using Merkle proof
     * @dev Similar to claimRoyaltiesMerkle but for ERC20 tokens
     * @param collection The collection address
     * @param recipient The address receiving the royalties
     * @param token The ERC20 token address
     * @param amount The amount to claim
     * @param merkleProof The Merkle proof
     */
    function claimERC20RoyaltiesMerkle(
        address collection,
        address recipient,
        IERC20 token,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external nonReentrant {
        // Get active root for collection (shared across ETH & ERC20).
        bytes32 activeRoot = _activeMerkleRoots[collection];

        if (activeRoot == bytes32(0)) {
            revert RoyaltyDistributor__NoActiveMerkleRoot();
        }

        if (_hasClaimedERC20Merkle[activeRoot][recipient][address(token)]) {
            revert RoyaltyDistributor__AlreadyClaimed();
        }

        // Leaf includes token to avoid collision between different tokens
        bytes32 leaf = keccak256(abi.encodePacked(recipient, address(token), amount));
        bool validProof = MerkleProof.verify(merkleProof, activeRoot, leaf);

        if (!validProof) {
            revert RoyaltyDistributor__InvalidProof();
        }

        // Mark as claimed
        _hasClaimedERC20Merkle[activeRoot][recipient][address(token)] = true;

        // Ensure royalty pool has enough tokens
        if (_collectionERC20Royalties[collection][token] < amount) {
            revert RoyaltyDistributor__NotEnoughTokensToDistributeForCollection();
        }

        // Reduce pool
        _collectionERC20Royalties[collection][token] -= amount;

        // Transfer tokens to recipient
        token.safeTransfer(recipient, amount);

        // No ETH analytics increment since token claim

        emit ERC20MerkleRoyaltyClaimed(recipient, address(token), amount, activeRoot, collection);
    }

    // --- Analytics view functions ---

    function totalAccrued() external view returns (uint256) {
        return totalAccruedRoyalty;
    }

    function totalClaimed() external view returns (uint256) {
        return totalClaimedRoyalty;
    }
}