# Testing Plan

## Phase 1: Unit Tests

### CentralizedRoyaltyDistributor.sol
- registerCollection
  - should allow DEFAULT_ADMIN_ROLE to register and store config
  - should revert if non-admin calls
  - should reject duplicate registration
- setTokenMinter
  - should record minter when called by collection contract
  - should revert when called by others
- receive() fallback
  - should accept ETH and increment `_collectionRoyalties`
- batchUpdateRoyaltyData
  - should allow SERVICE_ACCOUNT_ROLE to update per-token royalty data
  - should emit `RoyaltyAttributed` with correct values
  - should revert if called by unauthorized
  - should increment `totalAccruedRoyalty`
- submitRoyaltyMerkleRoot
  - should accept valid merkle root when totalAmount ≤ balance
  - should revert if totalAmount exceeds balance
  - should update active root and emit `MerkleRootSubmitted`
  - should revert if called by non-service-account
- claimRoyaltiesMerkle
  - should revert with invalid proof
  - should transfer correct ETH for valid proof
  - should mark recipient as claimed and emit `MerkleRoyaltyClaimed`
  - should revert on double claim
  - should increment `totalClaimedRoyalty`
- ERC20 support
  - addCollectionERC20Royalties: accept ERC20 transfer and update balance
  - claimERC20RoyaltiesMerkle: mirror ETH claim tests for ERC20 tokens
- Oracle functions (tests use mock oracle; no live API calls)
  - setOracleUpdateMinBlockInterval: only admin, updates interval
  - updateRoyaltyDataViaOracle: rate-limited; returns request ID; reverts if too soon
  - fulfillRoyaltyData: simulate Chainlink callback via MockOracle; verify state update
  - Oracle mock integration tests:
    - deploy a Chainlink MockOracle (e.g., MockV3Aggregator) and link to distributor
    - simulate full flow: request → capture request ID → call mock’s fulfill → assert updated royalty data in distributor
- Access control & security
  - unauthorized role tests for all restricted functions
  - reentrancy: simulate reentrancy on `claimRoyaltiesMerkle`
- View functions
  - totalAccrued() and totalClaimed(): correct initial and post-update values
  - unclaimed(): calculate balance minus claimed

### CentralizedRoyaltyAdapter.sol
- royaltyInfo
  - should return distributor address and correct royalty amount
- helper views
  - should query distributor and return matching state

### DiamondGenesisPass.sol
- ERC721 basics
  - minting (`mint`, `whitelistMint`, `ownerMint`) with and without payment
  - should forward `msg.value` to `owner()` address
  - should assign tokenURI correctly
- Access control
  - onlyOwner for setting Merkle root and toggles
  - onlyOwnerOrServiceAccount for burning and metadata updates
- Integration with distributor
  - should call `setTokenMinter` on mint
  - royaltyInfo via adapter returns correct distributor outcome
- Role management
  - assign and revoke `SERVICE_ACCOUNT_ROLE`

## Phase 2: Integration Tests

- Full system flow
  - deploy distributor & NFT contracts, register collection
  - user mint → simulate secondary sale → marketplace calls `royaltyInfo` and sends ETH
  - batchUpdateRoyaltyData & submitMerkleRoot off‑chain simulation
  - users claim with valid proofs
  - verify minter and creator balances
- Multi‑collection management
  - deploy and register multiple NFT collections
  - ensure isolated accounting and claims per collection
- ERC20 royalty flow
  - simulate ERC20 token transfers as royalties
  - batch update and claim via Merkle proofs
- Oracle flow
  - simulate Chainlink callback for royalty data updates
  - verify state changes in distributor

## Phase 3: Off‑Chain & Scripts

- Merkle tree generation tests
  - given sample balances, build tree and verify proofs in smart contract
- Marketplace simulation scripts
  - mock sale events and verify `batchUpdateRoyaltyData` inputs
- Dashboard & CLI helpers
  - test collection registration script
  - test Merkle root submission CLI

## Phase 4: End‑to‑End & Security

- Testnet deployment script
  - deploy, configure roles, run smoke tests
- Gas profiling
  - measure gas usage for key operations (batch update, claim)
- Audit checklist
  - confirm all events emitted for transparency
  - verify access control restrictions