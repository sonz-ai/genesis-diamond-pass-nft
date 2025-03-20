const { ethers } = require('ethers');
const fs = require('fs');
const readline = require('readline');

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

// ABI for the contract's ownership functions
const contractABI = [
  "function owner() view returns (address)",
  "function transferOwnership(address newOwner)",
  "function setDefaultRoyalty(address receiver, uint96 feeNumerator)"
];

async function main() {
  console.log('=== Sonzai Genesis Pass - Transfer Ownership ===');
  console.log('This script will help you transfer ownership of your contract to a Gnosis Safe multisig.');
  
  // Step 1: Get contract address and private key
  console.log('\n=== Step 1: Contract Information ===');
  
  const contractAddress = await question('Enter your deployed contract address: ');
  
  // Get private key from .env file or prompt
  let privateKey;
  try {
    const envContent = fs.readFileSync('.env', 'utf8');
    const match = envContent.match(/PRIVATE_KEY=(.+)/);
    if (match && match[1]) {
      privateKey = match[1];
      console.log('Found private key in .env file.');
      const useExisting = await question('Use existing private key? (y/n): ');
      if (useExisting.toLowerCase() !== 'y') {
        privateKey = await question('Enter your private key: ');
      }
    } else {
      privateKey = await question('Enter your private key: ');
    }
  } catch (error) {
    privateKey = await question('Enter your private key: ');
  }
  
  // Step 2: Get RPC URL and network
  console.log('\n=== Step 2: Network Information ===');
  
  console.log('Select the network:');
  console.log('1. Ethereum Mainnet');
  console.log('2. Sepolia Testnet');
  const networkChoice = await question('Enter your choice (1 or 2): ');
  
  let rpcUrl;
  if (networkChoice === '1') {
    rpcUrl = await question('Enter Ethereum Mainnet RPC URL: ');
  } else {
    rpcUrl = await question('Enter Sepolia Testnet RPC URL: ');
  }
  
  // Step 3: Get Gnosis Safe address
  console.log('\n=== Step 3: Gnosis Safe Information ===');
  
  const safeAddress = await question('Enter your Gnosis Safe multisig address: ');
  
  // Step 4: Connect to the contract
  console.log('\n=== Step 4: Connecting to Contract ===');
  
  try {
    // Set up provider and signer
    const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);
    const contract = new ethers.Contract(contractAddress, contractABI, wallet);
    
    // Check current owner
    const currentOwner = await contract.owner();
    console.log(`Current owner: ${currentOwner}`);
    
    if (currentOwner.toLowerCase() !== wallet.address.toLowerCase()) {
      console.log('Warning: You are not the current owner of this contract.');
      console.log('Only the current owner can transfer ownership.');
      const proceed = await question('Do you want to proceed anyway? (y/n): ');
      if (proceed.toLowerCase() !== 'y') {
        console.log('Operation cancelled.');
        process.exit(0);
      }
    }
    
    // Step 5: Transfer ownership
    console.log('\n=== Step 5: Transferring Ownership ===');
    
    console.log(`Transferring ownership to Gnosis Safe: ${safeAddress}`);
    const transferTx = await contract.transferOwnership(safeAddress);
    console.log(`Transaction hash: ${transferTx.hash}`);
    console.log('Waiting for transaction confirmation...');
    
    await transferTx.wait();
    console.log('Ownership transferred successfully!');
    
    // Step 6: Update royalty receiver (optional)
    console.log('\n=== Step 6: Update Royalty Receiver (Optional) ===');
    
    const updateRoyalty = await question('Do you want to update the royalty receiver to the Safe as well? (y/n): ');
    if (updateRoyalty.toLowerCase() === 'y') {
      const royaltyTx = await contract.setDefaultRoyalty(safeAddress, 1100); // 11%
      console.log(`Transaction hash: ${royaltyTx.hash}`);
      console.log('Waiting for transaction confirmation...');
      
      await royaltyTx.wait();
      console.log('Royalty receiver updated successfully!');
    }
    
    // Step 7: Verify new owner
    console.log('\n=== Step 7: Verification ===');
    
    const newOwner = await contract.owner();
    console.log(`New owner: ${newOwner}`);
    
    if (newOwner.toLowerCase() === safeAddress.toLowerCase()) {
      console.log('Ownership transfer verified successfully!');
      console.log('\nYour contract is now owned by the Gnosis Safe multisig.');
      console.log('All mint proceeds and royalties will now go to the Safe.');
    } else {
      console.log('Warning: Ownership transfer could not be verified.');
      console.log('Please check the contract on Etherscan to confirm the new owner.');
    }
  } catch (error) {
    console.error('Error:', error.message);
    if (error.data) {
      console.error('Error data:', error.data);
    }
  }
  
  rl.close();
}

function question(query) {
  return new Promise(resolve => {
    rl.question(query, resolve);
  });
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
