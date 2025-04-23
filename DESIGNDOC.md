## Design Document: Diamond Genesis Pass Royalty System
We are using forge
Forge build, forge test

**1. Introduction**

This document outlines the design of the royalty distribution system for the `DiamondGenesisPass` NFT collection. The primary goal is to enable royalty sharing between the original minter of an NFT and the collection creator, while ensuring compatibility with major NFT marketplaces (like OpenSea, MagicEden) that typically only support sending royalties to a single designated address. The system also incorporates distinct roles for contract ownership and service account operations.

**2. Core Problem**

Standard `IERC2981` implementations return a single recipient address for royalties. However, we want to split royalties based on secondary market sales:
*   **Minter:** Receives a share (e.g., 20%) of the royalty from the secondary sale of the specific token they originally minted.
*   **Creator/Royalty Recipient:** Receives the remaining share (e.g., 80%) of the royalty.

Marketplaces do not natively support sending split royalties to multiple parties based on the specific token being sold. They typically send the full royalty amount specified by `IERC2981`'s `royaltyInfo` to the single `receiver` address returned by that function.

Primary mint payments need to be directed **solely to the creator/royalty recipient**, separate from the royalty distribution pool.

Additionally, after deployment, primary ownership needs to be transferred to a secure entity (like a multisig), while allowing a separate, less privileged service account to perform routine operational tasks. The royalty recipient (creator) address may also need to be transferred to a different entity (e.g., a company multisig) after deployment.

**3. Implemented Solution: Centralized Distributor Pattern with Direct Accrual Tracking**

Our solution uses a three-contract system with refined access control and clearly separated roles:

*   **Roles in the System:**
    *   **Contract Owner:** Controls administrative functions of the contract (setting URIs, enabling minting, etc.) and receives primary mint proceeds. Can transfer ownership to a new address using `transferOwnership` and can change the royalty recipient using `setRoyaltyRecipient`.
    *   **Creator/Royalty Recipient:** Receives the creator's share (80%) of royalties from secondary sales and receives primary mint proceeds. Initially set during deployment but can be updated by the owner.
    *   **Minters:** Receive their share (20%) of royalties from secondary sales of tokens they minted.
    *   **Service Account:** Has limited permissions to perform operational tasks without full admin control.

*   **`DiamondGenesisPass.sol` (NFT Contract):**
    *   The main ERC721 contract representing the NFTs.
    *   Implements `IERC2981` (`royaltyInfo`), directing marketplace royalties to the `CentralizedRoyaltyDistributor`.
    *   Uses **OpenZeppelin's `Ownable`** for primary contract ownership (e.g., setting Merkle root, public mint status, burning tokens). The `owner()` will typically be a multisig post-deployment.
    *   Uses **OpenZeppelin's `AccessControl`** to define a `SERVICE_ACCOUNT_ROLE` for delegated tasks (e.g., owner minting). This role is managed by the `DEFAULT_ADMIN_ROLE`, which should be granted to the `owner()`.
    *   **Key Responsibility:** Manages NFT logic, directs secondary market royalties via `royaltyInfo`, records minters with the distributor, **forwards primary mint payments (`msg.value`) directly to the current creator/royalty recipient address**, and enforces distinct permissions for Owner and Service Account roles.
    *   Provides `setRoyaltyRecipient` (and legacy `updateCreatorAddress`) to change who receives the creator's royalty share and mint payments.
    *   **Supply Management:**
        * **Total Maximum Supply:** 888 tokens
        * **Whitelist Mint Maximum Supply:** 212 tokens
        * **Public Mint Supply:** Remaining tokens (388 tokens) after whitelist phase. 288 was sold to pre-sale.

*   **`CentralizedRoyaltyAdapter.sol` (Pattern Contract - Implemented by DiamondGenesisPass):**
    *   Defines the standard interface and logic for an NFT contract to interact with the `CentralizedRoyaltyDistributor`.
    *   Provides the `royaltyInfo` implementation pointing to the distributor.
    *   Includes helper views to query the distributor.

