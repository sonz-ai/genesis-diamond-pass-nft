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

- [ ] **CentralizedRoyaltyDistributor.sol**
  - [ ] Implement state variables
    - [ ] Collection configs mapping
    - [ ] Minters tracking
    - [ ] Royalty balance tracking
    - [ ] Merkle root management
    - [ ] Token and collection royalty data structures
    - [ ] Analytics state variables tracking (`totalAccruedRoyalty`, `totalClaimedRoyalty`)
  - [ ] Implement core functions
    - [ ] registerCollection
    - [ ] setTokenMinter
    - [ ] batchUpdateRoyaltyData
    - [ ] submitRoyaltyMerkleRoot
    - [ ] claimRoyaltiesMerkle
    - [ ] Update `batchUpdateRoyaltyData` to update `totalAccruedRoyalty`
    - [ ] Update `claimRoyaltiesMerkle` to update `totalClaimedRoyalty`
    - [ ] Implement analytics view functions (`totalAccrued`, `totalClaimed`)
  - [ ] Implement ERC20 support functions
    - [ ] addCollectionERC20Royalties
    - [ ] claimERC20RoyaltiesMerkle
  - [ ] Implement oracle interaction functions
    - [ ] updateRoyaltyDataViaOracle
    - [ ] setOracleUpdateMinBlockInterval
    - [ ] fulfillRoyaltyData
  - [ ] Implement events for all key operations
  - [ ] Add OpenZeppelin dependencies
    - [ ] AccessControl
    - [ ] ReentrancyGuard

- [ ] **CentralizedRoyaltyAdapter.sol**
  - [ ] Define interface for NFT contract interaction
  - [ ] Implement royaltyInfo pattern pointing to distributor
  - [ ] Add helper view functions for royalty queries

- [ ] **DiamondGenesisPass.sol**
  - [ ] Implement ERC721 functionality
  - [ ] Integrate CentralizedRoyaltyAdapter
  - [ ] Implement minting functions
    - [ ] whitelistMint
    - [ ] mint (public)
    - [ ] ownerMint (restricted)
  - [ ] Implement direct payment routing to owner
  - [ ] Add OpenZeppelin dependencies
    - [ ] Ownable
    - [ ] AccessControl
    - [ ] ERC721

### Phase 2: Testing & Development Tools

- [ ] **Unit Tests**
  - [ ] Distributor contract tests
  - [ ] Adapter pattern tests
  - [ ] NFT contract tests
  - [ ] Access control tests
  - [ ] Merkle verification tests
  - [ ] Add tests for on-chain analytics (state updates, view functions)

- [ ] **Integration Tests**
  - [ ] Complete flow tests (mint → sale → royalty → claim)
  - [ ] Multi-collection tests
  - [ ] Oracle flow tests

- [ ] **Development Scripts**
  - [ ] Deployment scripts
  - [ ] Configuration scripts
  - [ ] Merkle tree generation utilities
  - [ ] Test helpers for marketplace sales simulation

### Phase 3: Off-Chain Services

- [ ] **Batch Price Discovery & Royalty Service**
  - [ ] Implement Transfer event monitoring
  - [ ] Build marketplace API integrations
  - [ ] Create royalty calculation logic
  - [ ] Implement batchUpdateRoyaltyData call mechanism
  - [ ] Build Merkle tree generation system
  - [ ] Implement submitRoyaltyMerkleRoot call mechanism
  - [ ] Index on-chain analytics events (`Claimed`, `RoyaltyDataUpdated`) for fallback metrics

- [ ] **Oracle Implementation**
  - [ ] Develop Chainlink node adapter
  - [ ] Configure job specs for royalty data
  - [ ] Set up secure request/response flow

- [ ] **Administrative Dashboard**
  - [ ] Design UI for contract management
  - [ ] Manage multiple collections efficiently in a single interface
  - [ ] Implement collection registration interface
  - [ ] Create role management tools
  - [ ] Build royalty monitoring displays
  - [ ] Add Merkle root management tools
  - [ ] Display on-chain analytics (earned, claimed, unclaimed) via view functions and event indexing

- [ ] **User Claim Interface**
  - [ ] Design user-facing UI
  - [ ] Implement earned royalty displays
  - [ ] Create Merkle proof generation
  - [ ] Build claim transaction interface
  - [ ] Display user's earned, claimed, and unclaimed royalties via on-chain view functions

### Phase 4: Deployment & Security

- [ ] **Testnet Deployment**
  - [ ] Deploy to testnet
  - [ ] Configure initial contracts
  - [ ] Test full system flow
  - [ ] Fix identified issues

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

### Phase 5: Post-Deployment

- [ ] **Monitoring Setup**
  - [ ] Configure alerts for key contract events
  - [ ] Set up logs for off-chain services
  - [ ] Implement dashboard for system health

- [ ] **Documentation**
  - [ ] User guides for claiming royalties
  - [ ] Admin guides for system operation
  - [ ] Technical documentation for developers

- [ ] **Marketplace Coordination**
  - [ ] Verify royalty handling with major marketplaces
  - [ ] Test secondary sales on each marketplace
  - [ ] Document any marketplace-specific considerations

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