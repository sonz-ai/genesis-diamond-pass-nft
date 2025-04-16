## Design Document: Diamond Genesis Pass Royalty System

**1. Introduction**

This document outlines the design of the royalty distribution system for the `DiamondGenesisPass` NFT collection. The primary goal is to enable royalty sharing between the original minter of an NFT and the collection creator, while ensuring compatibility with major NFT marketplaces (like OpenSea, MagicEden) that typically only support sending royalties to a single designated address. The system also incorporates distinct roles for contract ownership and service account operations.

**2. Core Problem**

Standard `IERC2981` implementations return a single recipient address for royalties. However, we want to split royalties based on secondary market sales:
*   **Minter:** Receives a share (e.g., 20%) of the royalty from the secondary sale of the specific token they originally minted.
*   **Creator:** Receives the remaining share (e.g., 80%) of the royalty.

Marketplaces do not natively support sending split royalties to multiple parties based on the specific token being sold. They typically send the full royalty amount specified by `IERC2981`'s `royaltyInfo` to the single `receiver` address returned by that function.

Primary mint payments need to be directed **solely to the creator/collection owner**, separate from the royalty distribution pool.

Additionally, after deployment, primary ownership needs to be transferred to a secure entity (like a multisig), while allowing a separate, less privileged service account to perform routine operational tasks.

**3. Proposed Solution: Centralized Distributor Pattern with Dual Access Control**

We address this using a three-contract system with a refined access control model:

*   **`DiamondGenesisPass.sol` (NFT Contract):**
    *   The main ERC721 contract representing the NFTs.
    *   Implements `IERC2981` (`royaltyInfo`), directing marketplace royalties to the `CentralizedRoyaltyDistributor`.
    *   Uses **OpenZeppelin's `Ownable`** for primary contract ownership (e.g., setting Merkle root, public mint status, burning tokens). The `owner()` will typically be a multisig post-deployment and will receive primary mint payments.
    *   Uses **OpenZeppelin's `AccessControl`** to define a `SERVICE_ACCOUNT_ROLE` for delegated tasks (e.g., owner minting). This role is managed by the `DEFAULT_ADMIN_ROLE`, which should be granted to the `owner()`.
    *   **Key Responsibility:** Manages NFT logic, directs secondary market royalties via `royaltyInfo`, records minters with the distributor, **forwards primary mint payments (`msg.value`) directly to the current `owner()` address**, and enforces distinct permissions for Owner and Service Account roles.

*   **`CentralizedRoyaltyAdapter.sol` (Pattern Contract - Implemented by DiamondGenesisPass):**
    *   Defines the standard interface and logic for an NFT contract to interact with the `CentralizedRoyaltyDistributor`.
    *   Provides the `royaltyInfo` implementation pointing to the distributor.
    *   Includes helper views to query the distributor.

*   **`CentralizedRoyaltyDistributor.sol` (Distribution Hub):**
    *   The single address designated to receive all royalty payments from marketplaces for registered collections.
    *   Uses **OpenZeppelin's `AccessControl`** for role management:
        *   `DEFAULT_ADMIN_ROLE`: Controls core functions like registering new collections and setting oracle parameters.
        *   `SERVICE_ACCOUNT_ROLE`: Can perform specific actions like submitting royalty data (`batchUpdateRoyaltyData`) and submitting Merkle roots (`submitRoyaltyMerkleRoot`).
    *   **Key Responsibilities:**
        *   Stores configuration per collection (royalty fee, minter/creator shares, creator address).
        *   Tracks the original minter for every `tokenId` within each registered collection.
        *   Accumulates received royalty funds (ETH and potentially ERC20) per collection **only from marketplace payments via its `receive()` function**.
        *   Provides functions (`claimRoyaltiesMerkle`) for minters and creators to withdraw their respective shares based on submitted Merkle proofs.
        *   Allows admins or service accounts to record processed sale details (`batchUpdateRoyaltyData`) to update internal royalty accounting.
        *   Allows service accounts to submit Merkle roots (`submitRoyaltyMerkleRoot`) representing claimable royalties.

**4. System Flow**

