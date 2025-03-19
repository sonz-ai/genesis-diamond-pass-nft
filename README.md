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
   - Makes an HTTP request to the backend.sonz.ai API to check if the address is whitelisted
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

2. Install dependencies:
   ```bash
   forge install
   npm install
   ```

3. Build the project:
   ```bash
   forge build
   ```

4. Run tests:
   ```bash
   forge test
   ```

## Deployment

To deploy the contract to a network, you'll need to:

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

   # API Keys
   SONZAI_API_KEY=your_api_key_here

   # Contract Settings
   ROYALTY_RECEIVER_ADDRESS=your_royalty_receiver_address_here
   BASE_URI=https://api.sonzai.io/metadata/
   CALLBACK_GAS_LIMIT=300000
   ```

3. Set up the whitelist verification system:
   ```bash
   npm run setup-whitelist
   ```
   
   This script will guide you through:
   - Setting up API key authentication for the backend.sonz.ai service
   - Setting up Chainlink Functions for on-chain verification
   
   The script will provide you with all the necessary information to configure your deployment.

4. Deploy the contract:
   ```bash
   forge script script/DeploySonzaiGenesisPass.s.sol:DeploySonzaiGenesisPass --rpc-url $RPC_URL --broadcast --verify
   ```

   The deployment script will automatically use the values from your `.env` file. For any values not provided in the `.env` file, it will use default values.

## Security Considerations

- The `.env` file contains sensitive information and is excluded from git via `.gitignore`
- Never commit your private keys or API keys to the repository
- The deployment script loads sensitive values from environment variables rather than hardcoding them
- The API key for backend authentication is set up separately in the Chainlink Functions UI for additional security

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

## License

This project is licensed under the MIT License - see the LICENSE file for details.
