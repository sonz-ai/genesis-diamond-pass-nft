## Design Document: Diamond Genesis Pass Royalty System

**1. Introduction**

This document outlines the design of the royalty distribution system for the `DiamondGenesisPass` NFT collection. The primary goal is to enable royalty sharing between the original minter of an NFT and the collection creator, while ensuring compatibility with major NFT marketplaces (like OpenSea, MagicEden) that typically only support sending royalties to a single designated address. The system also incorporates distinct roles for contract ownership and service account operations.

**2. Core Problem**

Standard `IERC2981` implementations return a single recipient address for royalties. However, we want to split royalties based on secondary market sales:
*   **Minter:** Receives a share (e.g., 20%) of the royalty from the secondary sale of the specific token they originally minted.
*   **Creator:** Receives the remaining share (e.g., 80%) of the royalty.

Marketplaces do not natively support sending split royalties to multiple parties based on the specific token being sold. They typically send the full royalty amount specified by `IERC2981`'s `royaltyInfo` to the single `receiver` address returned by that function.

Primary mint payments also need to be directed into this royalty system to be distributed according to the defined shares.

Additionally, after deployment, primary ownership needs to be transferred to a secure entity (like a multisig), while allowing a separate, less privileged service account to perform routine operational tasks.

**3. Proposed Solution: Centralized Distributor Pattern with Dual Access Control**

We address this using a three-contract system with a refined access control model:

*   **`DiamondGenesisPass.sol` (NFT Contract):**
    *   The main ERC721 contract representing the NFTs.
    *   Implements `IERC2981` (`royaltyInfo`), directing marketplace royalties to the `CentralizedRoyaltyDistributor`.
    *   Uses **OpenZeppelin's `Ownable`** for primary contract ownership (e.g., setting Merkle root, public mint status, burning tokens). The `owner()` will typically be a multisig post-deployment.
    *   Uses **OpenZeppelin's `AccessControl`** to define a `SERVICE_ACCOUNT_ROLE` for delegated tasks (e.g., owner minting, recording sales). This role is managed by the `DEFAULT_ADMIN_ROLE`, which should be granted to the `owner()`.
    *   **Key Responsibility:** Manages NFT logic, directs secondary market royalties via `royaltyInfo`, records minters with the distributor, **forwards primary mint payments (`msg.value`) to the `CentralizedRoyaltyDistributor`'s pool for this collection**, and enforces distinct permissions for Owner and Service Account roles.

*   **`CentralizedRoyaltyAdapter.sol` (Pattern Contract - Implemented by DiamondGenesisPass):**
    *   Defines the standard interface and logic for an NFT contract to interact with the `CentralizedRoyaltyDistributor`.
    *   Provides the `royaltyInfo` implementation pointing to the distributor.
    *   Includes helper views to query the distributor.

*   **`CentralizedRoyaltyDistributor.sol` (Distribution Hub):**
    *   The single address designated to receive all royalty payments from marketplaces for registered collections.
    *   Uses **OpenZeppelin's `AccessControl`** for role management:
        *   `DEFAULT_ADMIN_ROLE`: Controls core functions like registering new collections.
        *   `SERVICE_ACCOUNT_ROLE`: Can perform specific actions like recording sale royalties (`recordSaleRoyalty`).
    *   **Key Responsibilities:**
        *   Stores configuration per collection (royalty fee, minter/creator shares, creator address).
        *   Tracks the original minter for every `tokenId` within each registered collection.
        *   Accumulates received royalty funds (ETH and potentially ERC20) per collection, **including primary mint payments forwarded from the NFT contract.**
        *   Provides functions (`claimRoyalties`, `claimERC20Royalties`) for minters and creators to withdraw their respective shares of the *accumulated pool*.
        *   Allows admins or service accounts to record sale details (triggering royalty pool updates).

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
    *   The `DiamondGenesisPass` contract forwards the payment (`msg.value`) to the `CentralizedRoyaltyDistributor` by calling `centralizedDistributor.addCollectionRoyalties{value: msg.value}(address(this))`, adding the funds to this collection's royalty pool.
    *   The `_mint` function within `DiamondGenesisPass` calls `centralizedDistributor.setTokenMinter(address(this), tokenId, to)` to record the minter.

3.  **Secondary Sale & Royalty Payment:**
    *   A user sells a `DiamondGenesisPass` NFT (e.g., Token ID 123) on a marketplace (e.g., OpenSea).
    *   The marketplace detects the sale and checks the `royaltyInfo` for Token ID 123 on the `DiamondGenesisPass` contract.
    *   `DiamondGenesisPass.royaltyInfo` returns the address of the `CentralizedRoyaltyDistributor` as the `receiver` and calculates the total royalty amount (e.g., 7.5% of sale price).
    *   The marketplace sends the full calculated royalty amount (ETH) to the `CentralizedRoyaltyDistributor` contract address.