*   **`CentralizedRoyaltyDistributor.sol` (Distribution Hub):**
    *   The single address designated to receive all royalty payments from marketplaces for registered collections.
    *   Uses **OpenZeppelin's `AccessControl`** for role management:
        *   `DEFAULT_ADMIN_ROLE`: Controls core functions like registering new collections and setting oracle parameters.
        *   `SERVICE_ACCOUNT_ROLE`: Can perform specific actions like updating accrued royalties (`updateAccruedRoyalties`).
    *   **Key Responsibilities:**
        *   Stores configuration per collection (royalty fee, minter/creator shares, creator address).
        *   Allows updating the creator address that receives royalties via `updateCreatorAddress`.
        *   Tracks the original minter for every `tokenId` within each registered collection.
        *   Accumulates received royalty funds (ETH and potentially ERC20) per collection **only from marketplace payments via its `receive()` function**.
        *   Tracks total accrued and claimed royalties per recipient for each collection.
        *   Provides functions (`claimRoyalties`) for minters and creators to withdraw their respective accumulated shares.
        *   Allows service accounts to update accrued royalties (`updateAccruedRoyalties`) to reflect new sales and royalty distributions.

**4. System Flow**

1.  **Deployment & Setup:**
    *   Deploy `CentralizedRoyaltyDistributor`. The deployer gets `DEFAULT_ADMIN_ROLE` and `SERVICE_ACCOUNT_ROLE`.
    *   Deploy `DiamondGenesisPass`, passing the `CentralizedRoyaltyDistributor` address, the overall royalty percentage (`royaltyFeeNumerator`), and the creator's address. The deployer becomes the `owner()` (from `Ownable`) and also gets `DEFAULT_ADMIN_ROLE` and `SERVICE_ACCOUNT_ROLE` (from `AccessControl`) on this contract.
    *   The `DiamondGenesisPass` deployer (who needs `DEFAULT_ADMIN_ROLE` on the distributor) calls `registerCollection` on the `CentralizedRoyaltyDistributor` via the `DiamondGenesisPass` constructor.
    *   The `owner()` of `DiamondGenesisPass` configures the contract (sets Merkle root, opens claim period, enables public mint).
    *   The `owner()` of `DiamondGenesisPass` transfers ownership (`transferOwnership`) to the company multisig.
    *   The `owner()` can also update the royalty recipient address (`setRoyaltyRecipient` or `updateCreatorAddress`) to direct creator royalties to a different address (e.g., company multisig).
    *   The multisig (now owner) grants `DEFAULT_ADMIN_ROLE` on `DiamondGenesisPass` to itself (if not already the deployer).
    *   The multisig (now owner and admin) grants `SERVICE_ACCOUNT_ROLE` on `DiamondGenesisPass` to the designated service account address.
    *   The admin of `CentralizedRoyaltyDistributor` grants `SERVICE_ACCOUNT_ROLE` on the distributor to the designated service account address.

2.  **Minting:**
    *   A user calls `whitelistMint` or `mint` on `DiamondGenesisPass`.
    *   The `DiamondGenesisPass` contract **transfers the payment (`msg.value`) directly to the current creator/royalty recipient address** (e.g., using `payable(creator()).transfer(msg.value)` or a safe equivalent).
    *   The `_mint` function within `DiamondGenesisPass` calls `centralizedDistributor.setTokenMinter(address(this), tokenId, to)` to record the minter. **Requires `setTokenMinter` to check `_msgSender()_ == collection`**.

3.  **Secondary Sale & Royalty Payment:**
    *   A user sells a `DiamondGenesisPass` NFT (e.g., Token ID 123) on a marketplace (e.g., OpenSea).
    *   The marketplace detects the sale and checks the `royaltyInfo` for Token ID 123 on the `DiamondGenesisPass` contract.
    *   `DiamondGenesisPass.royaltyInfo` returns the address of the `CentralizedRoyaltyDistributor` as the `receiver` and calculates the total royalty amount (e.g., 7.5% of sale price).
    *   The marketplace sends the full calculated royalty amount (ETH) to the `CentralizedRoyaltyDistributor` contract address.

4.  **Royalty Accumulation:**
    *   The `CentralizedRoyaltyDistributor` receives ETH via its `receive()` function from direct marketplace royalty payments.
    *   The contract internally increments the balance tracked for the `DiamondGenesisPass` collection address (`_collectionRoyalties[address(DiamondGenesisPass)] += msg.value`). **Note: `msg.value` is used here as `receive()` gets it directly.**

