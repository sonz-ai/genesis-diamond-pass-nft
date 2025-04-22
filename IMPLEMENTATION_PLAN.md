# Diamond Genesis Pass Royalty System - Implementation Plan
We are using forge
Forge build, forge test

## Core Components

1. **Smart Contracts**
   - CentralizedRoyaltyDistributor.sol
   - CentralizedRoyaltyAdapter.sol (pattern contract)
   - DiamondGenesisPass.sol (NFT contract)

2. **Off-Chain Services**
   - Batch Price Discovery & Royalty Service
   - Oracle Implementation
   - Administrative Dashboard
   - User Claim Interface

## Implementation Checklist

### Phase 1: Smart Contract Development

- [x] **CentralizedRoyaltyDistributor.sol**
  - [x] Implement state variables
    - [x] Collection configs mapping
    - [x] Minters tracking
    - [x] Royalty balance tracking
    - [x] Merkle root management
    - [x] Token and collection royalty data structures
    - [x] Analytics state variables tracking (`totalAccruedRoyalty`, `totalClaimedRoyalty`)
  - [x] Implement core functions
    - [x] registerCollection
    - [x] setTokenMinter
    - [x] batchUpdateRoyaltyData
    - [x] submitRoyaltyMerkleRoot
    - [x] claimRoyaltiesMerkle
    - [x] Update `batchUpdateRoyaltyData` to update `totalAccruedRoyalty`
    - [x] Update `claimRoyaltiesMerkle` to update `totalClaimedRoyalty`
    - [x] Implement analytics view functions (`totalAccrued`, `totalClaimed`)
  - [x] Implement ERC20 support functions
    - [x] addCollectionERC20Royalties
    - [x] claimERC20RoyaltiesMerkle
  - [x] Implement oracle interaction functions
    - [x] updateRoyaltyDataViaOracle
    - [x] setOracleUpdateMinBlockInterval
    - [x] fulfillRoyaltyData
  - [x] Implement events for all key operations
  - [x] Add OpenZeppelin dependencies
    - [x] AccessControl
    - [x] ReentrancyGuard

- [x] **CentralizedRoyaltyAdapter.sol**
  - [x] Define interface for NFT contract interaction
  - [x] Implement royaltyInfo pattern pointing to distributor
  - [x] Add helper view functions for royalty queries

- [x] **DiamondGenesisPass.sol**
  - [x] Implement ERC721 functionality
  - [x] Integrate CentralizedRoyaltyAdapter
  - [x] Implement minting functions
    - [x] whitelistMint
    - [x] mint (public)
    - [x] ownerMint (restricted)
  - [x] Implement direct payment routing to owner
  - [x] Add OpenZeppelin dependencies
    - [x] Ownable
    - [x] AccessControl
    - [x] ERC721

### Phase 2: Testing & Development Tools

- [x] **Unit Tests**
  - [x] Distributor contract tests
  - [x] Adapter pattern tests
  - [x] NFT contract tests
  - [x] Access control tests
  - [x] Merkle verification tests
  - [x] Add tests for on-chain analytics (state updates, view functions)

- [ ] **Integration Tests**
  - [x] Complete flow tests (mint → sale → royalty → claim)
  - [x] Multi-collection tests
  - [x] Oracle flow tests
  - [ ] Fix failing tests for double-counting in analytics
  - [ ] Fix tests for DiamondGenesisPass role management
  - [ ] Address other integration test failures

- [x] **Development Scripts**
  - [x] Deployment scripts
  - [x] Configuration scripts
  - [x] Merkle tree generation utilities
  - [x] Test helpers for marketplace sales simulation

#

### Phase 4: Deployment & Security

- [ ] **Security Audit**
  - [ ] Contract audit
  - [ ] Off-chain service security review
  - [ ] Access control verification
  - [ ] Merkle implementation validation

- [ ] **Mainnet Deployment**
  - [ ] Deploy distributor contract
  - [ ] Deploy and configure NFT contract
  - [ ] Set up proper role permissions
  - [ ] Transfer ownership to multisig
  - [ ] Configure service account permissions


## Implementation Notes

1. **Critical Path Dependencies:**
   - Distributor contract must be deployed first
   - NFT contract deployment requires distributor address
   - Off-chain services require deployed contracts

2. **Role Management Importance:**
   - Clearly separate multisig owner from service account
   - Document role transitions during deployment
   - Test access control restrictions thoroughly

3. **Gas Optimization Focus Areas:**
   - Merkle claim process
   - Batch update transactions
   - ERC20 claim process

4. **Security Priorities:**
   - Fund handling in distributor
   - Merkle root submission process
   - Access control enforcement 