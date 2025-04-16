// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title CentralizedRoyaltyDistributor
 * @author Custom implementation based on Limit Break, Inc. patterns
 * @notice A centralized royalty distributor that works with OpenSea's single address royalty model
 *         while maintaining the functionality to distribute royalties to minters and creators based on accumulated funds.
 * @dev This version uses a simplified distribution model where claims are based on the total accumulated royalty pool per collection, split by predefined shares. It does not track individual sale prices for precise per-sale distribution.
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

    // Role definition
    bytes32 public constant SERVICE_ACCOUNT_ROLE = keccak256("SERVICE_ACCOUNT_ROLE");

    // Events
    event CollectionRegistered(address indexed collection, uint256 royaltyFeeNumerator, uint256 minterShares, uint256 creatorShares, address creator);
    event MinterAssigned(address indexed collection, uint256 indexed tokenId, address indexed minter);
    event RoyaltyReceived(address indexed collection, address indexed sender, uint256 amount); // Added collection context
    event ERC20RoyaltyReceived(address indexed collection, address indexed token, address indexed sender, uint256 amount); // Added collection context
    event SaleRoyaltyRecorded(address indexed collection, uint256 indexed tokenId, uint256 salePrice, uint256 royaltyAmount); // Specific event for recorded sales royalty
    event RoyaltyClaimed(address indexed collection, address indexed claimant, uint256 amount, bool isMinter); // Renamed for clarity
    event ERC20RoyaltyClaimed(address indexed collection, address indexed token, address indexed claimant, uint256 amount, bool isMinter); // Renamed for clarity

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
     * @notice Receive function to accept direct ETH payments (e.g., manual top-ups by admin)
     * @dev Does not automatically allocate funds. Use addCollectionRoyalties.
     */
    receive() external payable virtual {
        // Intentionally left blank - requires manual assignment via addCollectionRoyalties
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
     * @notice Records a sale and allocates the calculated royalty to the collection's pool.
     * @dev Should only be called by the admin (DEFAULT_ADMIN_ROLE) or a service account (SERVICE_ACCOUNT_ROLE).
     * @param collection The collection address
     * @param tokenId The token ID that was sold
     * @param salePrice The sale price in ETH
     */
    function recordSaleRoyalty(address collection, uint256 tokenId, uint256 salePrice) external {
        // Role Check: Allow Admin or Service Account
        if (!hasRole(DEFAULT_ADMIN_ROLE, _msgSender()) && !hasRole(SERVICE_ACCOUNT_ROLE, _msgSender())) {
            revert RoyaltyDistributor__CallerIsNotAdminOrServiceAccount();
        }
        
        CollectionConfig storage config = _collectionConfigs[collection];
        if (!config.registered) {
             revert RoyaltyDistributor__CollectionNotRegistered();
        }

        uint256 royaltyAmount = (salePrice * config.royaltyFeeNumerator) / FEE_DENOMINATOR;

        if (royaltyAmount > 0) {
             _collectionRoyalties[collection] += royaltyAmount;
             emit SaleRoyaltyRecorded(collection, tokenId, salePrice, royaltyAmount);
        }
    }
    
    /**
     * @notice Records ERC20 royalties received from an external source.
     * @dev Should only be called by the admin (DEFAULT_ADMIN_ROLE) or a service account (SERVICE_ACCOUNT_ROLE).
     *      Assumes the ERC20 transfer to this contract has already occurred.
     * @param collection The collection address
     * @param token The ERC20 token address
     * @param amount The amount of ERC20 royalty received for this collection
     */
    function recordERC20Royalty(address collection, IERC20 token, uint256 amount) external {
        // Role Check: Allow Admin or Service Account
        if (!hasRole(DEFAULT_ADMIN_ROLE, _msgSender()) && !hasRole(SERVICE_ACCOUNT_ROLE, _msgSender())) {
            revert RoyaltyDistributor__CallerIsNotAdminOrServiceAccount();
        }

        if (!_collectionConfigs[collection].registered) {
             revert RoyaltyDistributor__CollectionNotRegistered();
        }

        if (amount > 0) {
            // Assumes the token transfer to *this* distributor contract happened *before* this call.
            // This function only records the amount against the collection.
            _collectionERC20Royalties[collection][token] += amount;
            emit ERC20RoyaltyReceived(collection, address(token), msg.sender, amount); // msg.sender is admin/service account
        }
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
     * @notice Distribute the claimant's share of accumulated ETH royalties for a specific collection.
     * @dev Calculates the share based on the claimant's role (minter or creator) and the total currently held royalties.
     * @param collection The collection address
     * @param claimant The address claiming royalties (must be the collection's creator or a minter in that collection)
     */
    function claimRoyalties(
        address collection,
        address claimant
    ) external nonReentrant {
        CollectionConfig storage config = _collectionConfigs[collection];
        if (!config.registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }

        uint256 availableAmount = _collectionRoyalties[collection];
        if (availableAmount == 0) {
            revert RoyaltyDistributor__NoRoyaltiesDueForAddress(); // Use specific error
        }
        
        bool isMinter = false;
        uint256 shareNumerator;

        if (claimant == config.creator) {
            shareNumerator = config.creatorShares;
            isMinter = false;
        } else {
            // Check if claimant is a minter *for this specific collection*
            if (_minterCollectionTokens[claimant][collection].length > 0) {
                 shareNumerator = config.minterShares;
                 isMinter = true;
            } else {
                 revert RoyaltyDistributor__AddressNotMinterOrCreatorForCollection();
            }
        }
        
        // Calculate amount based on recipient role's share of the total pool
        uint256 amountToDistribute = (availableAmount * shareNumerator) / SHARES_DENOMINATOR;
        
        if (amountToDistribute == 0) {
            revert RoyaltyDistributor__NoRoyaltiesDueForAddress();
        }
        
        // Decrease the total pool *before* sending to prevent reentrancy issues (although nonReentrant guard is also present)
        _collectionRoyalties[collection] -= amountToDistribute;
        
        // Send the royalties
        payable(claimant).sendValue(amountToDistribute);
        emit RoyaltyClaimed(collection, claimant, amountToDistribute, isMinter);
    }

    /**
     * @notice Distribute the claimant's share of accumulated ERC20 royalties for a specific collection and token.
     * @dev Calculates the share based on the claimant's role (minter or creator) and the total currently held royalties for that token.
     * @param collection The collection address
     * @param claimant The address claiming royalties (must be the collection's creator or a minter in that collection)
     * @param token The ERC20 token address
     */
    function claimERC20Royalties(
        address collection,
        address claimant,
        IERC20 token
    ) external nonReentrant {
        CollectionConfig storage config = _collectionConfigs[collection];
        if (!config.registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }

        uint256 availableAmount = _collectionERC20Royalties[collection][token];
        if (availableAmount == 0) {
            revert RoyaltyDistributor__NoRoyaltiesDueForAddress(); // Use specific error
        }
        
        bool isMinter = false;
        uint256 shareNumerator;

        if (claimant == config.creator) {
            shareNumerator = config.creatorShares;
            isMinter = false;
        } else {
            // Check if claimant is a minter *for this specific collection*
            if (_minterCollectionTokens[claimant][collection].length > 0) {
                 shareNumerator = config.minterShares;
                 isMinter = true;
            } else {
                 revert RoyaltyDistributor__AddressNotMinterOrCreatorForCollection();
            }
        }
        
        // Calculate amount based on recipient role's share of the total pool for this token
        uint256 amountToDistribute = (availableAmount * shareNumerator) / SHARES_DENOMINATOR;
        
        if (amountToDistribute == 0) {
            revert RoyaltyDistributor__NoRoyaltiesDueForAddress();
        }
        
        // Decrease the total pool *before* sending
        _collectionERC20Royalties[collection][token] -= amountToDistribute;
        
        // Send the royalties
        token.safeTransfer(claimant, amountToDistribute);
        emit ERC20RoyaltyClaimed(collection, address(token), claimant, amountToDistribute, isMinter);
    }

    /**
     * @notice Check how much ETH royalties are due for an address in a collection based on current pool and shares.
     * @param collection The collection address
     * @param claimant The address to check
     * @return The amount of ETH royalties currently claimable by the address
     */
    function getRoyaltiesDueForAddress(address collection, address claimant) external view returns (uint256) {
        CollectionConfig storage config = _collectionConfigs[collection];
        if (!config.registered) {
             // Return 0 if collection not registered instead of reverting? Be consistent. Let's revert.
             revert RoyaltyDistributor__CollectionNotRegistered();
        }

        uint256 availableAmount = _collectionRoyalties[collection];
        if (availableAmount == 0) {
            return 0;
        }
        
        uint256 shareNumerator;
        if (claimant == config.creator) {
            shareNumerator = config.creatorShares;
        } else if (_minterCollectionTokens[claimant][collection].length > 0) {
            shareNumerator = config.minterShares;
        } else {
            return 0; // Not the creator and not a minter for this collection
        }
        
        return (availableAmount * shareNumerator) / SHARES_DENOMINATOR;
    }

    /**
     * @notice Check how much ERC20 royalties are due for an address in a collection for a specific token.
     * @param collection The collection address
     * @param claimant The address to check
     * @param token The ERC20 token address
     * @return The amount of ERC20 royalties currently claimable by the address for that token
     */
    function getERC20RoyaltiesDueForAddress(address collection, address claimant, IERC20 token) external view returns (uint256) {
        CollectionConfig storage config = _collectionConfigs[collection];
        if (!config.registered) {
             revert RoyaltyDistributor__CollectionNotRegistered();
        }

        uint256 availableAmount = _collectionERC20Royalties[collection][token];
        if (availableAmount == 0) {
            return 0;
        }
        
        uint256 shareNumerator;
        if (claimant == config.creator) {
            shareNumerator = config.creatorShares;
        } else if (_minterCollectionTokens[claimant][collection].length > 0) {
            shareNumerator = config.minterShares;
        } else {
            return 0; // Not the creator and not a minter for this collection
        }
        
        return (availableAmount * shareNumerator) / SHARES_DENOMINATOR;
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
}