1.  **Deployment & Setup:**
    *   Deploy `CentralizedRoyaltyDistributor`. The deployer gets `DEFAULT_ADMIN_ROLE` and `SERVICE_ACCOUNT_ROLE`.
    *   Deploy `DiamondGenesisPass`, passing the `CentralizedRoyaltyDistributor` address, the overall royalty percentage (`royaltyFeeNumerator`), and the creator's address. The deployer becomes the `owner()` (from `Ownable`) and also gets `DEFAULT_ADMIN_ROLE` and `SERVICE_ACCOUNT_ROLE` (from `AccessControl`) on this contract.
    *   The `DiamondGenesisPass` deployer (who needs `DEFAULT_ADMIN_ROLE` on the distributor) calls `registerCollection` on the `CentralizedRoyaltyDistributor` via the `DiamondGenesisPass` constructor.
    *   The `owner()` of `DiamondGenesisPass` configures the contract (sets Merkle root, opens claim period, enables public mint).
    *   The `owner()` of `DiamondGenesisPass` transfers ownership (`transferOwnership`) to the company multisig.
    *   The multisig (now owner) grants `DEFAULT_ADMIN_ROLE` on `DiamondGenesisPass` to itself (if not already the deployer).
    *   The multisig (now owner and admin) grants `SERVICE_ACCOUNT_ROLE` on `DiamondGenesisPass` to the designated service account address.
    *   The admin of `CentralizedRoyaltyDistributor` grants `SERVICE_ACCOUNT_ROLE` on the distributor to the designated service account address.

2.  **Minting:**
    *   A user calls `whitelistMint` or `mint` on `DiamondGenesisPass`.
    *   The `DiamondGenesisPass` contract **transfers the payment (`msg.value`) directly to its current `owner()` address.** (e.g., using `payable(owner()).transfer(msg.value)` or a safe equivalent).
    *   The `_mint` function within `DiamondGenesisPass` calls `centralizedDistributor.setTokenMinter(address(this), tokenId, to)` to record the minter. **Requires `setTokenMinter` to check `msg.sender == collection`**.

3.  **Secondary Sale & Royalty Payment:**
    *   A user sells a `DiamondGenesisPass` NFT (e.g., Token ID 123) on a marketplace (e.g., OpenSea).
    *   The marketplace detects the sale and checks the `royaltyInfo` for Token ID 123 on the `DiamondGenesisPass` contract.
    *   `DiamondGenesisPass.royaltyInfo` returns the address of the `CentralizedRoyaltyDistributor` as the `receiver` and calculates the total royalty amount (e.g., 7.5% of sale price).
    *   The marketplace sends the full calculated royalty amount (ETH) to the `CentralizedRoyaltyDistributor` contract address.

4.  **Royalty Accumulation:**
    *   The `CentralizedRoyaltyDistributor` receives ETH via its `receive()` function from direct marketplace royalty payments.
    *   The contract internally increments the balance tracked for the `DiamondGenesisPass` collection address (`_collectionRoyalties[address(DiamondGenesisPass)] += msg.value`). **Note: `msg.value` is used here as `receive()` gets it directly.**

5.  **Royalty Data Processing & Merkle Root Submission:**
    *   **Off-Chain Processing:** An off-chain service monitors `Transfer` events, fetches sale prices from marketplaces, calculates royalty shares (minter/creator) based on the `_collectionConfigs`, and aggregates total unpaid royalties for each minter and the creator for a specific period.
    *   **Batch Update:** The service account calls `batchUpdateRoyaltyData` on `CentralizedRoyaltyDistributor`, providing details for multiple sales. This function (restricted to `SERVICE_ACCOUNT_ROLE` or `DEFAULT_ADMIN_ROLE`) updates internal accounting (`TokenRoyaltyData`) for *earned* royalties and emits detailed `RoyaltyAttributed` events for transparency. **This function does not directly distribute funds.**
    *   **Merkle Tree Generation:** The off-chain service constructs a Merkle tree where each leaf is `keccak256(abi.encodePacked(recipient_address, total_unpaid_amount))`. `recipient_address` is either a minter or the collection's creator address. `total_unpaid_amount` is the cumulative royalty amount owed to that recipient *up to this point* that hasn't been included in a previous claimable root.
    *   **Root Submission:** The service account calls `submitRoyaltyMerkleRoot(bytes32 merkleRoot, uint256 totalAmountInTree)` on the distributor. This stores the `merkleRoot` as the active one for the collection, replacing any previous root. The function verifies the caller has `SERVICE_ACCOUNT_ROLE` and checks that `totalAmountInTree` does not exceed the available balance in the distributor for this collection. It emits a `MerkleRootSubmitted` event.

