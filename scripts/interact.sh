#!/bin/bash
# scripts/interact.sh - Interact with deployed contracts using Forge/Cast

# Load environment variables and deployment addresses
source .env
ADDRESSES_FILE="./deployments/addresses.json"

# Check if addresses file exists
if [ ! -f "$ADDRESSES_FILE" ]; then
  echo "Error: Deployment addresses file not found at $ADDRESSES_FILE"
  echo "Please run the deployment script first."
  exit 1
fi

# Extract contract addresses
DISTRIBUTOR_ADDRESS=$(jq -r '.CentralizedRoyaltyDistributor' "$ADDRESSES_FILE")
DGP_ADDRESS=$(jq -r '.DiamondGenesisPass' "$ADDRESSES_FILE")

echo "Interacting with contracts..."
echo "DiamondGenesisPass: $DGP_ADDRESS"
echo "CentralizedRoyaltyDistributor: $DISTRIBUTOR_ADDRESS"

# Set RPC URL from environment or use default
RPC_URL=${RPC_URL:-"http://localhost:8545"}

echo -e "\n--- DiamondGenesisPass Contract Interactions ---"

# Get total supply
echo "Checking total supply..."
TOTAL_SUPPLY=$(cast call $DGP_ADDRESS "totalSupply()(uint256)" --rpc-url $RPC_URL)
echo "Current total supply: $TOTAL_SUPPLY"

# Check if public minting is active
# Note: This might not be directly accessible if the variable is private
echo "Checking if public minting is active..."
IS_PUBLIC_MINT_ACTIVE=$(cast call $DGP_ADDRESS "isPublicMintActive()(bool)" --rpc-url $RPC_URL 2>/dev/null || echo "Not directly accessible")
echo "Is public minting active? $IS_PUBLIC_MINT_ACTIVE"

# Get whitelist minted count
echo "Checking whitelist minted count..."
WHITELIST_MINTED=$(cast call $DGP_ADDRESS "whitelistMintedCount()(uint256)" --rpc-url $RPC_URL)
echo "Whitelist minted count: $WHITELIST_MINTED"

echo -e "\n--- CentralizedRoyaltyDistributor Contract Interactions ---"

# Check if the collection is registered with the distributor
echo "Checking if DiamondGenesisPass is registered with the distributor..."
IS_REGISTERED=$(cast call $DISTRIBUTOR_ADDRESS "isCollectionRegistered(address)(bool)" $DGP_ADDRESS --rpc-url $RPC_URL)
echo "Is DiamondGenesisPass registered? $IS_REGISTERED"

# If registered, get collection configuration
if [ "$IS_REGISTERED" = "true" ]; then
  echo "Getting collection configuration..."
  COLLECTION_CONFIG=$(cast call $DISTRIBUTOR_ADDRESS "getCollectionConfig(address)((uint256,uint256,uint256,address,bool))" $DGP_ADDRESS --rpc-url $RPC_URL)
  echo "Collection config: $COLLECTION_CONFIG"
  
  # Parse the configuration (this depends on the output format)
  # You may need to adjust this based on actual output
  # echo "Royalty Fee Numerator: $(echo $COLLECTION_CONFIG | cut -d' ' -f1)"
  # echo "Minter Shares: $(echo $COLLECTION_CONFIG | cut -d' ' -f2)"
  # echo "Creator Shares: $(echo $COLLECTION_CONFIG | cut -d' ' -f3)"
  # echo "Creator Address: $(echo $COLLECTION_CONFIG | cut -d' ' -f4)"
fi

# Check unclaimed royalties
echo "Checking unclaimed royalties..."
UNCLAIMED_ROYALTIES=$(cast call $DGP_ADDRESS "totalUnclaimedRoyalties()(uint256)" --rpc-url $RPC_URL)
echo "Unclaimed royalties: $UNCLAIMED_ROYALTIES wei"

echo -e "\nInteraction complete!" 