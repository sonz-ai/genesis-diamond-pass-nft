// scripts/interact.js
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  // Get the signer
  const [owner] = await ethers.getSigners();
  console.log("Interacting with contracts using account:", owner.address);

  // Load contract data
  const dgpData = loadContractData("DiamondGenesisPass");
  const distributorData = loadContractData("CentralizedRoyaltyDistributor");

  // Connect to contracts
  const diamondGenesisPass = new ethers.Contract(
    dgpData.address,
    dgpData.abi,
    owner
  );

  const royaltyDistributor = new ethers.Contract(
    distributorData.address,
    distributorData.abi,
    owner
  );

  console.log("Connected to DiamondGenesisPass at:", diamondGenesisPass.address);
  console.log("Connected to CentralizedRoyaltyDistributor at:", royaltyDistributor.address);

  // Example interactions with DiamondGenesisPass
  console.log("\n--- DiamondGenesisPass Contract Interactions ---");
  
  // Check if public minting is active
  try {
    const isPublicMintActive = await diamondGenesisPass.isPublicMintActive();
    console.log("Is public minting active?", isPublicMintActive);
    
    // If not active, activate it
    if (!isPublicMintActive) {
      console.log("Activating public minting...");
      const tx = await diamondGenesisPass.setPublicMintActive(true);
      await tx.wait();
      console.log("Public minting activated!");
    }
  } catch (error) {
    console.log("Error checking mint status (isPublicMintActive is likely not directly exposed)");
  }
  
  // Get the current supply
  const totalSupply = await diamondGenesisPass.totalSupply();
  console.log("Current total supply:", totalSupply.toString());
  
  // Get the royalty recipient
  try {
    const creator = await diamondGenesisPass.creator();
    console.log("Current royalty recipient:", creator);
  } catch (error) {
    console.log("Error getting creator (function may not be directly exposed)");
  }

  // Example interactions with CentralizedRoyaltyDistributor
  console.log("\n--- CentralizedRoyaltyDistributor Contract Interactions ---");
  
  // Check if the collection is registered
  try {
    const isRegistered = await royaltyDistributor.isCollectionRegistered(diamondGenesisPass.address);
    console.log("Is DiamondGenesisPass registered with distributor?", isRegistered);
    
    // Get collection configuration if registered
    if (isRegistered) {
      const collectionConfig = await royaltyDistributor.getCollectionConfig(diamondGenesisPass.address);
      console.log("Collection configuration:");
      console.log("  Royalty Fee Numerator:", collectionConfig.royaltyFeeNumerator.toString());
      console.log("  Minter Shares:", collectionConfig.minterShares.toString());
      console.log("  Creator Shares:", collectionConfig.creatorShares.toString());
      console.log("  Creator Address:", collectionConfig.creator);
    }
  } catch (error) {
    console.error("Error checking collection registration:", error);
  }
  
  // Check unclaimed royalties
  try {
    const unclaimedRoyalties = await diamondGenesisPass.totalUnclaimedRoyalties();
    console.log("Unclaimed royalties:", ethers.utils.formatEther(unclaimedRoyalties), "ETH");
  } catch (error) {
    console.error("Error checking unclaimed royalties:", error);
  }
}

function loadContractData(contractName) {
  try {
    const filePath = path.join(__dirname, "../abis", contractName + ".json");
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    throw new Error(`Failed to load contract data for ${contractName}: ${error.message}`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 