5.  **Royalty Data Processing & Accrual Updates:**
    *   **Off-Chain Processing:** An off-chain service monitors `Transfer` events, fetches sale prices from marketplaces, calculates royalty shares (minter/creator) based on the `_collectionConfigs`, and determines amounts owed to each recipient.
    *   **Accrual Updates:** The service account calls `updateAccruedRoyalties` on `CentralizedRoyaltyDistributor`, providing details for multiple recipients and their earned royalty amounts. This function (restricted to `SERVICE_ACCOUNT_ROLE` or `DEFAULT_ADMIN_ROLE`) updates internal accounting of total accrued royalties for each recipient and emits detailed `RoyaltyAccrued` events for transparency.

6.  **Royalty Claiming:**
    *   Minters and the creator (or updated royalty recipient) can call the public `claimRoyalties(address collection, uint256 amount)` function on the distributor at any time.
    *   The function checks that the caller has sufficient unclaimed royalties by verifying that their total accrued royalties minus already claimed royalties is greater than or equal to the requested amount.
    *   It also verifies that the distributor contract has sufficient ETH balance to fulfill the claim.
    *   If valid, it updates the claimed amount for the recipient and transfers the requested ETH amount to them. It emits a `RoyaltyClaimed` event.
    *   Recipients can check their claimable balance at any time using the `getClaimableRoyalties(address collection, address recipient)` view function.

**5. Contract Details & Implementation**

*   **`DiamondGenesisPass`:** Standard ERC721 features plus minting logic. Integrates `CentralizedRoyaltyAdapter`. Uses `Ownable` for core ownership (multisig) and `AccessControl` for `SERVICE_ACCOUNT_ROLE`. Forwards mint payments directly to the `owner()` address. Uses modifiers `onlyOwner` and `onlyOwnerOrServiceAccount`. `_requireCallerIsContractOwner` uses the `owner()` check for `MetadataURI` compatibility. Provides functions to update the royalty recipient address (`setRoyaltyRecipient` or legacy `updateCreatorAddress`).

*   **`CentralizedRoyaltyDistributor`:**
    *   Uses `AccessControl` for `DEFAULT_ADMIN_ROLE` (managing collections, oracle settings) and `SERVICE_ACCOUNT_ROLE` (updating accrued royalties).
    *   **State Variables:**
        *   `_collectionConfigs`: Maps collection address to configuration (royalty fee, shares, creator)
        *   `_minters`: Maps collection + token ID to minter address 
        *   `_minterCollectionTokens`: Maps minter + collection to token IDs minted
        *   `_collectionRoyalties`: Tracks ETH received per collection
        *   `_collectionERC20Royalties`: Tracks ERC20 tokens received per collection
        *   `_totalAccruedRoyalties`: Maps collection + recipient to total royalties accrued 
        *   `_totalClaimedRoyalties`: Maps collection + recipient to total royalties claimed
        *   `_tokenRoyaltyData`: Tracks royalty data per token (minter, volume, royalties earned)
        *   `_collectionRoyaltyData`: Tracks collection-level royalty data
        *   `_lastOracleUpdateBlock` and `_oracleUpdateMinBlockInterval`: For oracle rate limiting
    *   **Key Functions:**
        *   `registerCollection`: Registers a collection with royalty configuration (`onlyRole(DEFAULT_ADMIN_ROLE)`)
        *   `setTokenMinter`: Records the minter for a token (`onlyCollection(collection)`)
        *   `updateCreatorAddress`: Updates the address that receives creator royalties (callable by current creator or admin)
        *   `updateAccruedRoyalties`: Updates accrued royalties for multiple recipients (`onlyRole(SERVICE_ACCOUNT_ROLE)` or `DEFAULT_ADMIN_ROLE`)
        *   `claimRoyalties`: Allows recipients to claim their accrued royalties (public, nonReentrant)
        *   `getClaimableRoyalties`: View function to check claimable amount (public view)
        *   `updateRoyaltyDataViaOracle`: Triggers oracle update (public, rate-limited)
        *   `setOracleUpdateMinBlockInterval`: Sets rate limit for oracle updates (`onlyRole(DEFAULT_ADMIN_ROLE)`)
        *   `addCollectionRoyalties`/`addCollectionERC20Royalties`: Manually add royalties to a collection
        *   `fulfillRoyaltyData`: Chainlink callback (planned but not yet fully implemented)
    *   **Key Events:**
        *   `RoyaltyAccrued`: Emitted when royalties are accrued for a recipient
        *   `RoyaltyClaimed`: Emitted when a recipient claims royalties
        *   `RoyaltyReceived`/`ERC20RoyaltyReceived`: Emitted when royalties are received
        *   `CreatorAddressUpdated`: Emitted when the creator/royalty recipient address is updated

