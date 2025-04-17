# Next Steps

Based on the design, implementation and testing plans, and current code, here are the remaining tasks:

## Smart Contracts

- CentralizedRoyaltyDistributor.sol
  - [x] Implement ERC20 support: `addCollectionERC20Royalties`, `claimERC20RoyaltiesMerkle`
  - [x] Add oracle methods: `updateRoyaltyDataViaOracle`, `fulfillRoyaltyData`
  - [x] Finalize analytics: update `totalAccruedRoyalty`, `totalClaimedRoyalty`, add view functions `totalAccrued()`, `totalClaimed()`
- DiamondGenesisPass.sol
  - [x] Complete mint functions: `whitelistMint`, `safeMint`, `ownerMint` with proper perks and events
  - [x] Ensure `onlyOwnerOrServiceAccount` guards metadata, burn, and sale-recording operations
  - [x] Verify payment routing to owner and emit `SaleRecorded`
  - [x] Handle `registerCollection` fallback behavior and error logging
- CentralizedRoyaltyAdapter.sol
  - [x] Validate interface compliance and gas optimizations

## Testing

- Unit tests:
  - [x] ERC20 royalty flow
  - [x] Oracle functions with mock Chainlink
  - [x] Analytics views (`unclaimed`, `totalAccrued`, `totalClaimed`)
  - [x] Access control and reentrancy on all restricted functions
- Integration tests:
  - [x] Full lifecycle: mint → sale → `batchUpdateRoyaltyData` → `submitRoyaltyMerkleRoot` → claims
  - [x] Multi‑collection isolation
  - [x] ERC20 and oracle end‑to‑end flows

## Off-Chain Services & Tools

- [ ] Batch Price Discovery & Royalty Service
  - [ ] Transfer event monitoring script
  - [ ] Marketplace API integration
  - [ ] Royalty calculation logic
- [ ] Merkle tree generator and proof CLI
  - [ ] Generate Merkle trees from royalty data
  - [ ] Create proofs for claiming
- [ ] Chainlink oracle adapter and job specs
  - [ ] Oracle node configuration
  - [ ] Job specification for royalty data
- [ ] Deployment and Merkle submission scripts
  - [ ] Testnet deployment script
  - [ ] Mainnet deployment script
  - [ ] Merkle root submission script

## Deployment & Security

- [ ] Write deployment scripts for testnet and mainnet
  - [ ] Deploy distributor contract
  - [ ] Deploy NFT contract
  - [ ] Register collection
  - [ ] Transfer ownership to multisig
- [ ] Configure multisig roles and access transfers
  - [ ] Set up multisig as owner
  - [ ] Configure service account roles
- [ ] Prepare gas profiling and audit checklist
  - [ ] Optimize gas usage for key functions
  - [ ] Security audit preparation

## Documentation

- [x] Update README with setup, usage, test, and deploy instructions
  - [x] Project overview
  - [x] Installation and setup
  - [x] Testing instructions
  - [x] Deployment guide
- [x] Add admin and user guides for claim UI
  - [x] Admin dashboard guide
  - [x] User claim interface guide
- [x] Document off‑chain architecture and APIs
  - [x] Architecture diagram
  - [x] API documentation
  - [x] Integration guide