6.  **Royalty Claiming (Merkle Proof):**
    *   Minters and the creator call the public `claimRoyaltiesMerkle(address recipient, uint256 amount, bytes32[] calldata merkleProof)` function on the distributor.
    *   The function verifies the provided `merkleProof` against the currently active `merkleRoot` for the collection, ensuring the leaf `keccak256(abi.encodePacked(recipient, amount))` is valid.
    *   It checks that the `recipient` hasn't already claimed against this specific `merkleRoot`.
    *   If valid, it transfers the `amount` ETH to the `recipient` and marks the claim as processed for that `recipient` and `merkleRoot`. It emits a `MerkleRoyaltyClaimed` event.

**5. Contract Details & Rationale**

*   **`DiamondGenesisPass`:** Standard ERC721 features plus minting logic. Integrates `CentralizedRoyaltyAdapter`. Uses `Ownable` for core ownership (multisig) and `AccessControl` for `SERVICE_ACCOUNT_ROLE`. Forwards mint payments directly to the `owner()` address. Uses modifiers `onlyOwner` and `onlyOwnerOrServiceAccount`. `_requireCallerIsContractOwner` uses the `owner()` check for `MetadataURI` compatibility.

*   **`CentralizedRoyaltyDistributor`:**
    *   Uses `AccessControl` for `DEFAULT_ADMIN_ROLE` (managing collections, oracle settings) and `SERVICE_ACCOUNT_ROLE` (submitting data/Merkle roots).
    *   `_collectionConfigs`, `_minters`, `_minterCollectionTokens`, `_collectionRoyalties`, `_collectionERC20Royalties`: Core state variables. `_collectionRoyalties` tracks total ETH received via `receive()`.
    *   **Merkle Claim State:**
        *   `mapping(address => bytes32) private _activeMerkleRoots; // collection => root`
        *   `mapping(bytes32 => mapping(address => bool)) private _hasClaimedMerkle; // root => recipient => bool`
        *   (Optional: `mapping(bytes32 => uint256) private _merkleRootTotalAmount; // root => totalAmount`)
    *   **(New Sale Tracking Components section mostly unchanged, relates to future price discovery)**
    *   **Access Control Functions:** Uses standard `AccessControl` functions.
    *   **Key Functions:**
        *   `registerCollection`: `onlyRole(DEFAULT_ADMIN_ROLE)`.
        *   `setTokenMinter`: **`onlyCollection(collection)` - callable only by the registered NFT contract address.**
        *   `batchUpdateRoyaltyData`: Requires `DEFAULT_ADMIN_ROLE` or `SERVICE_ACCOUNT_ROLE`. Updates internal earned amounts, emits `RoyaltyAttributed`.
        *   `submitRoyaltyMerkleRoot`: Requires `SERVICE_ACCOUNT_ROLE`. Stores Merkle root, checks balance, emits `MerkleRootSubmitted`.
        *   `claimRoyaltiesMerkle`: Publicly callable. Verifies Merkle proof, checks for prior claims, transfers funds, emits `MerkleRoyaltyClaimed`.
        *   `setOracleUpdateMinBlockInterval`: `onlyRole(DEFAULT_ADMIN_ROLE)`.
        *   `updateRoyaltyDataViaOracle`: Public, but rate-limited.
        *   **(Price Discovery/Oracle functions unchanged, except `fulfillRoyaltyData` should align with `batchUpdateRoyaltyData` logic)**
        *   **Removed:** `recordSaleRoyalty`, `recordERC20Royalty`, `claimRoyalties`, `claimERC20Royalties`, `addCollectionRoyalties`.

**6. Security Considerations & Trust Assumptions**

*   **Distributor Security:** The `CentralizedRoyaltyDistributor` holds funds. It must be secure, non-reentrant (`ReentrancyGuard` is used), and ideally audited.
*   **Owner Privileges (`DiamondGenesisPass`):** The `owner()` (multisig) controls critical settings and the `treasuryAddress`.
*   **Admin Privileges (`AccessControl`):** The `DEFAULT_ADMIN_ROLE` holder (initially deployer, ideally transferred to owner/multisig) manages roles (`SERVICE_ACCOUNT_ROLE`) on both contracts.
*   **Service Account Permissions:** The `SERVICE_ACCOUNT_ROLE` has limited permissions (submitting data, submitting Merkle roots). If compromised, it cannot change core settings or steal funds directly, but could submit incorrect data/roots, potentially preventing or delaying legitimate claims until corrected by an Admin. Requires trust in the off-chain service operator.
*   **Merkle Root Integrity:** Users trust the off-chain service to generate correct Merkle roots that include all owed royalties. An incorrect root could prevent claims. The balance check in `submitRoyaltyMerkleRoot` provides a basic safeguard against promising more funds than available.
*   **Distribution Trust:** Users trust the distributor's Merkle claim logic and fund availability.
*   **Price Accuracy:** Users must trust the off-chain service accurately determines sale prices for calculating earned amounts in `batchUpdateRoyaltyData`.
*   **Oracle Security:** The implementation of Chainlink oracles introduces additional security considerations related to the off-chain data source and oracle nodes.
*   **Gas Costs:** Claiming royalties via `claimRoyaltiesMerkle` is significantly cheaper per user than individual tracking/claims, as the main computation is off-chain. `batchUpdateRoyaltyData` and `submitRoyaltyMerkleRoot` still incur costs, borne by the service operator.

