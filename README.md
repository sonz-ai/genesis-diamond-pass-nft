# Sonzai Diamond Genesis Pass NFT

This repository contains the smart contract for the Sonzai Diamond Genesis Pass NFT, an ERC721C-compliant NFT with royalties and whitelist functionality.

## Features

- ERC721C-compliant NFT with creator royalties
- 11% royalty on secondary sales
- Whitelist functionality using Chainlink Functions to verify addresses against a backend API
- Public mint functionality
- Mint price of 0.28 ETH
- Owner-only batch minting for team allocations
- Secure withdrawal of contract funds

## Contract Overview

The `SonzaiGenesisPass` contract is a production-ready implementation of an ERC721C NFT with the following features:

- **Whitelist Minting**: Uses Chainlink Functions to verify if an address is whitelisted by checking against the backend.sonz.ai API
- **Public Minting**: Allows anyone to mint tokens during the public sale phase
- **Royalties**: Implements ERC2981 for royalty information, with a fixed 11% royalty
- **Owner Controls**: Includes functions for the owner to manage the contract, including toggling mint phases and withdrawing funds

## Chainlink Functions Integration

This contract uses Chainlink Functions to verify whitelist status by querying the backend.sonz.ai API. Here's how it works:

1. A user calls `requestWhitelistVerification()` to initiate the verification process
2. The contract sends a request to Chainlink Functions with JavaScript code that:
   - Takes the user's address as input
   - Makes an HTTP request to get a CSRF token from the backend.sonz.ai API
   - Makes another HTTP request to check if the address is whitelisted, including the CSRF token
   - Returns the result (1 for whitelisted, 0 for not whitelisted)
3. Chainlink Functions executes the JavaScript code off-chain and returns the result
4. The contract's `fulfillRequest()` function processes the response and updates the user's whitelist status
5. If verified as whitelisted, the user can then call `whitelistMint()` to mint their NFT

This approach offers several advantages over traditional Merkle tree verification:
- Whitelist can be updated dynamically without changing the contract
- No need to generate and distribute Merkle proofs to users
- Can implement more complex whitelist logic (e.g., tiered whitelists, time-based restrictions)
- Integrates with existing backend systems

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

### Step 1: Set Up Chainlink Functions

