# DiamondGenesisPass NFT Deployment Guide

This guide explains how to deploy the DiamondGenesisPass NFT contract and interact with it using Forge (Foundry).

## Prerequisites

- [Foundry](https://getfoundry.sh/) installed (includes `forge`, `cast`, and `anvil`)
- Bash shell
- An Ethereum wallet with ETH for deployment
- A private key for deployment

## Installation

1. Install Foundry if you haven't already:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Configure your environment:

Create a `.env` file with the following content:

```
PRIVATE_KEY=your_private_key_here
RPC_URL=your_rpc_url_here
```

Make the scripts executable:

```bash
chmod +x scripts/*.sh
```

## Deployment Process

### 1. Build the contracts

```bash
forge build
```

### 2. Deploy the contracts

```bash
./scripts/deploy.sh
```

This script will:
1. Deploy the CentralizedRoyaltyDistributor contract
2. Deploy the DiamondGenesisPass contract with the distributor address
3. Save the contract addresses to the `deployments/addresses.json` file
4. Generate the contract ABIs in the `abis` directory

### 3. Generate ABIs only (optional)

If you only need to generate the ABIs without deploying:

```bash
forge build
./scripts/generate-abi.sh
```

This will extract the ABIs from the compiled contracts and save them to the `abis` directory.

## Contract Interaction

### Using the interaction script

```bash
./scripts/interact.sh
```

This script demonstrates how to:
- Connect to both contracts
- Check if public minting is active
- Get the current token supply
- Check the whitelist minted count
- Verify if the collection is registered with the distributor
- View unclaimed royalties

### Common Owner Operations

Use the owner actions script for common management tasks:

```bash
./scripts/owner-actions.sh
```

This interactive script allows you to:
1. Set the merkle root for whitelist minting
2. Enable/disable public minting
3. Set the base URI for metadata
4. Update the royalty recipient
5. Mint tokens as the contract owner

### Manual Owner Operations with Cast

You can also perform these operations manually using `cast`:

1. Set the merkle root for whitelist minting:
```bash
cast send $DGP_ADDRESS "setMerkleRoot(bytes32)" "0x..." --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

2. Enable public minting:
```bash
cast send $DGP_ADDRESS "setPublicMintActive(bool)" true --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

3. Update metadata URI:
```bash
cast send $DGP_ADDRESS "setBaseURI(string)" "https://your-api.com/metadata/" --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

4. Update royalty recipient:
```bash
cast send $DGP_ADDRESS "setRoyaltyRecipient(address)" "0x..." --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

## ABIs for Frontend Integration

The contract ABIs are saved in the `abis` directory after deployment or running the `generate-abi.sh` script. Use these files for frontend integration:

- `abis/DiamondGenesisPass.json`
- `abis/CentralizedRoyaltyDistributor.json`

Example of loading the ABI in a frontend application:

```javascript
import DiamondGenesisPassABI from '../abis/DiamondGenesisPass.json';
import { ethers } from 'ethers';

// Connect to the contract
const provider = new ethers.providers.Web3Provider(window.ethereum);
const signer = provider.getSigner();
const contractAddress = '0x...'; // DiamondGenesisPass contract address
const contract = new ethers.Contract(contractAddress, DiamondGenesisPassABI.abi, signer);

// Now you can interact with the contract
const supply = await contract.totalSupply();
console.log("Current supply:", supply.toString());
```

## Important Contract Parameters

- **Max Supply**: 888 tokens
- **Whitelist Supply**: 212 tokens
- **Public Mint Price**: 0.1 ETH
- **Royalty Distribution**: 20% to minter, 80% to creator

## Security Considerations

- After deployment, verify that the contract owner is correct
- Test whitelist minting with a few addresses before full launch
- Ensure the merkle root is correctly set before enabling whitelisting
- Consider multisig ownership for enhanced security 