**7. Off-Chain Components**

*   **Transfer Monitoring Service:** An off-chain service that listens for transfer events from the `DiamondGenesisPass` contract and calls `recordTransfer` on the distributor.
*   **Batch Price Discovery & Royalty Service:** A service that:
    *   Monitors `Transfer` events.
    *   Collects price data from marketplace APIs.
    *   Calculates royalty shares based on sale prices and collection configuration.
    *   Calls `batchUpdateRoyaltyData` to record earned amounts and emit attribution events.
    *   Periodically (e.g., daily/weekly) calculates cumulative unpaid royalties for *all* minters and the creator.
    *   Constructs the Merkle tree of claimable balances.
    *   Calls `submitRoyaltyMerkleRoot` with the new root and total amount.
*   **Oracle Implementation:** A Chainlink oracle adapter that connects the off-chain price discovery service to the on-chain distributor contract.
*   **Administrative Dashboard:** A UI for the contract owner to monitor transfers, add/remove service accounts, and manage the distribution system.

**8. Royalty Collection Process**

This section details the updated flow incorporating the Merkle distributor for claims.

*   **Marketplace Royalty Flow:**
    *   (Unchanged) Marketplaces send royalty via `royaltyInfo` to the distributor's `receive()` function.
    *   Funds accumulate in `_collectionRoyalties[collection]`.

*   **Transaction Tracking & Data Attribution:**
    *   (Unchanged) The contract emits `Transfer` events. Off-chain service monitors them.
    *   The contract tracks key data per tokenId (`TokenRoyaltyData`) and collection (`CollectionRoyaltyData`). **Note:** Remove `minterRoyaltyPaid`, `creatorRoyaltyPaid`, `totalRoyaltyDistributed` from these structs. Keep `minterRoyaltyEarned`, `creatorRoyaltyEarned`, `totalRoyaltyCollected`.
        ```solidity
        struct TokenRoyaltyData {
            address minter;               // Original minter address
            address currentOwner;         // Current owner address
            uint256 transactionCount;     // Number of times the token has been traded
            uint256 totalVolume;          // Cumulative trading volume
            uint256 lastSyncedBlock;      // Latest block height when royalty data was updated
            uint256 minterRoyaltyEarned;  // Total royalties earned by minter (updated by batchUpdate)
            // uint256 minterRoyaltyPaid;    // REMOVED - Handled by Merkle claims
            uint256 creatorRoyaltyEarned; // Total royalties earned by creator for this token (updated by batchUpdate)
            // uint256 creatorRoyaltyPaid;   // REMOVED - Handled by Merkle claims
            mapping(bytes32 => bool) processedTransactions; // Hash map to prevent duplicate processing
        }

        struct CollectionRoyaltyData {
            uint256 totalVolume;          // Total volume across all tokens
            uint256 lastSyncedBlock;      // Latest sync block for the collection
            uint256 totalRoyaltyCollected; // Total royalties received via receive()
            // uint256 totalRoyaltyDistributed; // REMOVED - Handled by Merkle claims
        }
        ```
    *   The off-chain processor calls `batchUpdateRoyaltyData` after fetching prices:
        ```solidity
        // Still restricted: onlyRole(SERVICE_ACCOUNT_ROLE) or DEFAULT_ADMIN_ROLE
        function batchUpdateRoyaltyData(
            address collection,
            uint256[] calldata tokenIds,
            address[] calldata minters, // Added: Need minter address for attribution
            address creator,          // Added: Need creator address
            uint256[] calldata salePrices,
            uint256[] calldata transactionTimestamps,
            bytes32[] calldata transactionHashes
        ) external /* restricted */ {
            // ... verification logic ...
            // For each sale:
            // 1. Calculate minterShareAmount and creatorShareAmount based on salePrice and collection config
            // 2. Update tokenData[tokenId].minterRoyaltyEarned += minterShareAmount;
            // 3. Update tokenData[tokenId].creatorRoyaltyEarned += creatorShareAmount;
            // 4. Mark transactionHash as processed
            // 5. Emit RoyaltyAttributed event
            // ... update collection lastSyncedBlock ...
        }

        // Event emitted for each processed sale within batchUpdateRoyaltyData
        event RoyaltyAttributed(
            address indexed collection,
            uint256 indexed tokenId,
            address indexed minter,
            uint256 salePrice,
            uint256 minterShareAttributed, // Amount added to minter's earned balance for this sale
            uint256 creatorShareAttributed, // Amount added to creator's earned balance for this sale
            bytes32 indexed transactionHash // Original transaction hash
        );
        ```
    *   This function only updates *internal accounting* of earned amounts; it does not transfer ETH.