4.  **Royalty Accumulation:**
    *   The `CentralizedRoyaltyDistributor` receives ETH via its `receive()` function (for direct marketplace payments) **or its `addCollectionRoyalties` function (for primary mint payments).**
    *   The contract internally increments the balance tracked for the `DiamondGenesisPass` collection address (`_collectionRoyalties[address(DiamondGenesisPass)] += amount`).

5.  **Sale Recording & Distribution:**
    *   **Manual Recording:** The service account (or Owner/Admin) calls `recordSale` on `DiamondGenesisPass`. This function verifies the caller has `owner()` or `SERVICE_ACCOUNT_ROLE` on `DiamondGenesisPass` and then calls `recordSaleRoyalty` on `CentralizedRoyaltyDistributor`.
    *   `recordSaleRoyalty` on the distributor verifies the caller has `DEFAULT_ADMIN_ROLE` or `SERVICE_ACCOUNT_ROLE` *on the distributor*, calculates the royalty based on the provided `salePrice`, and adds it to the collection's royalty pool.
    *   **Fund Distribution Methods:** Minters and the creator call `claimRoyalties` or `claimERC20Royalties` on the distributor to withdraw their calculated share of the *accumulated pool* based on the collection's minter/creator share configuration. These calls do not require special roles.

**5. Contract Details & Rationale**

*   **`DiamondGenesisPass`:** Standard ERC721 features plus minting logic. Integrates `CentralizedRoyaltyAdapter`. Uses `Ownable` for core ownership (multisig) and `AccessControl` for `SERVICE_ACCOUNT_ROLE`. **Forwards mint payments to the distributor's collection pool.** Uses modifiers `onlyOwner` and `onlyOwnerOrServiceAccount`. `_requireCallerIsContractOwner` uses the `owner()` check for `MetadataURI` compatibility. The forwarding of mint payments to `treasuryAddress` is flexible.

*   **`CentralizedRoyaltyDistributor`:**
    *   Uses `AccessControl` for `DEFAULT_ADMIN_ROLE` (managing collections) and `SERVICE_ACCOUNT_ROLE` (recording sales).
    *   `_collectionConfigs`, `_minters`, `_minterCollectionTokens`, `_collectionRoyalties`, `_collectionERC20Royalties`: Core state variables (mostly unchanged).
    *   **(New Sale Tracking Components section mostly unchanged, relates to future price discovery)**
    *   **Access Control Functions:** Uses standard `AccessControl` functions (`grantRole`, `revokeRole`, `hasRole`, etc.) managed by the `DEFAULT_ADMIN_ROLE`.
    *   **Key Functions:**
        *   `registerCollection`: `onlyRole(DEFAULT_ADMIN_ROLE)`.
        *   `setTokenMinter`: `onlyCollection(collection)` - callable only by the NFT contract.
        *   `recordSaleRoyalty`/`recordERC20Royalty`: Requires `DEFAULT_ADMIN_ROLE` or `SERVICE_ACCOUNT_ROLE`.
        *   `claimRoyalties`/`claimERC20Royalties`: No specific role required; callable by any eligible minter or the creator.
        *   `addCollectionRoyalties`: Accepts `payable` calls (e.g., from `DiamondGenesisPass` during mint) to add funds directly to a specific collection's royalty pool.
        *   **(Price Discovery/Oracle functions unchanged)**

**6. Security Considerations & Trust Assumptions**

*   **Distributor Security:** The `CentralizedRoyaltyDistributor` holds funds. It must be secure, non-reentrant (`ReentrancyGuard` is used), and ideally audited.
*   **Owner Privileges (`DiamondGenesisPass`):** The `owner()` (multisig) controls critical settings and the `treasuryAddress`.
*   **Admin Privileges (`AccessControl`):** The `DEFAULT_ADMIN_ROLE` holder (initially deployer, ideally transferred to owner/multisig) manages roles (`SERVICE_ACCOUNT_ROLE`) on both contracts.
*   **Service Account Permissions:** The `SERVICE_ACCOUNT_ROLE` has limited permissions (owner minting, sale recording). If compromised, it cannot change core settings or steal funds directly, but could potentially record incorrect sales data if the distributor relies solely on its input for pool updates.
*   **Distribution Trust:** Users trust the distributor's share logic and fund availability.
*   **Price Accuracy:** Users must trust that the off-chain process accurately determines sale prices, as this directly impacts their royalty allocation.
*   **Oracle Security:** The implementation of Chainlink oracles introduces additional security considerations related to the off-chain data source and oracle nodes.
*   **Gas Costs:** Claiming/distributing royalties costs gas. Frequent small claims might be inefficient. The batch claim (`distributeAll...`) approach is generally more gas-efficient per ETH transferred than per-sale distributions.

