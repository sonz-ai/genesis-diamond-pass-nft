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

**3. Implemented Solution: Centralized Distributor Pattern with Merkle Claims**

Our solution uses a three-contract system with refined access control:

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
    *   Minters and the creator call the public `claimRoyaltiesMerkle(address collection, address recipient, uint256 amount, bytes32[] calldata merkleProof)` function on the distributor.
    *   The function verifies the provided `merkleProof` against the currently active `merkleRoot` for the collection, ensuring the leaf `keccak256(abi.encodePacked(recipient, amount))` is valid.
    *   It checks that the `recipient` hasn't already claimed against this specific `merkleRoot`.
    *   If valid, it transfers the `amount` ETH to the `recipient` and marks the claim as processed for that `recipient` and `merkleRoot`. It emits a `MerkleRoyaltyClaimed` event.

**5. Contract Details & Implementation**

*   **`DiamondGenesisPass`:** Standard ERC721 features plus minting logic. Integrates `CentralizedRoyaltyAdapter`. Uses `Ownable` for core ownership (multisig) and `AccessControl` for `SERVICE_ACCOUNT_ROLE`. Forwards mint payments directly to the `owner()` address. Uses modifiers `onlyOwner` and `onlyOwnerOrServiceAccount`. `_requireCallerIsContractOwner` uses the `owner()` check for `MetadataURI` compatibility.

*   **`CentralizedRoyaltyDistributor`:**
    *   Uses `AccessControl` for `DEFAULT_ADMIN_ROLE` (managing collections, oracle settings) and `SERVICE_ACCOUNT_ROLE` (submitting data/Merkle roots).
    *   **State Variables:**
        *   `_collectionConfigs`: Maps collection address to configuration (royalty fee, shares, creator)
        *   `_minters`: Maps collection + token ID to minter address 
        *   `_minterCollectionTokens`: Maps minter + collection to token IDs minted
        *   `_collectionRoyalties`: Tracks ETH received per collection
        *   `_collectionERC20Royalties`: Tracks ERC20 tokens received per collection
        *   `_activeMerkleRoots`: Maps collection to current active Merkle root
        *   `_hasClaimedMerkle`: Tracks if an address has claimed against a Merkle root
        *   `_tokenRoyaltyData`: Tracks royalty data per token (minter, volume, royalties earned)
        *   `_collectionRoyaltyData`: Tracks collection-level royalty data
        *   `_lastOracleUpdateBlock` and `_oracleUpdateMinBlockInterval`: For oracle rate limiting
    *   **Key Functions:**
        *   `registerCollection`: Registers a collection with royalty configuration (`onlyRole(DEFAULT_ADMIN_ROLE)`)
        *   `setTokenMinter`: Records the minter for a token (`onlyCollection(collection)`)
        *   `batchUpdateRoyaltyData`: Processes sale data and attributes royalties internally (`onlyRole(SERVICE_ACCOUNT_ROLE)` or `DEFAULT_ADMIN_ROLE`)
        *   `submitRoyaltyMerkleRoot`: Submits a Merkle root for claims (`onlyRole(SERVICE_ACCOUNT_ROLE)`)
        *   `claimRoyaltiesMerkle`: Verifies Merkle proof and sends funds (public, nonReentrant)
        *   `updateRoyaltyDataViaOracle`: Triggers oracle update (public, rate-limited)
        *   `setOracleUpdateMinBlockInterval`: Sets rate limit for oracle updates (`onlyRole(DEFAULT_ADMIN_ROLE)`)
        *   `addCollectionRoyalties`/`addCollectionERC20Royalties`: Manually add royalties to a collection
        *   `fulfillRoyaltyData`: Chainlink callback (planned but not yet fully implemented)
    *   **Key Events:**
        *   `RoyaltyAttributed`: Emitted when royalties are attributed internally
        *   `MerkleRootSubmitted`: Emitted when a new Merkle root is submitted
        *   `MerkleRoyaltyClaimed`: Emitted when a claim is processed
        *   `RoyaltyReceived`/`ERC20RoyaltyReceived`: Emitted when royalties are received

**8. On-Chain Analytics**

*   **On-Chain Metrics (Totals Only):**
    *   `uint256 public totalAccruedRoyalty;` // total royalties accrued across all recipients
    *   `uint256 public totalClaimedRoyalty;` // total royalties claimed across all recipients

*   **Contract Modifications:**
    *   In `submitRoyaltyMerkleRoot`, update:
        ```solidity
        totalAccruedRoyalty += totalAmountInTree;
        ```
    *   In `claimRoyaltiesMerkle`, update:
        ```solidity
        totalClaimedRoyalty += amount;
        ```