*   **Royalty Distribution & Claim Process (Merkle Distributor):**
    *   **Merkle Root Generation (Off-Chain):** Periodically, the service queries the distributor (e.g., via helper views or its own database) to get the total `RoyaltyEarned` for each minter and the creator for the given collection. It calculates the *unpaid* amount for each recipient (Total Earned - Total Included in Previous Roots). It constructs the Merkle tree based on `keccak256(abi.encodePacked(recipient, unpaid_amount))`.
    *   **Root Submission (On-Chain):** The service calls `submitRoyaltyMerkleRoot(merkleRoot, totalAmountInTree)` on the distributor.
        ```solidity
        // Restricted: onlyRole(SERVICE_ACCOUNT_ROLE)
        function submitRoyaltyMerkleRoot(address collection, bytes32 merkleRoot, uint256 totalAmountInTree) external /* restricted */ {
            // require(hasRole(SERVICE_ACCOUNT_ROLE, msg.sender), "Caller needs service role");
            // require(totalAmountInTree <= availableBalanceForCollection(collection), "Insufficient balance for root");
            _activeMerkleRoots[collection] = merkleRoot;
            // Optional: store more details about the root
            emit MerkleRootSubmitted(collection, merkleRoot, totalAmountInTree, block.timestamp);
        }

        event MerkleRootSubmitted(
            address indexed collection,
            bytes32 indexed merkleRoot,
            uint256 totalAmountInTree,
            uint256 timestamp
        );
        ```
    *   **Claiming (On-Chain):** Users (minters/creator) call `claimRoyaltiesMerkle`.
        ```solidity
        function claimRoyaltiesMerkle(
            address collection, // Specify collection for clarity
            address recipient, // Often msg.sender, but allows claiming for others if needed
            uint256 amount,
            bytes32[] calldata merkleProof
        ) external {
            bytes32 activeRoot = _activeMerkleRoots[collection];
            require(activeRoot != bytes32(0), "No active Merkle root");
            require(!_hasClaimedMerkle[activeRoot][recipient], "Already claimed for this root");

            bytes32 leaf = keccak256(abi.encodePacked(recipient, amount));
            require(MerkleProof.verify(merkleProof, activeRoot, leaf), "Invalid proof");

            _hasClaimedMerkle[activeRoot][recipient] = true;
            // Transfer ETH
            (bool success, ) = recipient.call{value: amount}("");
            require(success, "Transfer failed");

            emit MerkleRoyaltyClaimed(recipient, amount, activeRoot, collection);
        }

        event MerkleRoyaltyClaimed(
            address indexed recipient,
            uint256 amount,
            bytes32 indexed merkleRoot,
            address indexed collection
        );
        ```
    *   View functions allow users/UI to check the active root and claim status.