**6. Security Considerations & Risk Mitigations**

*   **Distributor Security:** The `CentralizedRoyaltyDistributor` holds funds. It uses `ReentrancyGuard` for claim functions and checks fund availability before allowing claims.
*   **Owner Privileges:** The `owner()` (multisig) controls critical settings, receives mint proceeds, and can update the royalty recipient address.
*   **Admin Privileges:** The `DEFAULT_ADMIN_ROLE` holder (ideally the owner/multisig) manages collections and roles.
*   **Service Account Permissions:** The `SERVICE_ACCOUNT_ROLE` has limited permissions (updating accrued royalties). If compromised, it cannot change core settings but could potentially inflate accrued royalties for specific recipients. Requires trust in the off-chain service operator.
*   **Creator/Royalty Recipient Update:** The ability to change the creator address allows transferring royalty rights but also introduces a risk if ownership is compromised. Functions to update the creator are protected by access control.
*   **Distribution Trust:** Users trust the distributor's claim logic and fund availability.
*   **Price Accuracy:** Users trust the off-chain service accurately determines sale prices for calculating earned amounts in `updateAccruedRoyalties`.
*   **Oracle Security:** The implementation includes rate limiting for oracle updates to prevent abuse. Oracle fulfillment should be restricted to the oracle node.
*   **Gas Costs:** The `updateAccruedRoyalties` function might be gas-intensive when updating many recipients at once. The service might need to batch these updates for gas efficiency.
*   **Race Conditions:** The direct accrual tracking system eliminates race conditions between updating royalties and claiming, as claims are always based on the current state of accrued minus claimed amounts.

**7. Off-Chain Components**

*   **Royalty Calculation & Distribution Service:** A service that:
    *   Monitors `Transfer` events.
    *   Collects price data from marketplace APIs.
    *   Calculates royalty shares based on sale prices and collection configuration.
    *   Calls `updateAccruedRoyalties` (or `updateAccruedERC20Royalties`) to update accrued royalties for minters and creators.
*   **Oracle Implementation:** A Chainlink oracle adapter that connects the off-chain price discovery service to the on-chain distributor contract.
    *   Triggered by `updateRoyaltyDataViaOracle` on the distributor.
    *   Fetches processed royalty data (recipients and amounts) from the off-chain service.
    *   Calls `fulfillRoyaltyData` on the distributor.
*   **Administrative Dashboard:** A UI for the contract owner to monitor transfers, add/remove service accounts, update the royalty recipient, and manage the distribution system.
*   **User Claim Interface:** A UI for minters and creators/royalty recipients to check their earned royalties and claim them.

**7.1 Chainlink Oracle Integration Architecture**

The system uses an event-driven architecture for oracle integration that can be deployed in phases:

1. **Initial Deployment (Without Chainlink):**
   * Deploy `CentralizedRoyaltyDistributor` and `DiamondGenesisPass` contracts
   * The `updateRoyaltyDataViaOracle` function emits events but has no immediate effect
   * Service accounts can still update royalties directly with `updateAccruedRoyalties`

2. **Chainlink Integration (Later Phase):**
   * Deploy `ChainlinkOracleIntegration` contract pointing to the `CentralizedRoyaltyDistributor`
   * Set up `trustedOracleAddress` in the distributor
   * Configure Chainlink parameters (router, DON ID, subscription ID)
   * Set up JavaScript source code for Chainlink Functions

