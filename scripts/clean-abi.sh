#!/bin/bash
# scripts/clean-abi.sh - Generate clean ABIs for easy use

# Create output directory if it doesn't exist
mkdir -p ./abis

# Generate clean ABI for CentralizedRoyaltyDistributor
echo "Generating clean ABI for CentralizedRoyaltyDistributor..."
forge inspect src/programmable-royalties/CentralizedRoyaltyDistributor.sol:CentralizedRoyaltyDistributor abi --json > ./abis/CentralizedRoyaltyDistributor.json

# Generate clean ABI for DiamondGenesisPass
echo "Generating clean ABI for DiamondGenesisPass..."
forge inspect src/DiamondGenesisPass.sol:DiamondGenesisPass abi --json > ./abis/DiamondGenesisPass.json

echo "Clean ABIs generated successfully in the abis directory!" 