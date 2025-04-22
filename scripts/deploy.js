const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  // Get the signers
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // Deploy CentralizedRoyaltyDistributor first
  console.log("Deploying CentralizedRoyaltyDistributor...");
  const CentralizedRoyaltyDistributor = await ethers.getContractFactory("CentralizedRoyaltyDistributor");
  const royaltyDistributor = await CentralizedRoyaltyDistributor.deploy();
  await royaltyDistributor.deployed();
  console.log("CentralizedRoyaltyDistributor deployed to:", royaltyDistributor.address);

  // Set up parameters for DiamondGenesisPass
  const royaltyFeeNumerator = 750; // 7.5% royalty fee in basis points
  const creatorAddress = deployer.address; // Using deployer as the initial creator

  // Deploy DiamondGenesisPass
  console.log("Deploying DiamondGenesisPass...");
  const DiamondGenesisPass = await ethers.getContractFactory("DiamondGenesisPass");
  const diamondGenesisPass = await DiamondGenesisPass.deploy(
    royaltyDistributor.address,
    royaltyFeeNumerator,
    creatorAddress
  );
  await diamondGenesisPass.deployed();
  console.log("DiamondGenesisPass deployed to:", diamondGenesisPass.address);

  // Generate and save the contract ABIs
  saveContractData(royaltyDistributor, "CentralizedRoyaltyDistributor");
  saveContractData(diamondGenesisPass, "DiamondGenesisPass");

  console.log("Deployment complete! ABIs saved to the ./abis directory.");
}

function saveContractData(contract, name) {
  const contractData = {
    address: contract.address,
    abi: JSON.parse(contract.interface.format("json"))
  };

  // Ensure the abis directory exists
  const abiDir = path.join(__dirname, "../abis");
  if (!fs.existsSync(abiDir)) {
    fs.mkdirSync(abiDir, { recursive: true });
  }

  // Write the contract data to a JSON file
  fs.writeFileSync(
    path.join(abiDir, `${name}.json`),
    JSON.stringify(contractData, null, 2)
  );
  console.log(`${name} data saved to abis/${name}.json`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 