3. **End-to-End Oracle Flow:**
   ```
   ┌───────────────┐         ┌──────────────────────────┐         ┌───────────────────────┐
   │  Any User     │ ─────▶ │ CentralizedRoyalty       │ ─────▶ │ Off-Chain Listener     │
   │ (Public Call) │         │ Distributor              │         │                       │
   └───────────────┘         └──────────────────────────┘         └───────────────────────┘
          │                           │                                      │
          │                           │                                      │
          │                           ▼                                      ▼
          │                  ┌──────────────────┐                 ┌───────────────────────┐
          │                  │ Rate-Limited     │                 │ ChainlinkOracle       │
          │                  │ Event Emission   │                 │ Integration Contract  │
          │                  └──────────────────┘                 └───────────────────────┘
          │                                                                 │
          │                                                                 │
          │                                                                 ▼
          │                                                       ┌───────────────────────┐
          │                                                       │ Chainlink Functions   │
          │                                                       │ (Off-Chain Processing)│
          │                                                       └───────────────────────┘
          │                                                                 │
          │                                                                 │
          ▼                                                                 ▼
   ┌───────────────┐         ┌──────────────────────────┐         ┌───────────────────────┐
   │  Royalty      │ ◀────── │ fulfillRoyaltyData       │ ◀────── │ Oracle Response       │
   │  Recipients   │         │ (Trusted Oracle Only)    │         │ (Processed Data)      │
   └───────────────┘         └──────────────────────────┘         └───────────────────────┘
   ```

4. **Security Features:**
   * Only the trusted oracle address can call `fulfillRoyaltyData`
   * Rate limiting prevents excessive updates (configurable per collection)
   * Off-chain listener can be a dedicated service or run by the contract owner
   * Chainlink Functions provides cryptographic verification of data
   * Admin can always override or update oracle configuration

5. **Deployment Flexibility:**
   * Contracts can be deployed and operate normally without immediate Chainlink integration
   * Oracle integration can be added later when needed, without disrupting existing functionality
   * Service accounts can still directly update royalties if needed

This phased approach allows immediate deployment while reserving the option to add automated Chainlink-based updates later.

**8. On-Chain Analytics**

*   **On-Chain Metrics (Totals Only):**
    *   `uint256 public totalAccruedRoyalty;` // total royalties accrued across all recipients
    *   `uint256 public totalClaimedRoyalty;` // total royalties claimed across all recipients

*   **Contract Modifications:**
    *   In `updateAccruedRoyalties`, update:
        ```solidity
        totalAccruedRoyalty += amount;
        ```
    *   In `claimRoyalties`, update:
        ```solidity
        totalClaimedRoyalty += amount;
        ```

*   **View Functions (gas-free external calls):**
    *   `function totalAccrued() external view returns (uint256) { return totalAccruedRoyalty; }`
    *   `function totalClaimed() external view returns (uint256) { return totalClaimedRoyalty; }`
    *   `function totalUnclaimed() external view returns (uint256) { return totalAccruedRoyalty - totalClaimedRoyalty; }`
    *   `function collectionUnclaimed(address collection) external view returns (uint256) { return _collectionRoyalties[collection]; }`
    *   `function totalUnclaimedRoyalties() external view returns (uint256)` // On DiamondGenesisPass, returns the collection-specific unclaimed amount
    *   `function getClaimableRoyalties(address collection, address recipient) external view returns (uint256)` // Returns the claimable amount for a specific recipient

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

*   **Accrual Update Process:**
    ```solidity
    function updateAccruedRoyalties(
        address collection,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyRole(SERVICE_ACCOUNT_ROLE) {
        require(recipients.length == amounts.length, "Length mismatch");
        
        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint256 amount = amounts[i];
            
            _totalAccruedRoyalties[collection][recipient] += amount;
            
            emit RoyaltyAccrued(collection, recipient, amount);
            totalAccruedRoyalty += amount;
        }
    }
    ```

*   **Claim Process:**
    ```solidity
    function claimRoyalties(
        address collection,
        uint256 amount
    ) external nonReentrant {
        address recipient = msg.sender;
        
        // Check that the recipient has sufficient unclaimed royalties
        uint256 accrued = _totalAccruedRoyalties[collection][recipient];
        uint256 claimed = _totalClaimedRoyalties[collection][recipient];
        require(accrued - claimed >= amount, "Insufficient unclaimed royalties");
        
        // Check that the contract has sufficient balance
        require(_collectionRoyalties[collection] >= amount, "Insufficient collection balance");
        
        // Update claimed amount and reduce collection balance
        _totalClaimedRoyalties[collection][recipient] += amount;
        _collectionRoyalties[collection] -= amount;
        totalClaimedRoyalty += amount;
        
        // Transfer the funds
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Transfer failed");
        
        emit RoyaltyClaimed(collection, recipient, amount);
    }
    ```

