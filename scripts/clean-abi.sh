#!/bin/bash
# scripts/clean-abi.sh - Generate clean ABIs for easy use

# Create output directory if it doesn't exist
mkdir -p ./abis

# Generate clean ABI for CentralizedRoyaltyDistributor
echo "Generating clean ABI for CentralizedRoyaltyDistributor..."
forge inspect src/programmable-royalties/CentralizedRoyaltyDistributor.sol:CentralizedRoyaltyDistributor abi > ./abis/CentralizedRoyaltyDistributor_raw.json

# Generate clean ABI for DiamondGenesisPass
echo "Generating clean ABI for DiamondGenesisPass..."
forge inspect src/DiamondGenesisPass.sol:DiamondGenesisPass abi > ./abis/DiamondGenesisPass_raw.json

# Process the ABIs using jq to format them nicely
if command -v jq >/dev/null 2>&1; then
    echo "Formatting ABIs with jq..."
    jq . ./abis/CentralizedRoyaltyDistributor_raw.json > ./abis/CentralizedRoyaltyDistributor.json
    jq . ./abis/DiamondGenesisPass_raw.json > ./abis/DiamondGenesisPass.json
    
    # Remove the raw files
    rm ./abis/*_raw.json
else
    echo "jq not found, using raw ABIs instead."
    mv ./abis/CentralizedRoyaltyDistributor_raw.json ./abis/CentralizedRoyaltyDistributor.json
    mv ./abis/DiamondGenesisPass_raw.json ./abis/DiamondGenesisPass.json
fi

echo "Clean ABIs generated successfully in the abis directory!" 