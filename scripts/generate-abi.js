const fs = require("fs");
const path = require("path");

async function main() {
  // Define paths
  const artifactsDir = path.join(__dirname, "../artifacts");
  const outputDir = path.join(__dirname, "../abis");
  
  // Ensure output directory exists
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }
  
  // Contract names
  const contracts = [
    "CentralizedRoyaltyDistributor",
    "DiamondGenesisPass"
  ];
  
  // Extract and save ABIs
  contracts.forEach(contractName => {
    try {
      // Find contract artifact path
      let artifactPath;
      if (contractName === "CentralizedRoyaltyDistributor") {
        artifactPath = path.join(artifactsDir, "src/programmable-royalties", contractName + ".sol", contractName + ".json");
      } else { // DiamondGenesisPass
        artifactPath = path.join(artifactsDir, "src", contractName + ".sol", contractName + ".json");
      }
      
      // Read and parse artifact JSON
      const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));
      
      // Extract ABI
      const abi = artifact.abi;
      
      // Save ABI to file
      const outputPath = path.join(outputDir, contractName + ".json");
      fs.writeFileSync(outputPath, JSON.stringify({ abi }, null, 2));
      
      console.log(`Generated ABI for ${contractName} at ${outputPath}`);
    } catch (error) {
      console.error(`Error generating ABI for ${contractName}:`, error.message);
    }
  });
  
  console.log("ABI generation complete!");
}

// Execute main function
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  }); 