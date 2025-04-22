#!/bin/bash
# scripts/deploy.sh - Deploy contracts using Forge

# Load environment variables
source .env

# Set the RPC URL and private key from environment variables
RPC_URL=${RPC_URL:-"http://localhost:8545"}
PRIVATE_KEY=${PRIVATE_KEY}

# Check if PRIVATE_KEY is set
if [ -z "$PRIVATE_KEY" ]; then
  echo "Error: PRIVATE_KEY is not set. Please set it in your .env file."
  exit 1
fi

# Create directory for deployment info
mkdir -p ./deployments

# Deploy CentralizedRoyaltyDistributor
echo "Deploying CentralizedRoyaltyDistributor..."
DISTRIBUTOR_DEPLOY=$(forge create \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  src/programmable-royalties/CentralizedRoyaltyDistributor.sol:CentralizedRoyaltyDistributor)

# Extract distributor address from deployment output
DISTRIBUTOR_ADDRESS=$(echo "$DISTRIBUTOR_DEPLOY" | grep "Deployed to:" | awk '{print $3}')
echo "CentralizedRoyaltyDistributor deployed to: $DISTRIBUTOR_ADDRESS"

# Set parameters for DiamondGenesisPass
ROYALTY_FEE_NUMERATOR=750  # 7.5% royalty
CREATOR_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)

# Deploy DiamondGenesisPass
echo "Deploying DiamondGenesisPass..."
DGP_DEPLOY=$(forge create \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --constructor-args $DISTRIBUTOR_ADDRESS $ROYALTY_FEE_NUMERATOR $CREATOR_ADDRESS \
  src/DiamondGenesisPass.sol:DiamondGenesisPass)

# Extract DiamondGenesisPass address from deployment output
DGP_ADDRESS=$(echo "$DGP_DEPLOY" | grep "Deployed to:" | awk '{print $3}')
echo "DiamondGenesisPass deployed to: $DGP_ADDRESS"

# Save deployment addresses
cat > ./deployments/addresses.json << EOF
{
  "CentralizedRoyaltyDistributor": "$DISTRIBUTOR_ADDRESS",
  "DiamondGenesisPass": "$DGP_ADDRESS"
}
EOF

echo "Deployment complete! Addresses saved to ./deployments/addresses.json"

# Generate ABIs using cast
echo "Generating ABIs..."
mkdir -p ./abis

# Generate ABIs using cast
cast abi-encode "CentralizedRoyaltyDistributor()" > ./abis/CentralizedRoyaltyDistributor.json
cast abi-encode "DiamondGenesisPass(address,uint96,address)" > ./abis/DiamondGenesisPass.json

echo "ABI generation complete! ABIs saved to ./abis directory." 