const { ethers } = require('ethers');
const fs = require('fs');
const readline = require('readline');
const { exec } = require('child_process');
const path = require('path');

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

async function main() {
  console.log('=== Sonzai Genesis Pass - Chainlink Functions Secrets Setup ===');
  console.log('This script will help you set up encrypted secrets for Chainlink Functions.');
  
  // Step 1: Check if functions-hardhat-starter-kit is available
  console.log('\n=== Step 1: Checking Chainlink Functions dependencies ===');
  
  const functionsKitPath = path.join(__dirname, '..', 'lib', 'functions-hardhat-starter-kit');
  if (!fs.existsSync(functionsKitPath)) {
    console.log('Chainlink Functions Hardhat Starter Kit not found.');
    console.log('Please run: forge install smartcontractkit/functions-hardhat-starter-kit');
    process.exit(1);
  }
  
  console.log('Chainlink Functions Hardhat Starter Kit found at:', functionsKitPath);
  
  // Step 2: Get API key
  console.log('\n=== Step 2: API Key Configuration ===');
  
  let apiKey;
  try {
    const envContent = fs.readFileSync('.env', 'utf8');
    const match = envContent.match(/SONZAI_API_KEY=(.+)/);
    if (match && match[1]) {
      apiKey = match[1];
      console.log('Found API key in .env file.');
      const useExisting = await question('Use existing API key? (y/n): ');
      if (useExisting.toLowerCase() !== 'y') {
        apiKey = await question('Enter your Sonzai API Key: ');
      }
    } else {
      apiKey = await question('Enter your Sonzai API Key: ');
    }
  } catch (error) {
    apiKey = await question('Enter your Sonzai API Key: ');
  }
  
  // Step 3: Create secrets.json file
  console.log('\n=== Step 3: Creating secrets.json file ===');
  
  const secretsJson = {
    apiKey: apiKey
  };
  
  fs.writeFileSync('secrets.json', JSON.stringify(secretsJson, null, 2));
  console.log('Created secrets.json file with your API key.');
  
  // Step 4: Encrypt secrets
  console.log('\n=== Step 4: Encrypting secrets ===');
  
  console.log('Select the network you\'re deploying to:');
  console.log('1. Ethereum Mainnet');
  console.log('2. Sepolia Testnet');
  const networkChoice = await question('Enter your choice (1 or 2): ');
  
  let network;
  if (networkChoice === '1') {
    network = 'mainnet';
  } else {
    network = 'sepolia';
  }
  
  console.log(`Using ${network} network for encryption.`);
  console.log('Please enter a password to encrypt your secrets:');
  const password = await question('Password: ');
  
  // Change to the functions-hardhat-starter-kit directory
  process.chdir(functionsKitPath);
  
  // Copy secrets.json to the functions-hardhat-starter-kit directory
  fs.copyFileSync(path.join(__dirname, '..', 'secrets.json'), 'secrets.json');
  
  // Run the encryption command
  console.log('Encrypting secrets...');
  exec(`npx hardhat functions-encrypt-secrets --network ${network} --password ${password}`, (error, stdout, stderr) => {
    if (error) {
      console.error(`Error encrypting secrets: ${error.message}`);
      return;
    }
    
    if (stderr) {
      console.error(`Stderr: ${stderr}`);
      return;
    }
    
    console.log(stdout);
    
    // Copy the encrypted secrets back to the project root
    try {
      fs.copyFileSync('encrypted-secrets.json', path.join(__dirname, '..', 'encrypted-secrets.json'));
      console.log('Encrypted secrets saved to encrypted-secrets.json');
      
      // Copy the DON public key
      fs.copyFileSync(`${network}-don-public-key.json`, path.join(__dirname, '..', `${network}-don-public-key.json`));
      console.log(`DON public key saved to ${network}-don-public-key.json`);
      
      // Clean up
      fs.unlinkSync('secrets.json');
      console.log('\nSecrets encryption completed successfully!');
      
      // Return to the project root
      process.chdir(path.join(__dirname, '..'));
      
      // Instructions
      console.log('\n=== Step 5: Next Steps ===');
      console.log('1. Upload your encrypted secrets to the Chainlink Functions UI:');
      console.log('   - Go to functions.chain.link');
      console.log('   - Connect your wallet');
      console.log('   - Navigate to "Secrets" and click "Upload Secrets"');
      console.log('   - Upload your encrypted-secrets.json file');
      console.log('2. Note the encrypted secrets reference (gist ID)');
      console.log('3. Update your contract deployment script with the encrypted secrets reference');
      
      rl.close();
    } catch (err) {
      console.error('Error copying encrypted files:', err);
      rl.close();
    }
  });
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