*   **View Claimable Amount:**
    ```solidity
    function getClaimableRoyalties(
        address collection,
        address recipient
    ) external view returns (uint256) {
        uint256 accrued = _totalAccruedRoyalties[collection][recipient];
        uint256 claimed = _totalClaimedRoyalties[collection][recipient];
        return accrued - claimed;
    }
    ```

*   **ERC20 Support (Planned):**
    ```solidity
    function updateAccruedERC20Royalties(
        address collection,
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyRole(SERVICE_ACCOUNT_ROLE) {
        // Similar to updateAccruedRoyalties but for ERC20 tokens
    }
    
    function claimERC20Royalties(
        address collection,
        address token,
        uint256 amount
    ) external nonReentrant {
        // Similar to claimRoyalties but for ERC20 tokens
    }
    ```

*   **Oracle Rate Limiting:**
    ```solidity
    // Public function that can be called by anyone
    function updateRoyaltyDataViaOracle(address collection) external {
        // Check collection is registered
        if (!_collectionConfigs[collection].registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }
        
        // Rate limiting check - the only protection to prevent abuse
        uint256 minInterval = _oracleUpdateMinBlockInterval[collection];
        if (block.number < _lastOracleUpdateBlock[collection] + minInterval) {
            revert RoyaltyDistributor__OracleUpdateTooFrequent();
        }
        
        // Update last call block
        _lastOracleUpdateBlock[collection] = block.number;
        
        // Emit an event for the off-chain listener to detect and trigger the oracle
        emit OracleUpdateRequested(collection, _collectionRoyaltyData[collection].lastSyncedBlock, block.number);
    }
    ```

*   **Oracle Response Handling:**
    ```solidity
    // Called only by the trusted oracle address
    function fulfillRoyaltyData(
        bytes32 requestId,
        address collection,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external {
        // Ensure the caller is the trusted oracle address
        if (msg.sender != trustedOracleAddress && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert RoyaltyDistributor__CallerIsNotTrustedOracle();
        }

        // Validate the inputs
        if (!_collectionConfigs[collection].registered) {
            revert RoyaltyDistributor__CollectionNotRegistered();
        }
        require(recipients.length == amounts.length, "Arrays must have the same length");

        // Update accrued royalties
        bytes32[] memory emptyHashes = new bytes32[](recipients.length);
        _updateAccruedRoyaltiesInternal(collection, recipients, amounts, emptyHashes);
        
        // Emit completion event
        emit OracleRoyaltyDataFulfilled(collection, requestId);
    }
    ```

**10. Future Considerations & Improvements**

*   **Gas Optimization:** The `updateAccruedRoyalties` function might need optimization for handling many recipients efficiently. Consider batching strategies.
*   **Enhanced Access Control:** `setTokenMinter` restricted to the collection contract. Clear roles for Admin (`DEFAULT_ADMIN_ROLE`) and Service (`SERVICE_ACCOUNT_ROLE`).
*   **Marketplace Integration:** Explore direct integrations with major marketplaces via their APIs to automate price discovery.
*   **On-Chain Price Verification:** Research potential methods to verify sale prices on-chain without relying solely on off-chain services.
*   **Mint Revenue Distribution:** Explicitly separated. Mint revenue (`msg.value` from minting functions) goes directly to the `owner()` of the `DiamondGenesisPass` contract. Only secondary market royalties flow into the distributor for splitting.
*   **ERC-2981 Changes:** Monitor for changes in the ERC-2981 standard or marketplace implementations that might allow direct support for multiple royalty recipients.
*   **ERC20 Royalty Implementation:** 
    *   Complete the ERC20 royalty claiming functionality (already present).
    *   Ensure ERC20 tracking and accrual process is robust (`updateAccruedERC20Royalties`).
