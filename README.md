# Sonzai Diamond Genesis Pass NFT

This repository contains the smart contract for the Sonzai Diamond Genesis Pass NFT, an ERC721C-compliant NFT with royalties and whitelist functionality.

## Features

- ERC721C-compliant NFT with creator royalties
- Advanced royalty distribution system splitting royalties between minters and creators
- Whitelist functionality using Merkle proofs for efficient and secure verification
- Public mint functionality
- Mint price of 0.1 ETH
- Owner-only batch minting for team allocations
- Secure withdrawal of contract funds
- Total supply of 888 tokens (212 reserved for whitelist, 288 for Pre-sale, 388 for public mint)

## Contract Overview

The `DiamondGenesisPass` contract is a production-ready implementation of an ERC721C NFT with the following features:

- **Whitelist Minting**: Uses Merkle proofs to efficiently verify if an address is whitelisted
- **Public Minting**: Allows anyone to mint tokens during the public sale phase
- **Royalties**: Implements a sophisticated royalty system with the following components:
  - **DiamondGenesisPass**: The main NFT contract that implements ERC721C standards and directs marketplace royalties to the CentralizedRoyaltyDistributor
  - **CentralizedRoyaltyAdapter**: A pattern contract implemented by DiamondGenesisPass for royalty routing
  - **CentralizedRoyaltyDistributor**: A distribution hub that receives royalties from marketplaces and handles splitting between minters and creators
- **Role-Based Access Control**: Distinct roles for contract ownership, service account operations, and royalty management
- **Owner Controls**: Includes functions for the owner to manage the contract, including toggling mint phases and withdrawing funds

## Royalty Distribution System

The system implements a sophisticated approach to royalty distribution:

- **Split Royalties**: Secondary market royalties are split between the original minter (e.g., 20%) and the creator/royalty recipient (e.g., 80%)
- **Direct Mint Payments**: Primary mint payments go directly to the creator/royalty recipient
- **Roles**:
  - **Contract Owner**: Controls administrative functions and can transfer ownership to a multisig
  - **Creator/Royalty Recipient**: Receives creator's share of royalties and primary mint proceeds
  - **Minters**: Receive their share of royalties from secondary sales of tokens they minted
  - **Service Account**: Has limited permissions for operational tasks without full admin control

### Royalty Flow

1. When an NFT is sold on a marketplace, the marketplace calls `royaltyInfo` on the NFT contract
2. The NFT contract directs the royalty payment to the CentralizedRoyaltyDistributor
3. The distributor receives and tracks royalties per collection
4. An off-chain service processes sale data and updates accrued royalties for minters and creators by calling `updateAccruedRoyalties` on the distributor
5. Minters and creators can claim their respective royalties through the distributor's `claimRoyalties` function

## Whitelist Verification

This contract uses Merkle proofs for efficient whitelist verification:

1. The contract owner sets a Merkle root using the `setMerkleRoot` function
2. The Merkle root is the top hash of a Merkle tree containing all whitelisted addresses
3. To mint using the whitelist, users provide a Merkle proof along with their mint transaction
4. The contract verifies the proof against the Merkle root to confirm eligibility
5. Once verified, the user can mint their allocated tokens

This approach offers several advantages:
- Extremely gas-efficient verification on-chain
- No need to store the entire whitelist on-chain
- Cryptographically secure verification
- Only need to update a single hash (the root) when changing the whitelist

## Development