1. Create a Chainlink Functions subscription:
   - Go to [functions.chain.link](https://functions.chain.link/)
   - Connect your wallet
   - Navigate to "Subscriptions" and click "Create Subscription"
   - Fund your subscription with LINK tokens (at least 5-10 LINK)
   - Note your Subscription ID

2. Get the DON ID and Router Address:
   - For Ethereum Mainnet:
     - Router: 0x65Dcc24F8ff9e51F10DCc7Ed1e4e2A61e6E14bd6
     - DON ID: 0x66756e2d657468657265756d2d6d61696e6e65742d31000000000000000000
   - For Sepolia Testnet:
     - Router: 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0
     - DON ID: 0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000

### Step 2: Configure Environment Variables

1. Create a `.env` file from the example:
   ```bash
   cp .env.example .env
   ```

2. Edit the `.env` file with your specific values:
   ```
   # Deployment
   PRIVATE_KEY=your_wallet_private_key_here

   # Chainlink Functions
   CHAINLINK_SUBSCRIPTION_ID=your_subscription_id_here
   CHAINLINK_DON_ID=your_don_id_here
   CHAINLINK_ROUTER_ADDRESS=your_router_address_here
   ENCRYPTED_SECRETS_REFERENCE=your_encrypted_secrets_reference_here

   # API Keys
   SONZAI_API_KEY=your_api_key_here
   SONZAI_CSRF_SECRET=your_csrf_secret_here

   # Contract Settings
   ROYALTY_RECEIVER_ADDRESS=your_royalty_receiver_address_here
   BASE_URI=https://api.sonzai.io/metadata/
   CALLBACK_GAS_LIMIT=300000
   ```

### Step 3: Set Up Whitelist Verification

Run the whitelist setup script:
```bash
npm run setup-whitelist
```

This script will guide you through:
- Setting up API key authentication for the backend.sonz.ai service
- Configuring Chainlink Functions parameters
- Testing the API connection
- Updating your environment variables

### Step 4: Set Up Chainlink Functions Secrets

Run the Chainlink Functions secrets setup script:
```bash
npm run setup-chainlink-secrets
```

This script will:
- Create a secrets.json file with your API key
- Encrypt the secrets using the Chainlink Functions CLI
- Generate the encrypted secrets file and DON public key
- Provide instructions for uploading your secrets to the Chainlink Functions UI

After running the script:
1. Upload your encrypted secrets to the Chainlink Functions UI
2. Note the encrypted secrets reference (gist ID)
3. Add this reference to your .env file as ENCRYPTED_SECRETS_REFERENCE

### Step 5: Deploy the Contract

Deploy the contract using Foundry:
```bash
forge script script/DeploySonzaiGenesisPass.s.sol:DeploySonzaiGenesisPass --rpc-url $RPC_URL --broadcast --verify
```

The deployment script will automatically use the values from your `.env` file. For any values not provided in the `.env` file, it will use default values.

### Step 6: Add Contract as Consumer

After deployment:
1. Go to the Chainlink Functions UI
2. Find your subscription
3. Add your contract address as a consumer
4. This allows your contract to use your Chainlink Functions subscription

### Step 7: Transfer Ownership to Gnosis Safe (Optional)

If you want to transfer ownership to a Gnosis Safe multisig:
```bash
npm run transfer-ownership
```

This script will:
- Connect to your deployed contract
- Transfer ownership to your Gnosis Safe multisig
- Optionally update the royalty receiver to the Safe as well
- Verify the ownership transfer was successful

All mint proceeds (0.28 ETH per mint) and royalties (11% of secondary sales) will then go to the Gnosis Safe.

## Security Considerations

- The `.env` file contains sensitive information and is excluded from git via `.gitignore`
- Never commit your private keys or API keys to the repository
- The deployment script loads sensitive values from environment variables rather than hardcoding them
- The API key for backend authentication is set up separately in the Chainlink Functions UI for additional security
- CSRF protection is implemented for all API calls to the backend.sonz.ai service to prevent cross-site request forgery attacks

## Chainlink Functions Details

### CSRF Protection

The backend.sonz.ai API uses CSRF (Cross-Site Request Forgery) protection to secure its endpoints. This requires:

1. Obtaining a CSRF token from the server before making API requests
2. Including this token in the headers of subsequent requests

The Chainlink Functions implementation handles this automatically by:
- First making a request to `https://backend.sonz.ai/api/v1/csrf-token` to get a CSRF token (this endpoint is public and doesn't require authentication)
- Then including this token in the `X-CSRF-Token` header when making the whitelist verification request

Example of how the CSRF flow works in JavaScript:

```javascript
// Step 1: Get a CSRF token (public endpoint, no authentication needed)
fetch('https://backend.sonz.ai/api/v1/csrf-token')
  .then(response => response.json())
  .then(data => {
    // Store the token for future requests
    const csrfToken = data.csrf_token;
    
    // Step 2: Use the token for authenticated requests
    fetch('https://backend.sonz.ai/api/v1/whitelist/0x123...', {
      method: 'GET',
      headers: {
        'X-API-Key': 'your-api-key',
        'X-CSRF-Token': csrfToken,
        'Content-Type': 'application/json'
      }
    });
  });
```

### Secrets Management

Chainlink Functions requires secure management of API keys and other secrets:

1. Secrets are stored in a JSON file and encrypted using the Chainlink Functions CLI
2. The encrypted secrets are uploaded to the Chainlink Functions DON (Decentralized Oracle Network)
3. The contract references these secrets using the encrypted secrets reference (gist ID)
4. When the Chainlink Functions request is executed, the DON decrypts the secrets and uses them to make the API request

This approach ensures that sensitive information like API keys is never stored on-chain.

### JavaScript Source Code

The JavaScript code executed by Chainlink Functions:
1. Takes the user's address as input
2. Retrieves the API key from the encrypted secrets
3. Makes an HTTP request to get a CSRF token
4. Makes another HTTP request to check if the address is whitelisted
5. Returns 1 if the address is whitelisted, 0 if not

This code is stored on-chain in the `requestWhitelistVerification()` function.

## Contract Interaction

After deployment, you can interact with the contract using the following functions:

### For Users

- `requestWhitelistVerification()`: Request verification of your address against the whitelist API
- `whitelistMint()`: Mint a token during the whitelist phase (after verification)
- `publicMint()`: Mint a token during the public phase
- `burn(uint256 tokenId)`: Burn a token you own

### For the Owner

- `setBaseURI(string calldata baseURI)`: Update the base URI for token metadata
- `toggleWhitelistMint(bool enabled)`: Enable or disable whitelist minting
- `togglePublicMint(bool enabled)`: Enable or disable public minting
- `mintBatch(address to, uint256 amount)`: Mint multiple tokens to a specific address
- `withdraw()`: Withdraw contract funds to the owner
- `setDefaultRoyalty(address receiver, uint96 feeNumerator)`: Update the default royalty information
- `setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator)`: Set royalty information for a specific token

## Claim UI

This project provides a web-based Claim Interface for users to claim their accrued royalties and an Admin Dashboard for managing distributions.

### Admin Dashboard Guide

- **Access**: Navigate to `https://app.genesis-pass.ai/admin-dashboard` and authenticate with your Service Account credentials.
- **Upload Merkle Root**: Go to the "Merkle Submissions" tab, enter the new root hash and total amount, and click "Submit".
- **Monitor Claims**: View real-time claim status under the "Claims" tab. Export claim logs as CSV for reporting.
- **Manage Service Accounts**: Under "Settings", add or remove service account addresses for collection management.

### User Claim Interface Guide

- **Connect Wallet**: Visit `https://app.genesis-pass.ai/claim` and connect your Ethereum wallet (e.g., MetaMask).
- **Enter Details**: The interface will detect your address and show your claimable amount.
- **Claim Royalties**: Click "Claim" to submit a transaction that claims your pending royalties.
- **View History**: See past claim transactions and amounts on the "History" tab.

## Off-Chain Architecture & APIs

### Architecture Diagram

The system architecture comprises a serverless backend, Merkle tree generator, and web UI components.
![Architecture Diagram](docs/architecture.png)

### API Documentation

- **GET** `/api/v1/claims?address=<walletAddress>`: Returns pending royalty amounts and proofs.
- **POST** `/api/v1/roots`: Submit new Merkle root data. Body: `{ "collection": "<address>", "merkleRoot": "<bytes32>", "totalAmount": <uint256> }`.
- **GET** `/api/v1/status`: Health check endpoint for off-chain services.

### Integration Guide

1. Fetch pending claims via the `/api/v1/claims` endpoint.
2. Use `merkletreejs` or similar to generate the Merkle proof from the returned data.
3. Call `claimRoyaltiesMerkle` or `claimERC20RoyaltiesMerkle` on the smart contract with the proof.
4. Monitor transaction status and update UI accordingly.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