*   **Multiple Collection Management:** Enhance the admin dashboard to manage multiple collections efficiently from a single interface.
*   **Oracle Service Implementation:**
    *   The system is designed to allow deploying the contracts first and configuring Chainlink integration later.
    *   A separate `ChainlinkOracleIntegration` contract connects the CentralizedRoyaltyDistributor with Chainlink Functions.
    *   The `updateRoyaltyDataViaOracle` function is public and can be called by anyone, with rate limiting as the only protection to prevent abuse.
    *   To complete the integration:
        *   Deploy the `ChainlinkOracleIntegration` contract pointing to the `CentralizedRoyaltyDistributor`.
        *   Set the trusted oracle address in the distributor via `setTrustedOracleAddress`.
        *   Configure the Chainlink router, DON ID, and subscription ID via `configureChainlink`.
        *   Set the JavaScript source code for Chainlink Functions via `setSource`.
        *   Implement an off-chain listener for `OracleUpdateRequested` events that triggers Chainlink Functions requests.
    *   Security measures:
        *   Only the trusted oracle address can call `fulfillRoyaltyData`.
        *   Rate limiting prevents excessive LINK token costs.
        *   Access control ensures only authorized addresses can configure the oracle integration.
*   **Transaction Indexing:** Implement more sophisticated indexing methods to quickly locate missing price data for efficient batch updates.
*   **Testing and Auditing:** Comprehensive testing (including the updated Oracle flow) and security audit before full production deployment.

**11. Accrual System Implementation**

### Accrual System Requirements

*   **Updating Accrued Royalties:** The off-chain service must accurately calculate royalty shares and update accrued amounts via `updateAccruedRoyalties`.

*   **Preventing Double Accrual:** The system must prevent double-counting royalties for the same sale:
    * Keep a record of processed transaction hashes
    * Only accrue royalties for sales that haven't been processed

*   **Claiming Royalties:** The system allows recipients to claim their royalties at any time, up to their unclaimed balance.

### Claim Security

*   **Balance Verification:** The contract verifies that:
    * The recipient has sufficient unclaimed royalties
    * The contract has sufficient ETH to fulfill the claim

*   **Reentrancy Protection:** The contract uses OpenZeppelin's `ReentrancyGuard` to prevent reentrancy attacks during claims.

*   **Order of Operations:** The contract follows the checks-effects-interactions pattern:
    * First checks balances
    * Then updates state variables
    * Only then transfers ETH

### Off-Chain Service Requirements

*   **Production Implementation:**
    * Monitor blockchain for NFT transfers
    * Query marketplace APIs for sale prices
    * Calculate royalty splits based on collection configuration
    * Update accrued royalties via `updateAccruedRoyalties`
    * Provide UI for users to view and claim their royalties

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

**Token Trading System (Direct Token Sales)**

### 1. Token Bidding Mechanism
- Anyone can place bids to purchase tokens directly from current token owners:
  - For a specific tokenId (token-specific bid)
  - For any token in the collection (collection-wide bid)
- Bids are tracked separately from minter status bids
- Bidders can increase their bids; ETH is escrowed in the contract

### 2. Bid Management
- A token holder can view all bids for their token(s)
- Bidders can withdraw their bids if they change their mind or are outbid
- The system tracks token bids and collection-wide bids separately

### 3. Token Sale Process
- Token owners can accept the highest bid for their token:
  - If the highest bid is for their specific tokenId
  - If the highest bid is at the collection level
- Upon acceptance:
  - The token is transferred to the bidder
  - The sale price is split according to royalty configuration:
    - A percentage (e.g., 7.5%) is sent to the CentralizedRoyaltyDistributor
    - The remainder (92.5%) is transferred to the seller
  - After the sale, the distributor handles the royalty split (minter/creator)
  - All other bids for that tokenId are refunded automatically

### 4. Royalty Handling
- The transaction is recorded as a sale in the CentralizedRoyaltyDistributor
- Royalties are properly attributed between minter and creator based on collection configuration
- The distribution follows the same accrual pattern as marketplace sales

### 5. Security & Edge Cases
- Only the token owner can accept bids for their token
- Token and royalty transfers are atomic (all succeed or all fail)
- Prevents reentrancy attacks
- Ensures proper handling of ETH transfers

### 6. Example Solidity Functions
- `placeTokenBid(tokenId, isCollectionBid)` (payable)
- `viewTokenBids(tokenId)` returns (TokenBid[])
- `viewCollectionTokenBids()` returns (TokenBid[])
- `acceptHighestTokenBid(tokenId)` (onlyTokenOwner)
- `withdrawTokenBid(tokenId, isCollectionBid)`
- `_distributeSaleProceeds(tokenId, salePrice, buyer, seller)`