**7. Off-Chain Components**

*   **Transfer Monitoring Service:** An off-chain service that listens for transfer events from the `DiamondGenesisPass` contract and calls `recordTransfer` on the distributor.
*   **Batch Price Discovery Service:** A service that:
    *   Calls `getLastPricedTransaction` to determine where to start the data collection
    *   Queries `getUnpricedTransactions` to get a list of transfers needing price updates
    *   Collects price data for all identified transactions from marketplace APIs in a single batch
    *   Submits a single `batchUpdateSalePrices` transaction to update all prices efficiently
*   **Oracle Implementation:** A Chainlink oracle adapter that connects the off-chain price discovery service to the on-chain distributor contract.
*   **Administrative Dashboard:** A UI for the contract owner to monitor transfers, add/remove service accounts, and manage the distribution system.

**8. Royalty Collection Process**

The royalty collection system combines on-chain and off-chain components to ensure accurate tracking and distribution of royalties:

*   **Marketplace Royalty Flow:**
    *   When a DiamondGenesisPass NFT is sold on a marketplace supporting IERC2981, the marketplace calls `royaltyInfo` and sends the royalty amount to the CentralizedRoyaltyDistributor.
    *   The distributor's `receive()` function captures these payments and adds them to the collection's royalty pool.

*   **Transaction Tracking:**
    *   The contract emits a `TransferEvent(uint256 indexed tokenId, address from, address to, uint256 timestamp)` whenever a token changes ownership.
    *   The contract tracks key data per tokenId using the following structure:
        ```solidity
        struct TokenRoyaltyData {
            address minter;               // Original minter address
            address currentOwner;         // Current owner address
            uint256 transactionCount;     // Number of times the token has been traded
            uint256 totalVolume;          // Cumulative trading volume
            uint256 lastSyncedBlock;      // Latest block height when royalty data was updated
            uint256 minterRoyaltyEarned;  // Total royalties earned by minter
            uint256 minterRoyaltyPaid;    // Total royalties withdrawn by minter
            uint256 creatorRoyaltyEarned; // Total royalties earned by creator for this token
            uint256 creatorRoyaltyPaid;   // Total royalties withdrawn by creator for this token
            mapping(bytes32 => bool) processedTransactions; // Hash map to prevent duplicate processing
        }
        ```
    *   The contract also maintains collection-level data:
        ```solidity
        struct CollectionRoyaltyData {
            uint256 totalVolume;          // Total volume across all tokens
            uint256 lastSyncedBlock;      // Latest sync block for the collection
            uint256 totalRoyaltyCollected; // Total royalties received
            uint256 totalRoyaltyDistributed; // Total royalties paid out
        }
        ```

*   **Royalty Synchronization Process:**
    *   Each transfer emits an event that is monitored by an off-chain processor.
    *   The processor queries the blockchain for `TransferEvent` events after the `lastSyncedBlock` height.
    *   For each identified transfer, the processor:
        1. Determines the sale price from marketplace APIs (OpenSea, LooksRare, etc.)
        2. Calculates the royalty amounts based on configured splits (e.g., 20% minter, 80% creator)
        3. Computes the new cumulative volume and royalties
    *   The processor then calls a restricted batch update function:
        ```solidity
        function batchUpdateRoyaltyData(
            address collection,
            uint256[] calldata tokenIds,
            uint256[] calldata salePrices,
            uint256[] calldata transactionTimestamps,
            bytes32[] calldata transactionHashes
        ) external onlyRole(SERVICE_ACCOUNT_ROLE)
        ```
    *   This function:
        1. Verifies the caller has SERVICE_ACCOUNT_ROLE or is the owner
        2. For each tokenId in the batch:
           - Verifies the transaction hash hasn't been processed before
           - Updates the token's transaction count, volume, and royalty data
           - Marks the transaction hash as processed
        3. Updates the lastSyncedBlock to the current block
        4. Emits a `RoyaltyDataUpdated(address collection, uint256[] tokenIds)` event

*   **Withdrawal Process:**
    *   After royalty data is updated, users can interact with the system:
        *   Minters can view their earned royalties through a view function:
           ```solidity
           function getMinterRoyaltyInfo(address minter) external view returns (
               uint256 totalEarned,
               uint256 totalWithdrawn,
               uint256 currentlyClaimable,
               uint256[] memory tokenIds
           )
           ```
        *   Minters can claim through these functions:
           ```solidity
           function claimMinterRoyalties(uint256 tokenId) external
           function claimAllMinterRoyalties() external
           ```
        *   The creator can check and claim their royalties:
           ```solidity
           function getCreatorRoyaltyInfo() external view returns (
               uint256 totalEarned,
               uint256 totalWithdrawn,
               uint256 currentlyClaimable
           )
           function claimCreatorRoyalties() external
           ```
    *   Each claim function:
        1. Calculates the claimable amount (accumulated minus already withdrawn)
        2. Updates the withdrawn amount tracking
        3. Transfers the funds to the appropriate recipient
        4. Emits a `RoyaltyClaimed(address recipient, uint256 amount)` event