*   **View Functions (gas-free external calls):**
    *   `function totalAccrued() external view returns (uint256) { return totalAccruedRoyalty; }`
    *   `function totalClaimed() external view returns (uint256) { return totalClaimedRoyalty; }`
    *   _Per-recipient analytics are derived off-chain via emitted events (MerkleRootSubmitted, MerkleRoyaltyClaimed, RoyaltyAttributed)._  
    *   **Off-Chain Analytics Workflow:**
        - **Events:** `RoyaltyAttributed`, `MerkleRootSubmitted`, `MerkleRoyaltyClaimed`
        - **Indexing:** Use The Graph or a custom service to subscribe to these events and maintain per-recipient `accrued`, `claimed`, and `unclaimed` balances off-chain.
        - **Data Access:** Expose GraphQL/REST endpoints or a dApp front-end for querying real-time per-user metrics based on the indexed data.

**6. Security Considerations & Risk Mitigations**

*   **Distributor Security:** The `CentralizedRoyaltyDistributor` holds funds. It uses `ReentrancyGuard` for claim functions and checks fund availability before submissions/claims.
*   **Owner Privileges:** The `owner()` (multisig) controls critical settings and receives mint proceeds.
*   **Admin Privileges:** The `DEFAULT_ADMIN_ROLE` holder (ideally the owner/multisig) manages collections and roles.
*   **Service Account Permissions:** The `SERVICE_ACCOUNT_ROLE` has limited permissions (submitting data, submitting Merkle roots). If compromised, it cannot change core settings or steal funds directly, but could submit incorrect data/roots, potentially preventing or delaying legitimate claims until corrected by an Admin. Requires trust in the off-chain service operator.
*   **Merkle Root Integrity:** Users trust the off-chain service to generate correct Merkle roots that include all owed royalties. The balance check in `submitRoyaltyMerkleRoot` provides a basic safeguard against promising more funds than available.
*   **Distribution Trust:** Users trust the distributor's Merkle claim logic and fund availability.
*   **Price Accuracy:** Users trust the off-chain service accurately determines sale prices for calculating earned amounts in `batchUpdateRoyaltyData`.
*   **Oracle Security:** The implementation includes rate limiting for oracle updates to prevent abuse. Oracle fulfillment should be restricted to the oracle node.
*   **Gas Costs:** Claiming royalties via `claimRoyaltiesMerkle` is significantly cheaper per user than individual tracking/claims, as the main computation is off-chain. `batchUpdateRoyaltyData` and `submitRoyaltyMerkleRoot` still incur costs, borne by the service operator.

**7. Off-Chain Components**

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
*   **User Claim Interface:** A UI for minters and creators to check their earned royalties and generate the Merkle proofs needed to claim.

**9. Royalty Data Collection & Claims Process**

*   **Collection-level Data Structure:**
    ```solidity
    struct CollectionRoyaltyData {
        uint256 totalVolume;          // Total volume across all tokens
        uint256 lastSyncedBlock;      // Latest sync block for the collection
        uint256 totalRoyaltyCollected; // Total royalties received via receive()
    }
    ```

*   **Token-level Data Structure:**
    ```solidity
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
    ```

*   **Batch Update Process:**
    ```solidity
    function batchUpdateRoyaltyData(
        address collection,
        uint256[] calldata tokenIds,
        address[] calldata minters,
        address creator,
        uint256[] calldata salePrices,
        uint256[] calldata transactionTimestamps,
        bytes32[] calldata transactionHashes
    ) external /* restricted */ {
        // For each sale:
        // 1. Calculate minterShareAmount and creatorShareAmount based on salePrice and collection config
        // 2. Update tokenData[tokenId].minterRoyaltyEarned += minterShareAmount;
        // 3. Update tokenData[tokenId].creatorRoyaltyEarned += creatorShareAmount;
        // 4. Mark transactionHash as processed
        // 5. Emit RoyaltyAttributed event
    }
    ```

*   **Merkle Root Submission Process:**
    ```solidity
    function submitRoyaltyMerkleRoot(
        address collection, 
        bytes32 merkleRoot, 
        uint256 totalAmountInTree
    ) external onlyRole(SERVICE_ACCOUNT_ROLE) {
        // Verify caller and check balance sufficiency
        _activeMerkleRoots[collection] = merkleRoot;
        _merkleRootTotalAmount[merkleRoot] = totalAmountInTree;
        _merkleRootSubmissionTime[merkleRoot] = block.timestamp;
        emit MerkleRootSubmitted(collection, merkleRoot, totalAmountInTree, block.timestamp);
    }
    ```

*   **Claim Process:**
    ```solidity
    function claimRoyaltiesMerkle(
        address collection,
        address recipient,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external nonReentrant {
        // Verify proof against active root
        // Check not already claimed
        // Mark as claimed
        // Transfer ETH to recipient
        emit MerkleRoyaltyClaimed(recipient, amount, activeRoot, collection);
    }
    ```

*   **ERC20 Claim Process (Planned):**
    ```solidity
    function claimERC20RoyaltiesMerkle(
        address collection,
        address recipient,
        address token,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external nonReentrant {
        // Similar to claimRoyaltiesMerkle but for ERC20 tokens
        // Verify proof against active root for the token
        // Transfer ERC20 tokens to recipient
        emit ERC20MerkleRoyaltyClaimed(recipient, token, amount, activeRoot, collection);
    }
    ```