This project uses [Foundry](https://book.getfoundry.sh/) for development, testing, and deployment.

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Git](https://git-scm.com/downloads)

### Setup

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd genesis-pass-nft
   ```

2. Initialize and update git submodules:
   ```bash
   git submodule update --init --recursive
   ```

3. Install dependencies:
   ```bash
   forge install
   npm install
   ```

4. Build the project:
   ```bash
   forge build
   ```

5. Run tests:
   ```bash
   forge test
   ```

## Deployment

To deploy the contract to a network, follow these steps:

### Step 1: Configure Environment Variables

1. Create a `.env` file from the example:
   ```bash
   cp .env.example .env
   ```

2. Edit the `.env` file with your specific values:
   ```
   # Deployment
   PRIVATE_KEY=your_wallet_private_key_here

   # Contract Settings
   ROYALTY_RECEIVER_ADDRESS=your_royalty_receiver_address_here
   BASE_URI=https://api.sonzai.io/metadata/
   ```

### Step 2: Generate Merkle Root for Whitelist

Run the whitelist generation script:
```bash
npm run generate-merkle-root
```

This script will:
- Take a list of whitelisted addresses from a specified file
- Generate a Merkle tree and calculate the root hash
- Provide the Merkle root to be set in the contract
- Generate a JSON file with proofs for each whitelisted address

### Step 3: Deploy the Contracts

Deploy the contracts in the following order:

1. Deploy the CentralizedRoyaltyDistributor:
```bash
forge script script/DeployCentralizedRoyaltyDistributor.s.sol:DeployCentralizedRoyaltyDistributor --rpc-url $RPC_URL --broadcast --verify
```

2. Deploy the DiamondGenesisPass contract:
```bash
forge script script/DeployDiamondGenesisPass.s.sol:DeployDiamondGenesisPass --rpc-url $RPC_URL --broadcast --verify
```

The deployment scripts will automatically use the values from your `.env` file.

### Step 4: Set Merkle Root and Activate Minting

After deployment:
1. Call `setMerkleRoot` with the generated Merkle root hash
2. To enable public minting later, call `setPublicMintActive(true)`

### Step 5: Transfer Ownership to Gnosis Safe (Optional)

If you want to transfer ownership to a Gnosis Safe multisig:
```bash
npm run transfer-ownership
```

This script will:
- Connect to your deployed contract
- Transfer ownership to your Gnosis Safe multisig
- Optionally update the royalty recipient to the Safe as well
- Verify the ownership transfer was successful

All mint proceeds (0.1 ETH per mint) and royalties will then be managed through the Gnosis Safe.

## Security Considerations

- The `.env` file contains sensitive information and is excluded from git via `.gitignore`
- Never commit your private keys or API keys to the repository
- The deployment script loads sensitive values from environment variables rather than hardcoding them
- The Merkle tree whitelist mechanism ensures cryptographic verification of whitelisted addresses
- The royalty distribution system includes checks to prevent reentrancy and unauthorized access
- Role-based access control ensures that only authorized addresses can perform sensitive operations

## Royalty Claim System

This project provides a direct accrual tracking system for royalty distribution and a web-based Claim Interface for users.

### How Royalty Accrual Works

1. **Royalty Collection**: The CentralizedRoyaltyDistributor contract receives royalty payments from marketplace sales
2. **Accrual Updates**: An off-chain service:
   - Monitors blockchain events for secondary sales
   - Fetches sale prices from marketplace APIs
   - Calculates royalty shares (minter/creator split)
   - Updates accrued royalties by calling `updateAccruedRoyalties` (restricted to service accounts)
3. **Claiming Process**: Users claim their accrued royalties by calling `claimRoyalties` on the distributor

### Admin Dashboard Guide

- **Access**: Navigate to `https://app.genesis-pass.ai/admin-dashboard` and authenticate with your Service Account credentials.
- **Update Accrued Royalties**: Process new sales and update recipient balances.
- **Monitor Claims**: View real-time claim status under the "Claims" tab. Export claim logs as CSV for reporting.
- **Manage Service Accounts**: Under "Settings", add or remove service account addresses for collection management.

### User Claim Interface Guide

- **Connect Wallet**: Visit `https://app.genesis-pass.ai/claim` and connect your Ethereum wallet (e.g., MetaMask).
- **Enter Details**: The interface will detect your address and show your claimable amount.
- **Claim Royalties**: Click "Claim" to submit a transaction that claims your pending royalties.
- **View History**: See past claim transactions and amounts on the "History" tab.

## Off-Chain Architecture & APIs

### Architecture Diagram

The system architecture comprises a serverless backend, royalty tracking service, and web UI components.
![Architecture Diagram](docs/architecture.png)

### API Documentation

- **GET** `/api/v1/royalties?address=<walletAddress>`: Returns pending royalty amounts for an address.
- **POST** `/api/v1/accrual`: Update accrued royalties for recipients. Requires service account authentication.
- **GET** `/api/v1/status`: Health check endpoint for off-chain services.

### Integration Guide

1. Fetch pending royalties via the `/api/v1/royalties` endpoint.
2. To claim royalties, call `claimRoyalties` on the CentralizedRoyaltyDistributor contract.
3. Monitor transaction status and update UI accordingly.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
