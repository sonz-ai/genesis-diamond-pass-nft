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
  - [ ] Full lifecycle: mint → sale → `batchUpdateRoyaltyData` → `submitRoyaltyMerkleRoot` → claims
  - [ ] Multi‑collection isolation
  - [ ] ERC20 and oracle end‑to‑end flows

## Off-Chain Services & Tools

- Batch Price Discovery & Royalty Service
- Merkle tree generator and proof CLI
- Chainlink oracle adapter and job specs
- Deployment and Merkle submission scripts

## Deployment & Security

- Write deployment scripts for testnet and mainnet
- Configure multisig roles and access transfers
- Prepare gas profiling and audit checklist

## Documentation

- Update README with setup, usage, test, and deploy instructions
- Add admin and user guides for claim UI
- Document off‑chain architecture and APIs
