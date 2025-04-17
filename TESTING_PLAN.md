# Testing Plan

## Phase 1: Unit Tests

### CentralizedRoyaltyDistributor.sol
- [x] registerCollection
  - [x] should allow DEFAULT_ADMIN_ROLE to register and store config
  - [x] should revert if non-admin calls
  - [x] should reject duplicate registration
- [x] setTokenMinter
  - [x] should record minter when called by collection contract
  - [x] should revert when called by others
- [x] receive() fallback
  - [x] should accept ETH and increment `_collectionRoyalties`
- [x] batchUpdateRoyaltyData
  - [x] should allow SERVICE_ACCOUNT_ROLE to update per-token royalty data
  - [x] should emit `RoyaltyAttributed` with correct values
  - [x] should revert if called by unauthorized
  - [x] should increment `totalAccruedRoyalty`
- [x] submitRoyaltyMerkleRoot
  - [x] should accept valid merkle root when totalAmount ≤ balance
  - [x] should revert if totalAmount exceeds balance
  - [x] should update active root and emit `MerkleRootSubmitted`
  - [x] should revert if called by non-service-account
- [x] claimRoyaltiesMerkle
  - [x] should revert with invalid proof
  - [x] should transfer correct ETH for valid proof
  - [x] should mark recipient as claimed and emit `MerkleRoyaltyClaimed`
  - [x] should revert on double claim
  - [x] should increment `totalClaimedRoyalty`
- [x] ERC20 support
  - [x] addCollectionERC20Royalties: accept ERC20 transfer and update balance
  - [x] claimERC20RoyaltiesMerkle: mirror ETH claim tests for ERC20 tokens
- [x] Oracle functions (tests use mock oracle; no live API calls)
  - [x] setOracleUpdateMinBlockInterval: only admin, updates interval
  - [x] updateRoyaltyDataViaOracle: rate-limited; returns request ID; reverts if too soon
  - [x] fulfillRoyaltyData: simulate Chainlink callback via MockOracle; verify state update
  - [x] Oracle mock integration tests:
    - [x] deploy a Chainlink MockOracle (e.g., MockV3Aggregator) and link to distributor
    - [x] simulate full flow: request → capture request ID → call mock's fulfill → assert updated royalty data in distributor
- [x] Access control & security
  - [x] unauthorized role tests for all restricted functions
  - [x] reentrancy: simulate reentrancy on `claimRoyaltiesMerkle`
- [x] View functions
  - [x] totalAccrued() and totalClaimed(): correct initial and post-update values
  - [x] unclaimed(): calculate balance minus claimed

### CentralizedRoyaltyAdapter.sol
- [x] royaltyInfo
  - [x] should return distributor address and correct royalty amount
- [x] helper views
  - [x] should query distributor and return matching state

### DiamondGenesisPass.sol
- [x] ERC721 basics
  - [x] minting (`mint`, `whitelistMint`, `ownerMint`) with and without payment
  - [x] should forward `msg.value` to `owner()` address
  - [x] should assign tokenURI correctly
- [x] Access control
  - [x] onlyOwner for setting Merkle root and toggles
  - [x] onlyOwnerOrServiceAccount for burning and metadata updates
- [x] Integration with distributor
  - [x] should call `setTokenMinter` on mint
  - [x] royaltyInfo via adapter returns correct distributor outcome
- [x] Role management
  - [x] assign and revoke `SERVICE_ACCOUNT_ROLE`

## Phase 2: Integration Tests

- [x] Full system flow
  - [x] deploy distributor & NFT contracts, register collection
  - [x] user mint → simulate secondary sale → marketplace calls `royaltyInfo` and sends ETH
  - [x] batchUpdateRoyaltyData & submitMerkleRoot off‑chain simulation
  - [x] users claim with valid proofs
  - [x] verify minter and creator balances
- [x] Multi‑collection management
  - [x] deploy and register multiple NFT collections
  - [x] ensure isolated accounting and claims per collection
- [x] ERC20 royalty flow
  - [x] simulate ERC20 token transfers as royalties
  - [x] batch update and claim via Merkle proofs
- [x] Oracle flow
  - [x] simulate Chainlink callback for royalty data updates
  - [x] verify state changes in distributor

## Phase 3: Off‑Chain & Scripts

- [x] Merkle tree generation tests
  - [x] given sample balances, build tree and verify proofs in smart contract
- [x] Marketplace simulation scripts
  - [x] mock sale events and verify `batchUpdateRoyaltyData` inputs
- [x] Dashboard & CLI helpers
  - [x] test collection registration script
  - [x] test Merkle root submission CLI

## Phase 4: End‑to‑End & Security

- [x] Testnet deployment script
  - [x] deploy, configure roles, run smoke tests
- [x] Gas profiling
  - [x] measure gas usage for key operations (batch update, claim)
- [x] Audit checklist
  - [x] confirm all events emitted for transparency
  - [x] verify access control restrictions