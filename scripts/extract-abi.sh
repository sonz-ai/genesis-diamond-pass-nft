#!/bin/bash
# scripts/extract-abi.sh - Extract contract ABIs in clean JSON format

# Create output directory if it doesn't exist
mkdir -p ./abis

echo "Building contracts..."
forge build --quiet

echo "Extracting ABIs..."

# DiamondGenesisPass ABI
echo "Extracting DiamondGenesisPass ABI..."
# Use cast to get a clean JSON output
cast abi-encode "$(cat artifacts/src/DiamondGenesisPass.sol/DiamondGenesisPass.json | jq -r '.abi')" > ./abis/DiamondGenesisPass.json 2>/dev/null || {
  echo "Failed to extract DiamondGenesisPass ABI. Using forge to get raw artifact..."
  cp artifacts/src/DiamondGenesisPass.sol/DiamondGenesisPass.json ./abis/DiamondGenesisPass_full.json
  echo "Extracting ABI only..."
  cat ./abis/DiamondGenesisPass_full.json | jq '.abi' > ./abis/DiamondGenesisPass.json
  rm ./abis/DiamondGenesisPass_full.json
}

# CentralizedRoyaltyDistributor ABI
echo "Extracting CentralizedRoyaltyDistributor ABI..."
# Use cast to get a clean JSON output
cast abi-encode "$(cat artifacts/src/programmable-royalties/CentralizedRoyaltyDistributor.sol/CentralizedRoyaltyDistributor.json | jq -r '.abi')" > ./abis/CentralizedRoyaltyDistributor.json 2>/dev/null || {
  echo "Failed to extract CentralizedRoyaltyDistributor ABI. Using forge to get raw artifact..."
  cp artifacts/src/programmable-royalties/CentralizedRoyaltyDistributor.sol/CentralizedRoyaltyDistributor.json ./abis/CentralizedRoyaltyDistributor_full.json
  echo "Extracting ABI only..."
  cat ./abis/CentralizedRoyaltyDistributor_full.json | jq '.abi' > ./abis/CentralizedRoyaltyDistributor.json
  rm ./abis/CentralizedRoyaltyDistributor_full.json
}

echo "ABIs extracted successfully to the abis directory!" 