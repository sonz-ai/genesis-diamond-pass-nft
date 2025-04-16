// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CentralizedRoyaltyDistributor
 * @author Custom implementation based on Limit Break, Inc. patterns
 * @notice A centralized royalty distributor that works with OpenSea's single address royalty model
 *         while maintaining the functionality to distribute royalties to minters and creators.
 */
contract CentralizedRoyaltyDistributor is ERC165, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using Address for address payable;

    error RoyaltyDistributor__CollectionNotRegistered();
    error RoyaltyDistributor__MinterCannotBeZeroAddress();
    error RoyaltyDistributor__MinterHasAlreadyBeenAssignedToTokenId();
    error RoyaltyDistributor__CreatorCannotBeZeroAddress();
    error RoyaltyDistributor__CreatorSharesCannotBeZero();
    error RoyaltyDistributor__MinterSharesCannotBeZero();
    error RoyaltyDistributor__RoyaltyFeeWillExceedSalePrice();
    error RoyaltyDistributor__CollectionAlreadyRegistered();
    error RoyaltyDistributor__NotEnoughEtherToDistributeForCollection();
    error RoyaltyDistributor__NotEnoughTokensToDistributeForCollection();
    error RoyaltyDistributor__ZeroAmountToDistribute();
    error RoyaltyDistributor__NoRoyaltiesDueForAddress();
    error RoyaltyDistributor__NotMinterOfAnyTokens();
    error RoyaltyDistributor__AddressNotMinterOrCreator();
    error RoyaltyDistributor__CallerIsNotContractOwner();
    error RoyaltyDistributor__MinterSharesCannotExceedCreatorShares();

    struct CollectionConfig {
        uint256 royaltyFeeNumerator;
        uint256 minterShares;
        uint256 creatorShares;
        address creator;
        bool registered;
    }

    struct TokenMinter {
        address minter;
        bool assigned;
    }

    // Token sales tracking
    struct SaleRecord {
        uint256 tokenId;
        uint256 salePrice;
        address collection;
    }
    
    // Struct to keep track of token info for a minter
    struct MinterTokenInfo {
        address collection;
        uint256 tokenId;
    }

    uint96 public constant FEE_DENOMINATOR = 10_000;

    // Mapping from collection address => collection configuration
    mapping(address => CollectionConfig) private _collectionConfigs;
    
    // Mapping from collection address => token ID => minter address
    mapping(address => mapping(uint256 => TokenMinter)) private _minters;
    
    // Mapping from minter address => all tokens they've minted (across all collections)
    mapping(address => MinterTokenInfo[]) private _minterTokens;
    
    // Mapping to check if a token has already been added for a minter (collection => tokenId => minter => bool)
    mapping(address => mapping(uint256 => mapping(address => bool))) private _tokenAddedForMinter;
    
    // Accumulated royalties (in ETH) for each collection
    mapping(address => uint256) private _collectionRoyalties;
    
    // Accumulated royalties (in ERC20 tokens) for each collection and token
    mapping(address => mapping(IERC20 => uint256)) private _collectionERC20Royalties;
    
    // Sales records for processing
    SaleRecord[] private _pendingSales;

    // Events
    event CollectionRegistered(address indexed collection, uint256 royaltyFeeNumerator, uint256 minterShares, uint256 creatorShares, address creator);
    event MinterAssigned(address indexed collection, uint256 indexed tokenId, address indexed minter);
    event RoyaltyReceived(address indexed sender, uint256 amount);
    event ERC20RoyaltyReceived(address indexed token, address indexed sender, uint256 amount);
    event RoyaltyDistributed(address indexed collection, address indexed receiver, uint256 amount, bool isMinter);
    event ERC20RoyaltyDistributed(address indexed collection, address indexed token, address indexed receiver, uint256 amount, bool isMinter);
    event SaleRecorded(address indexed collection, uint256 indexed tokenId, uint256 salePrice);

    /**
     * @notice Receive function to accept ETH payments
     */
    receive() external payable virtual {
        emit RoyaltyReceived(_msgSender(), msg.value);
    }

    /**
     * @notice Register a collection with this royalty distributor
     * @param collection The address of the collection to register
     * @param royaltyFeeNumerator The royalty fee numerator
     * @param minterShares The number of shares for minters
     * @param creatorShares The number of shares for creators
     * @param creator The creator address for the collection
     */
    function registerCollection(
        address collection,
        uint96 royaltyFeeNumerator,
        uint256 minterShares,
        uint256 creatorShares,
        address creator
    ) external onlyOwner {
        
        if(_collectionConfigs[collection].registered) {
            revert RoyaltyDistributor__CollectionAlreadyRegistered();
        }
        
        if(royaltyFeeNumerator > FEE_DENOMINATOR) {
            revert RoyaltyDistributor__RoyaltyFeeWillExceedSalePrice();
        }

        if (minterShares == 0) {
            revert RoyaltyDistributor__MinterSharesCannotBeZero();
        }

        if (creatorShares == 0) {
            revert RoyaltyDistributor__CreatorSharesCannotBeZero();
        }

        if (minterShares >= creatorShares) {
            revert RoyaltyDistributor__MinterSharesCannotExceedCreatorShares();
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
     * @return minterShares The minter shares
     * @return creatorShares The creator shares
     * @return creator The creator address
     */
    function getCollectionConfig(address collection) external view returns (
        uint256 royaltyFeeNumerator,
        uint256 minterShares,
        uint256 creatorShares,
        address creator
    ) {
        CollectionConfig memory config = _collectionConfigs[collection];
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
     * @param collection The collection address
     * @param tokenId The token ID
     * @param minter The minter address
     */
    function setTokenMinter(address collection, uint256 tokenId, address minter) external onlyOwner {
        if (!_collectionConfigs[collection].registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }

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
        
        // Add this token to the minter's list of tokens
        if (!_tokenAddedForMinter[collection][tokenId][minter]) {
            _minterTokens[minter].push(MinterTokenInfo({
                collection: collection,
                tokenId: tokenId
            }));
            _tokenAddedForMinter[collection][tokenId][minter] = true;
        }

        emit MinterAssigned(collection, tokenId, minter);
    }

    /**
     * @notice Get the minter of a token
     * @param collection The collection address
     * @param tokenId The token ID
     * @return The minter address
     */
    function getMinter(address collection, uint256 tokenId) external view returns (address) {
        return _minters[collection][tokenId].minter;
    }
    
    /**
     * @notice Get all tokens minted by a specific address across all collections
     * @param minter The minter address
     * @return An array of MinterTokenInfo containing collection addresses and token IDs
     */
    function getTokensByMinter(address minter) external view returns (MinterTokenInfo[] memory) {
        return _minterTokens[minter];
    }
    
    /**
     * @notice Get the number of tokens minted by a specific address
     * @param minter The minter address
     * @return The number of tokens minted
     */
    function getMinterTokenCount(address minter) external view returns (uint256) {
        return _minterTokens[minter].length;
    }

    /**
     * @notice Records a sale for future royalty distribution
     * @param collection The collection address
     * @param tokenId The token ID that was sold
     * @param salePrice The sale price
     */
    function recordSale(address collection, uint256 tokenId, uint256 salePrice) external onlyOwner {
        if (!_collectionConfigs[collection].registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }

        _pendingSales.push(SaleRecord({
            tokenId: tokenId,
            salePrice: salePrice,
            collection: collection
        }));

        emit SaleRecorded(collection, tokenId, salePrice);
    }

    /**
     * @notice Get the accumulated royalties for a collection (in ETH)
     * @param collection The collection address
     * @return The accumulated royalties
     */
    function getCollectionRoyalties(address collection) external view returns (uint256) {
        return _collectionRoyalties[collection];
    }

    /**
     * @notice Get the accumulated royalties for a collection (in ERC20)
     * @param collection The collection address
     * @param token The ERC20 token address
     * @return The accumulated royalties
     */
    function getCollectionERC20Royalties(address collection, IERC20 token) external view returns (uint256) {
        return _collectionERC20Royalties[collection][token];
    }

    /**
     * @notice Manually add ETH royalties for a collection
     * @param collection The collection address
     * @param amount The amount to add
     */
    function addCollectionRoyalties(address collection, uint256 amount) external payable {
        if (msg.value != amount) {
            revert("Invalid amount");
        }
        
        if (!_collectionConfigs[collection].registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }

        _collectionRoyalties[collection] += amount;
        emit RoyaltyReceived(_msgSender(), amount);
    }

    /**
     * @notice Manually add ERC20 royalties for a collection
     * @param collection The collection address
     * @param token The ERC20 token address
     * @param amount The amount to add
     */
    function addCollectionERC20Royalties(address collection, IERC20 token, uint256 amount) external {
        if (!_collectionConfigs[collection].registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }

        token.safeTransferFrom(_msgSender(), address(this), amount);
        _collectionERC20Royalties[collection][token] += amount;
        emit ERC20RoyaltyReceived(address(token), _msgSender(), amount);
    }

    /**
     * @notice Distribute ETH royalties for a specific token
     * @param collection The collection address
     * @param tokenId The token ID
     * @param amount The amount to distribute
     */
    function distributeRoyaltiesForToken(
        address collection,
        uint256 tokenId,
        uint256 amount
    ) external nonReentrant {
        if (!_collectionConfigs[collection].registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }

        if (_collectionRoyalties[collection] < amount) {
            revert RoyaltyDistributor__NotEnoughEtherToDistributeForCollection();
        }

        if (amount == 0) {
            revert RoyaltyDistributor__ZeroAmountToDistribute();
        }

        TokenMinter memory tokenMinter = _minters[collection][tokenId];
        if (!tokenMinter.assigned) {
            // If no minter is assigned, all royalties go to the creator
            address creator = _collectionConfigs[collection].creator;
            _collectionRoyalties[collection] -= amount;
            payable(creator).sendValue(amount);
            emit RoyaltyDistributed(collection, creator, amount, false);
        } else {
            // Split between minter and creator
            uint256 minterShares = _collectionConfigs[collection].minterShares;
            uint256 creatorShares = _collectionConfigs[collection].creatorShares;
            uint256 totalShares = minterShares + creatorShares;
            
            address minter = tokenMinter.minter;
            address creator = _collectionConfigs[collection].creator;
            
            uint256 minterAmount = (amount * minterShares) / totalShares;
            uint256 creatorAmount = amount - minterAmount;
            
            _collectionRoyalties[collection] -= amount;
            
            if (minterAmount > 0) {
                payable(minter).sendValue(minterAmount);
                emit RoyaltyDistributed(collection, minter, minterAmount, true);
            }
            
            if (creatorAmount > 0) {
                payable(creator).sendValue(creatorAmount);
                emit RoyaltyDistributed(collection, creator, creatorAmount, false);
            }
        }
    }

    /**
     * @notice Distribute ETH royalties for all tokens minted by a specific address in a collection
     * @param collection The collection address
     * @param recipient The address to distribute royalties to (must be a minter or creator)
     */
    function distributeAllRoyaltiesForMinter(
        address collection,
        address recipient
    ) external nonReentrant {
        if (!_collectionConfigs[collection].registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }

        uint256 availableAmount = _collectionRoyalties[collection];
        if (availableAmount == 0) {
            revert RoyaltyDistributor__ZeroAmountToDistribute();
        }
        
        address creator = _collectionConfigs[collection].creator;
        bool isMinter = false;
        uint256 minterTokenCount = 0;
        
        // Check if recipient is creator or minter
        if (recipient == creator) {
            // Recipient is the creator
            isMinter = false;
        } else {
            // Check if recipient is a minter
            for (uint256 i = 0; i < _minterTokens[recipient].length; i++) {
                if (_minterTokens[recipient][i].collection == collection) {
                    minterTokenCount++;
                }
            }
            
            if (minterTokenCount == 0) {
                revert RoyaltyDistributor__AddressNotMinterOrCreator();
            }
            
            isMinter = true;
        }
        
        // Get the creator and share configuration
        uint256 minterShares = _collectionConfigs[collection].minterShares;
        uint256 creatorShares = _collectionConfigs[collection].creatorShares;
        uint256 totalShares = minterShares + creatorShares;
        
        // Calculate amount based on recipient role
        uint256 amountToDistribute;
        if (isMinter) {
            amountToDistribute = (availableAmount * minterShares) / totalShares;
        } else {
            amountToDistribute = (availableAmount * creatorShares) / totalShares;
        }
        
        if (amountToDistribute == 0) {
            revert RoyaltyDistributor__NoRoyaltiesDueForAddress();
        }
        
        // Update the collection royalties
        _collectionRoyalties[collection] -= amountToDistribute;
        
        // Send the royalties
        payable(recipient).sendValue(amountToDistribute);
        emit RoyaltyDistributed(collection, recipient, amountToDistribute, isMinter);
    }

    /**
     * @notice Distribute all available ERC20 royalties for a specific minter in a collection
     * @param collection The collection address
     * @param recipient The address to distribute royalties to (must be a minter or creator)
     * @param token The ERC20 token address
     */
    function distributeAllERC20RoyaltiesForMinter(
        address collection,
        address recipient,
        IERC20 token
    ) external nonReentrant {
        if (!_collectionConfigs[collection].registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }

        uint256 availableAmount = _collectionERC20Royalties[collection][token];
        if (availableAmount == 0) {
            revert RoyaltyDistributor__ZeroAmountToDistribute();
        }
        
        address creator = _collectionConfigs[collection].creator;
        bool isMinter = false;
        uint256 minterTokenCount = 0;
        
        // Check if recipient is creator or minter
        if (recipient == creator) {
            // Recipient is the creator
            isMinter = false;
        } else {
            // Check if recipient is a minter
            for (uint256 i = 0; i < _minterTokens[recipient].length; i++) {
                if (_minterTokens[recipient][i].collection == collection) {
                    minterTokenCount++;
                }
            }
            
            if (minterTokenCount == 0) {
                revert RoyaltyDistributor__AddressNotMinterOrCreator();
            }
            
            isMinter = true;
        }
        
        // Get the creator and share configuration
        uint256 minterShares = _collectionConfigs[collection].minterShares;
        uint256 creatorShares = _collectionConfigs[collection].creatorShares;
        uint256 totalShares = minterShares + creatorShares;
        
        // Calculate amount based on recipient role
        uint256 amountToDistribute;
        if (isMinter) {
            amountToDistribute = (availableAmount * minterShares) / totalShares;
        } else {
            amountToDistribute = (availableAmount * creatorShares) / totalShares;
        }
        
        if (amountToDistribute == 0) {
            revert RoyaltyDistributor__NoRoyaltiesDueForAddress();
        }
        
        // Update the collection royalties
        _collectionERC20Royalties[collection][token] -= amountToDistribute;
        
        // Send the royalties
        token.safeTransfer(recipient, amountToDistribute);
        emit ERC20RoyaltyDistributed(collection, address(token), recipient, amountToDistribute, isMinter);
    }

    /**
     * @notice Check how much royalties are due for an address in a collection
     * @param collection The collection address
     * @param recipient The address to check
     * @return The amount of royalties due for the address
     */
    function getRoyaltiesDueForAddress(address collection, address recipient) external view returns (uint256) {
        if (!_collectionConfigs[collection].registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }

        uint256 availableAmount = _collectionRoyalties[collection];
        if (availableAmount == 0) {
            return 0;
        }
        
        address creator = _collectionConfigs[collection].creator;
        bool isMinter = false;
        
        // Check if recipient is creator or minter
        if (recipient == creator) {
            // Recipient is the creator
            isMinter = false;
        } else {
            // Check if recipient is a minter
            uint256 minterTokenCount = 0;
            for (uint256 i = 0; i < _minterTokens[recipient].length; i++) {
                if (_minterTokens[recipient][i].collection == collection) {
                    minterTokenCount++;
                }
            }
            
            if (minterTokenCount == 0) {
                return 0; // Not a minter of any tokens in this collection
            }
            
            isMinter = true;
        }
        
        // Get the creator and share configuration
        uint256 minterShares = _collectionConfigs[collection].minterShares;
        uint256 creatorShares = _collectionConfigs[collection].creatorShares;
        uint256 totalShares = minterShares + creatorShares;
        
        // Calculate amount based on recipient role
        if (isMinter) {
            return (availableAmount * minterShares) / totalShares;
        } else {
            return (availableAmount * creatorShares) / totalShares;
        }
    }

    /**
     * @notice Check how much ERC20 royalties are due for an address in a collection
     * @param collection The collection address
     * @param recipient The address to check
     * @param token The ERC20 token address
     * @return The amount of ERC20 royalties due for the address
     */
    function getERC20RoyaltiesDueForAddress(address collection, address recipient, IERC20 token) external view returns (uint256) {
        if (!_collectionConfigs[collection].registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }

        uint256 availableAmount = _collectionERC20Royalties[collection][token];
        if (availableAmount == 0) {
            return 0;
        }
        
        address creator = _collectionConfigs[collection].creator;
        bool isMinter = false;
        
        // Check if recipient is creator or minter
        if (recipient == creator) {
            // Recipient is the creator
            isMinter = false;
        } else {
            // Check if recipient is a minter
            uint256 minterTokenCount = 0;
            for (uint256 i = 0; i < _minterTokens[recipient].length; i++) {
                if (_minterTokens[recipient][i].collection == collection) {
                    minterTokenCount++;
                }
            }
            
            if (minterTokenCount == 0) {
                return 0; // Not a minter of any tokens in this collection
            }
            
            isMinter = true;
        }
        
        // Get the creator and share configuration
        uint256 minterShares = _collectionConfigs[collection].minterShares;
        uint256 creatorShares = _collectionConfigs[collection].creatorShares;
        uint256 totalShares = minterShares + creatorShares;
        
        // Calculate amount based on recipient role
        if (isMinter) {
            return (availableAmount * minterShares) / totalShares;
        } else {
            return (availableAmount * creatorShares) / totalShares;
        }
    }

    /**
     * @notice Distribute ETH royalties for all tokens in a collection
     * @param collection The collection address
     */
    function distributeAllRoyaltiesForCollection(address collection) external nonReentrant {
        if (!_collectionConfigs[collection].registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }

        uint256 amount = _collectionRoyalties[collection];
        if (amount == 0) {
            revert RoyaltyDistributor__ZeroAmountToDistribute();
        }

        // In the batch distribution, we simply send everything to the creator
        // This is a simpler approach for collection-wide royalties
        address creator = _collectionConfigs[collection].creator;
        _collectionRoyalties[collection] = 0;
        
        payable(creator).sendValue(amount);
        emit RoyaltyDistributed(collection, creator, amount, false);
    }

    /**
     * @notice Distribute ERC20 royalties for all tokens in a collection
     * @param collection The collection address
     * @param token The ERC20 token address
     */
    function distributeAllERC20RoyaltiesForCollection(address collection, IERC20 token) external nonReentrant {
        if (!_collectionConfigs[collection].registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }

        uint256 amount = _collectionERC20Royalties[collection][token];
        if (amount == 0) {
            revert RoyaltyDistributor__ZeroAmountToDistribute();
        }

        // In the batch distribution, we simply send everything to the creator
        address creator = _collectionConfigs[collection].creator;
        _collectionERC20Royalties[collection][token] = 0;
        
        token.safeTransfer(creator, amount);
        emit ERC20RoyaltyDistributed(collection, address(token), creator, amount, false);
    }

    /**
     * @dev Indicates whether the contract implements the specified interface.
     * @param interfaceId The interface id
     * @return true if the contract implements the specified interface, false otherwise
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }
}