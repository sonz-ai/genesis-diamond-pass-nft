#!/bin/bash
# scripts/owner-actions.sh - Common owner actions for DiamondGenesisPass

# Load environment variables and deployment addresses
source .env
ADDRESSES_FILE="./deployments/addresses.json"

# Check if addresses file exists
if [ ! -f "$ADDRESSES_FILE" ]; then
  echo "Error: Deployment addresses file not found at $ADDRESSES_FILE"
  echo "Please run the deployment script first."
  exit 1
fi

# Check if private key is set
if [ -z "$PRIVATE_KEY" ]; then
  echo "Error: PRIVATE_KEY is not set. Please set it in your .env file."
  exit 1
fi

# Extract contract address
DGP_ADDRESS=$(jq -r '.DiamondGenesisPass' "$ADDRESSES_FILE")
echo "DiamondGenesisPass: $DGP_ADDRESS"

# Set RPC URL from environment or use default
RPC_URL=${RPC_URL:-"http://localhost:8545"}

# Function to show the menu
show_menu() {
  echo -e "\nDiamondGenesisPass Owner Actions:"
  echo "1) Set Merkle Root for whitelist"
  echo "2) Enable/Disable Public Minting"
  echo "3) Set Base URI for metadata"
  echo "4) Update Royalty Recipient"
  echo "5) Mint a token as owner"
  echo "q) Quit"
  echo -n "Select an option: "
}

# Function to set merkle root
set_merkle_root() {
  echo -n "Enter the merkle root (0x format): "
  read MERKLE_ROOT
  
  echo "Setting merkle root to $MERKLE_ROOT..."
  cast send $DGP_ADDRESS "setMerkleRoot(bytes32)" $MERKLE_ROOT \
    --private-key $PRIVATE_KEY \
    --rpc-url $RPC_URL
  
  echo "Merkle root set successfully!"
}

# Function to toggle public minting
toggle_public_minting() {
  echo -n "Enable public minting? (y/n): "
  read CHOICE
  
  if [[ $CHOICE =~ ^[Yy]$ ]]; then
    STATUS=true
  else
    STATUS=false
  fi
  
  echo "Setting public minting to $STATUS..."
  cast send $DGP_ADDRESS "setPublicMintActive(bool)" $STATUS \
    --private-key $PRIVATE_KEY \
    --rpc-url $RPC_URL
  
  echo "Public minting status updated!"
}

# Function to set base URI
set_base_uri() {
  echo -n "Enter the base URI for metadata (e.g., https://example.com/metadata/): "
  read BASE_URI
  
  echo "Setting base URI to $BASE_URI..."
  cast send $DGP_ADDRESS "setBaseURI(string)" "$BASE_URI" \
    --private-key $PRIVATE_KEY \
    --rpc-url $RPC_URL
  
  echo "Base URI set successfully!"
}

# Function to update royalty recipient
update_royalty_recipient() {
  echo -n "Enter the new royalty recipient address: "
  read RECIPIENT
  
  echo "Updating royalty recipient to $RECIPIENT..."
  cast send $DGP_ADDRESS "setRoyaltyRecipient(address)" $RECIPIENT \
    --private-key $PRIVATE_KEY \
    --rpc-url $RPC_URL
  
  echo "Royalty recipient updated successfully!"
}

# Function to mint a token as owner
owner_mint() {
  echo -n "Enter the recipient address: "
  read RECIPIENT
  
  echo "Minting token to $RECIPIENT..."
  cast send $DGP_ADDRESS "mintOwner(address)" $RECIPIENT \
    --private-key $PRIVATE_KEY \
    --rpc-url $RPC_URL
  
  echo "Token minted successfully!"
}

# Main loop
while true; do
  show_menu
  read OPTION
  
  case $OPTION in
    1) set_merkle_root ;;
    2) toggle_public_minting ;;
    3) set_base_uri ;;
    4) update_royalty_recipient ;;
    5) owner_mint ;;
    q|Q) echo "Exiting..."; exit 0 ;;
    *) echo "Invalid option. Please try again." ;;
  esac
done 