*   **Oracle-Based Synchronization (Alternative/Backup):**
    *   Any user can trigger royalty data updates through the public oracle function:
       ```solidity
       function updateRoyaltyDataViaOracle() external
       ```
    *   This function:
        1. Calls a Chainlink oracle using the following parameters:
           ```solidity
           Request memory req = buildChainlinkRequest(
               jobId,
               address(this),
               this.fulfillRoyaltyData.selector
           );
           req.add("collection", addressToString(address(this)));
           req.add("fromBlock", uint256ToString(lastSyncedBlock));
           return sendOperatorRequest(req, fee);
           ```
        2. The oracle calls an API endpoint like: `https://api.royalty-tracker.com/collection/{collection}/transactions?fromBlock={fromBlock}`
        3. The API response includes all token transfers and verified sale prices
        4. The Chainlink callback function `fulfillRoyaltyData` processes this data on-chain:
           ```solidity
           function fulfillRoyaltyData(
               bytes32 _requestId,
               uint256[] memory tokenIds,
               uint256[] memory salePrices,
               bytes32[] memory transactionHashes
           ) external recordChainlinkFulfillment(_requestId)
           ```
        5. This function updates the royalty data in the same way as the service account's batch update function

*   **Anti-Duplication Safeguards:**
    *   To prevent duplicate royalty calculations, the system implements several layers of protection:
        1. Each transaction hash is stored in a mapping (`processedTransactions`) with boolean values
        2. Before processing any sale, the contract checks: `require(!tokenData.processedTransactions[txHash], "Transaction already processed");`
        3. The off-chain processor tracks the last processed block height and only queries for newer events
        4. The system includes a reconciliation process that can be triggered by the service account to verify and fix any discrepancies

*   **User Interface for Royalty Tracking:**
    *   A dedicated dashboard will be provided for minters and the creator to:
        1. View their current claimable royalties across all tokens they've minted
        2. See historical royalty payments
        3. Track the trading activity of their tokens
        4. Initiate royalty claims
        5. Verify the last synchronized block and ensure their royalty data is up-to-date

This hybrid approach combines the efficiency of centralized off-chain processing with the security of on-chain verification, ensuring minters and the creator can reliably claim their earned royalties while maintaining reasonable gas costs.

**9. Future Considerations / Potential Improvements**

*   **Marketplace Integration:** Explore direct integrations with major marketplaces via their APIs to automate price discovery.
*   **Gas Optimization:** Optimize batch operations like `batchUpdateSalePrices` to handle larger sets of transactions while minimizing gas costs.
*   **Enhanced Access Control:** Consider implementing a more granular RBAC (Role-Based Access Control) system to restrict specific functions to specific service accounts.
*   **Transaction Indexing:** Implement more sophisticated indexing methods to quickly locate missing price data for efficient batch updates.
*   **Oracle Redundancy:** Use multiple oracle providers or data sources to ensure reliability of off-chain price information.
*   **ERC20 Royalties:** The system includes handling for ERC20 royalties, which adds flexibility but also complexity if multiple royalty tokens are expected.
*   **On-Chain Price Verification:** Research potential methods to verify sale prices on-chain without relying solely on off-chain services.
*   **Restricting `setTokenMinter`:** Modify `setTokenMinter` in the distributor to only be callable by the registered `collection` address, rather than `onlyOwner`, improving security and decentralization. This requires the distributor to know about the collection *before* minting starts, which is already the case via `registerCollection`.
*   **Role Management:** Ensure clear processes for managing `DEFAULT_ADMIN_ROLE` and `SERVICE_ACCOUNT_ROLE` across both contracts, especially after ownership transfer.
*   **Distributor Permissions:** The current `recordSaleRoyalty` trusts the caller (Admin/Service Account) provides the correct `salePrice` to update the pool. Future oracle integration is key for trustless price updates.
*   Consider if `DEFAULT_ADMIN_ROLE` on `DiamondGenesisPass` should strictly be the `owner()` by overriding `_authorizeUpgrade` (if using UUPS) or managing roles carefully.
*   **Mint Revenue Distribution:** The current model pools mint revenue with secondary royalties. Consider if mint revenue should have different split rules or bypass the minter share entirely, which would require adjustments to the distributor's claim logic or separate accounting.
