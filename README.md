# Telemafia Diamond Genesis Pass NFT

This repository contains the smart contract for the Telemafia Diamond Genesis Pass NFT, an ERC721C-compliant NFT with royalties and whitelist functionality.

## Features

- ERC721C-compliant NFT with creator royalties
- 11% royalty on secondary sales
- Whitelist functionality using Chainlink Functions to verify addresses against a Supabase database
- Public mint functionality
- Mint price of 0.28 ETH
- Owner-only batch minting for team allocations
- Secure withdrawal of contract funds

## Contract Overview

The `TelemafiaGenesisPass` contract is a production-ready implementation of an ERC721C NFT with the following features:

- **Whitelist Minting**: Uses Chainlink Functions to verify if an address is whitelisted by checking against a Supabase database
- **Public Minting**: Allows anyone to mint tokens during the public sale phase
- **Royalties**: Implements ERC2981 for royalty information, with a fixed 11% royalty
- **Owner Controls**: Includes functions for the owner to manage the contract, including toggling mint phases and withdrawing funds

## Chainlink Functions Integration

This contract uses Chainlink Functions to verify whitelist status by querying a Supabase database. Here's how it works:

1. A user calls `requestWhitelistVerification()` to initiate the verification process
2. The contract sends a request to Chainlink Functions with JavaScript code that:
   - Takes the user's address as input
   - Makes an HTTP request to the Supabase API to check if the address is in the whitelist table
   - Returns the result (1 for whitelisted, 0 for not whitelisted)
3. Chainlink Functions executes the JavaScript code off-chain and returns the result
4. The contract's `fulfillRequest()` function processes the response and updates the user's whitelist status
5. If verified as whitelisted, the user can then call `whitelistMint()` to mint their NFT

This approach offers several advantages over traditional Merkle tree verification:
- Whitelist can be updated dynamically without changing the contract
- No need to generate and distribute Merkle proofs to users
- Can implement more complex whitelist logic (e.g., tiered whitelists, time-based restrictions)
- Integrates with existing database systems

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

1. Set up your environment variables:
   ```bash
   export PRIVATE_KEY=your_private_key
   export RPC_URL=your_rpc_url
   ```

2. Set up the whitelist verification system:
   ```bash
   # Install dependencies
   npm install
   
   # Run the setup script
   npm run setup-whitelist
   ```
   
   This script will guide you through:
   - Setting up a Supabase database for whitelist verification
   - Adding addresses to the whitelist
   - Setting up Chainlink Functions for on-chain verification
   
   The script will provide you with all the necessary information to configure your deployment.

4. Update the deployment script (`script/DeployTelemafiaGenesisPass.s.sol`) with your desired parameters:
   - Set the `royaltyReceiver` address to receive royalties
   - Set the `baseURI` for your token metadata
   - Set the `router` address for Chainlink Functions
   - Set the `donId` for Chainlink Functions
   - Set the `subscriptionId` for Chainlink Functions
   - Set the `callbackGasLimit` for Chainlink Functions
   - Set the `supabaseUrl` for your Supabase project
   - Set the `supabaseKey` (this will be encrypted separately)

5. Deploy the contract:
   ```bash
   forge script script/DeployTelemafiaGenesisPass.s.sol:DeployTelemafiaGenesisPass --rpc-url $RPC_URL --broadcast --verify
   ```

## Contract Interaction

After deployment, you can interact with the contract using the following functions:

### For Users

- `requestWhitelistVerification()`: Request verification of your address against the whitelist database
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
