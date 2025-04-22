#!/bin/bash
# scripts/generate-abi.sh - Generate ABIs using Forge/Cast

# Create output directory if it doesn't exist
mkdir -p ./abis

# Generate ABI for CentralizedRoyaltyDistributor
echo "Generating ABI for CentralizedRoyaltyDistributor..."
forge inspect src/programmable-royalties/CentralizedRoyaltyDistributor.sol:CentralizedRoyaltyDistributor abi > ./abis/CentralizedRoyaltyDistributor_raw.json
echo "CentralizedRoyaltyDistributor ABI saved to ./abis/CentralizedRoyaltyDistributor.json"

# Generate ABI for DiamondGenesisPass
echo "Generating ABI for DiamondGenesisPass..."
forge inspect src/DiamondGenesisPass.sol:DiamondGenesisPass abi > ./abis/DiamondGenesisPass_raw.json
echo "DiamondGenesisPass ABI saved to ./abis/DiamondGenesisPass.json"

# Format the ABIs in a more usable structure
for contract in CentralizedRoyaltyDistributor DiamondGenesisPass; do
  # Clean up the forge output - remove any formatting issues
  cat ./abis/${contract}_raw.json | tr -d '\r' | tr -d '\t' > ./abis/${contract}_clean.json
  
  # Create formatted file with proper JSON structure
  echo "{\"abi\": $(cat ./abis/${contract}_clean.json)}" > ./abis/${contract}.json
  
  # Remove temporary files
  rm ./abis/${contract}_raw.json ./abis/${contract}_clean.json
done

echo "ABI generation complete! ABIs are saved in the ./abis directory." 