*   **Oracle-Based Synchronization (Alternative/Backup):**
    *   Any user can trigger royalty data updates (`batchUpdateRoyaltyData` logic) through the public oracle function:
       ```solidity
       // State variables for rate limiting
       mapping(address => uint256) private _lastOracleUpdateBlock; // collection => block number
       mapping(address => uint256) private _oracleUpdateMinBlockInterval; // collection => block interval

       // Function for admin to set interval
       function setOracleUpdateMinBlockInterval(address collection, uint256 interval) external onlyRole(DEFAULT_ADMIN_ROLE) {
            _oracleUpdateMinBlockInterval[collection] = interval;
       }

       function updateRoyaltyDataViaOracle(address collection) external {
           // Rate Limiting Check
           uint256 minInterval = _oracleUpdateMinBlockInterval[collection];
           require(block.number >= _lastOracleUpdateBlock[collection] + minInterval, "Oracle update called too soon");

           _lastOracleUpdateBlock[collection] = block.number; // Update timestamp before external call

           // ... build and send Chainlink request ...
           // Request should target an endpoint that provides data similar to batchUpdateRoyaltyData input
           // req.add("collection", addressToString(collection));
           // req.add("fromBlock", uint256ToString(CollectionRoyaltyData[collection].lastSyncedBlock));
           // ... sendOperatorRequest ...
       }
       ```
    *   The callback function `fulfillRoyaltyData` (called by Chainlink node) processes the response and effectively performs the same logic as `batchUpdateRoyaltyData`, updating earned amounts and emitting `RoyaltyAttributed` events. It must also be permissioned (`recordChainlinkFulfillment`).
        ```solidity
           // Called by Chainlink Node
           function fulfillRoyaltyData(
               bytes32 _requestId,
               address collection, // Need collection identifier
               // ... data arrays similar to batchUpdateRoyaltyData ...
           ) external recordChainlinkFulfillment(_requestId) {
               // ... process data, update earned royalties, emit RoyaltyAttributed events ...
               // This performs the *attribution* step, not distribution.
           }
        ```

*   **Anti-Duplication Safeguards:**
    *   (Unchanged) `processedTransactions` mapping in `TokenRoyaltyData` prevents reprocessing the same sale in `batchUpdateRoyaltyData` or `fulfillRoyaltyData`.
    *   Merkle claim logic (`_hasClaimedMerkle`) prevents duplicate withdrawals for the *same* root. The off-chain service must ensure subsequent roots correctly account for already claimed amounts if using a cumulative model.

*   **User Interface for Royalty Tracking:**
    *   A dedicated dashboard will be provided for minters and the creator to:
        1. View their total *earned* royalties (from `TokenRoyaltyData`).
        2. See the currently active Merkle root for the collection.
        3. Check if they have already claimed against the active root.
        4. Generate the necessary proof (off-chain helper) and initiate claims via `claimRoyaltiesMerkle`.
        5. View historical claims (by querying `MerkleRoyaltyClaimed` events).

**9. Future Considerations / Potential Improvements**

*   **Marketplace Integration:** Explore direct integrations with major marketplaces via their APIs to automate price discovery.
*   **Gas Optimization:** Optimize batch operations like `batchUpdateSalePrices` to handle larger sets of transactions while minimizing gas costs.
*   **Enhanced Access Control:** Consider implementing a more granular RBAC (Role-Based Access Control) system to restrict specific functions to specific service accounts.
*   **Transaction Indexing:** Implement more sophisticated indexing methods to quickly locate missing price data for efficient batch updates.
*   **Oracle Redundancy:** Use multiple oracle providers or data sources to ensure reliability of off-chain price information.
*   **ERC20 Royalties:** The system includes handling for ERC20 royalties, which adds flexibility but also complexity if multiple royalty tokens are expected.
*   **On-Chain Price Verification:** Research potential methods to verify sale prices on-chain without relying solely on off-chain services.
*   **Restricting `setTokenMinter`:** Done. Modify `setTokenMinter` in the distributor to only be callable by the registered `collection` address.
*   **Role Management:** (Unchanged Importance)
*   **Distributor Permissions:** `batchUpdateRoyaltyData` relies on the service account for correct data to update *earned* amounts. `submitRoyaltyMerkleRoot` relies on the service account for correct *claimable* amounts/tree. Trust is placed in the service operator.
*   Consider if `DEFAULT_ADMIN_ROLE` on `DiamondGenesisPass` should strictly be the `owner()` (Unchanged recommendation).
*   **Mint Revenue Distribution:** Explicitly separated. Mint revenue (`msg.value` from minting functions) goes directly to the `owner()` of the `DiamondGenesisPass` contract. Only secondary market royalties flow into the distributor for splitting via Merkle claims.
*   **Merkle Root Management:** The off-chain service must carefully manage how roots are generated (e.g., cumulative unpaid vs. periodic). The current on-chain design assumes only the latest root is active for claims. Define recovery procedures if a bad root is submitted.
*   **Gas Optimization:** Achieved significantly for claims using the Merkle distributor pattern. Batch updates (`batchUpdateRoyaltyData`) remain potentially costly but are handled by the service operator.
*   **Enhanced Access Control:** `setTokenMinter` restricted to the collection contract. Clear roles for Admin (`DEFAULT_ADMIN_ROLE`) and Service (`SERVICE_ACCOUNT_ROLE`).