*   **Oracle Rate Limiting:**
    ```solidity
    function updateRoyaltyDataViaOracle(address collection) external {
        // Rate limiting check
        require(block.number >= _lastOracleUpdateBlock[collection] + _oracleUpdateMinBlockInterval[collection]);
        _lastOracleUpdateBlock[collection] = block.number;
        // Trigger Chainlink oracle call
    }
    ```

*   **Oracle Callback (Planned):**
    ```solidity
    function fulfillRoyaltyData(
        bytes32 _requestId,
        address collection,
        uint256[] memory tokenIds,
        address[] memory minters,
        address creator,
        uint256[] memory salePrices,
        bytes32[] memory transactionHashes
    ) external recordChainlinkFulfillment(_requestId) {
        // Process data similar to batchUpdateRoyaltyData
        // This would be triggered by Chainlink oracle after updateRoyaltyDataViaOracle call
    }
    ```

**10. Future Considerations & Improvements**

*   **Gas Optimization:** Achieved significantly for claims using the Merkle distributor pattern. Batch updates (`batchUpdateRoyaltyData`) remain potentially costly but are handled by the service operator.
*   **Enhanced Access Control:** `setTokenMinter` restricted to the collection contract. Clear roles for Admin (`DEFAULT_ADMIN_ROLE`) and Service (`SERVICE_ACCOUNT_ROLE`).
*   **Marketplace Integration:** Explore direct integrations with major marketplaces via their APIs to automate price discovery.
*   **On-Chain Price Verification:** Research potential methods to verify sale prices on-chain without relying solely on off-chain services.
*   **Mint Revenue Distribution:** Explicitly separated. Mint revenue (`msg.value` from minting functions) goes directly to the `owner()` of the `DiamondGenesisPass` contract. Only secondary market royalties flow into the distributor for splitting via Merkle claims.
*   **Merkle Root Management:** The off-chain service must carefully manage how roots are generated (e.g., cumulative unpaid vs. periodic). The current on-chain design assumes only the latest root is active for claims. Define recovery procedures if a bad root is submitted.
*   **ERC-2981 Changes:** Monitor for changes in the ERC-2981 standard or marketplace implementations that might allow direct support for multiple royalty recipients.
*   **ERC20 Royalty Implementation:** 
    *   Complete the ERC20 royalty claiming functionality using Merkle proofs
    *   Add support for tracking ERC20 royalties in the batch update process
    *   Create separate Merkle roots for each ERC20 token type
*   **Multiple Collection Management:** Enhance the admin dashboard to manage multiple collections efficiently from a single interface.
*   **Oracle Service Completion:**
    *   Implement the Chainlink oracle adapter
    *   Complete the `fulfillRoyaltyData` function to securely process oracle responses
    *   Add secure oracle node communication
*   **Transaction Indexing:** Implement more sophisticated indexing methods to quickly locate missing price data for efficient batch updates.
*   **Testing and Auditing:** Comprehensive testing and security audit before full production deployment.

**Minter Status as a Tradable Commodity (Updated Spec)**

### 1. Minter Status Management
- The contract owner can assign or revoke minter status for any tokenId in the collection.
- Minter status entitles the holder to receive royalties for that token.

### 2. Bidding System for Minter Status
- Anyone can bid (by depositing ETH) to acquire minter status:
  - For a specific tokenId (token-specific bid).
  - For any token in the collection (collection-wide bid).
- Bids are tracked per tokenId and at the collection level.
- Bidders can increase their bids; ETH is escrowed in the contract.

### 3. Viewing Bids
- A public function allows anyone to view all current bidders and their bid amounts:
  - For a specific tokenId.
  - For the collection as a whole.

### 4. Selling Minter Status
- The current minter of a tokenId can accept the highest bid:
  - If the highest bid is for their specific tokenId, they can sell minter status to that bidder.
  - If the highest bid is at the collection level, they can sell minter status to that bidder.
- Upon sale:
  - The minter status is transferred to the new owner.
  - The ETH from the highest bid is distributed as follows:
    - 100% of the royalty for the minter status trade goes directly to the contract owner (not to the centralized royalty distributor).
    - The remainder (if any) is transferred to the seller.
  - All other bids for that tokenId or collection are refunded.

### 5. Security & Edge Cases
- Only the current minter can sell their minter status.
- If a bid is outbid, the previous bidder can withdraw their ETH.
- Prevent reentrancy and ensure proper ETH handling.

### 6. Example Solidity Functions
- `setMinterStatus(tokenId, address newMinter)` (onlyOwner)
- `placeBid(tokenId, isCollectionBid)` (payable)
- `viewBids(tokenId)` returns (Bid[])
- `viewCollectionBids()` returns (Bid[])
- `acceptHighestBid(tokenId)` (onlyMinter)
- `withdrawBid(tokenId, isCollectionBid)`
