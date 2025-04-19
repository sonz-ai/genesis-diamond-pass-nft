# Implementation Detail 3 – Missing On‑Chain Work

> **Scope** – only Solidity contracts; off‑chain APIs/oracles intentionally skipped.

---

## 🔧 TODO Checklist

- [ ] **DiamondGenesisPass**
  - [ ] `_afterTokenTransfer` override – sync `currentOwner` in distributor.
  - [ ] Call `centralizedDistributor.setTokenMinter` inside **_all_** mint paths (`_safeMint` wrapper).
  - [ ] Harmonise `supportsInterface` override chain.

- [ ] **CentralizedRoyaltyDistributor**
  - [ ] `updateTokenCurrentOwner(address,uint256,address)` – only collection.
  - [ ] Increment `totalAccruedRoyalty` in `submitRoyaltyMerkleRoot` (ETH) ⬆ analytics.
  - [ ] ETH `receive()` cannot trust `msg.sender`; add `depositRoyalty(address collection)` payable or require collection‑forward pattern.
  - [ ] Rate‑limit: permit first ever oracle call when `_lastOracleUpdateBlock==0`.
  - [ ] Double‑count guard already present; add block‑level skip if tx repeated across batches.

- [ ] **Minter‑Status Marketplace**
  - [ ] Storage structs for `Bid`, per‑token & collection pools.
  - [ ] `setMinterStatus` (onlyOwner).
  - [ ] `placeBid`, `acceptHighestBid`, `withdrawBid` with escrow tracking.
  - [ ] `viewBids`, `viewCollectionBids` public views.
  - [ ] Clear / refund losing bids on acceptance; non‑reentrancy.

- [ ] **ERC20 Royalty Merkle**
  - [ ] `submitERC20RoyaltyMerkleRoot(address collection,address token,bytes32 root,uint256 total)`.
  - [ ] Analytics vars `totalAccruedRoyaltyERC20` / `totalClaimedRoyaltyERC20`.
  - [ ] Mirror claim logic; update counters.

- [ ] **Testing**
  - [ ] Forge tests for analytics (accrued/claimed).
  - [ ] Transfer sync test (owner update).
  - [ ] Bid module full flow.
  - [ ] ERC20 claim path.

---

## 📝 Design Discussion

### 1 Ownership Synchronisation
Adding `_afterTokenTransfer` in **DiamondGenesisPass** keeps distributor’s `currentOwner` accurate, enabling off‑chain analytics and validating `onlyMinter` logic for bid acceptance.

### 2 Accrual Accounting Fixes
`submitRoyaltyMerkleRoot` now mutates `totalAccruedRoyalty`; claim path already touches `totalClaimedRoyalty`. Tests failing with `RoyaltyDistributor__InsufficientBalanceForRoot` stemmed from root > pool; ensure service computes tree ≤ pool.

### 3 Royalty Deposit Path
Marketplaces remit ETH from their own address: distributor’s `receive()` cannot map funds to a collection. Options:
1. **Forwarding Pattern** – collection implements `fallback()` to forward received royalties to `depositRoyalty{value: msg.value}(address(this))`.
2. **Off‑Chain Re‑deposit** – index `RoyaltyReceived` events and push matched value via `addCollectionRoyalties`.

Pattern 1 is preferred (gas‑cheap, deterministic).

### 4 Tradable Minter Status
To commoditise minter rights we extend distributor with bid escrow. Highest bid stored; on acceptance 100 % goes to contract **owner()** (collection creator), remainder to seller. All other bids refunded. Bid maps:
```solidity
struct Bid {address bidder; uint256 amount;}
mapping(uint256=>Bid[]) _tokenBids;
Bid[] _collectionBids;
mapping(address=>uint256) _pendingReturns; // withdraw pattern
```
Edge cases handled: reentrancy (checks‑effects‑interactions), outbid refunds, zero‑amount guard.

### 5 ERC20 Merkle Roots
ETH and ERC20 share core logic; token‑specific roots avoid state bloat. Add per‑token analytics and claim flags.

### 6 Oracle Rate‑Limit
Allow first invocation by testing `_lastOracleUpdateBlock==0`. Prevents false `OracleUpdateTooFrequent` failures on fresh contracts.

### 7 Gas & Security Notes
- Use `unchecked` math where safe.
- Consolidate storage packing (e.g. `CollectionConfig` fields order).
- External calls placed last; functions marked `nonReentrant` where ETH/token transfers occur.

---

This document should remain the single source of truth for outstanding Solidity work. Tick each item upon implementation & green tests. 🚀

