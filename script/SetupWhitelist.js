const { ethers } = require('ethers');
const axios = require('axios');
const fs = require('fs');
const readline = require('readline');

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

async function main() {
  console.log('=== Sonzai Genesis Pass - Whitelist Setup ===');
  console.log('This script will help you set up Chainlink Functions for whitelist verification.');
  
  // Step 1: Collect Chainlink Functions information
  console.log('\n=== Step 1: Chainlink Functions Configuration ===');
  
  const subscriptionId = await question('Enter your Chainlink Functions Subscription ID: ');
  console.log(`Using Subscription ID: ${subscriptionId}`);
  
  console.log('\nSelect the network you\'re deploying to:');
  console.log('1. Ethereum Mainnet');
  console.log('2. Sepolia Testnet');
  const networkChoice = await question('Enter your choice (1 or 2): ');
  
  let routerAddress, donId;
  if (networkChoice === '1') {
    routerAddress = '0x65Dcc24F8ff9e51F10DCc7Ed1e4e2A61e6E14bd6';
    donId = '0x66756e2d657468657265756d2d6d61696e6e65742d31000000000000000000';
    console.log('Using Ethereum Mainnet configuration');
  } else {
    routerAddress = '0xb83E47C2bC239B3bf370bc41e1459A34b41238D0';
    donId = '0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000';
    console.log('Using Sepolia Testnet configuration');
  }
  
  // Step 2: API Key Configuration
  console.log('\n=== Step 2: API Key Configuration ===');
  console.log('You need an API key to authenticate with backend.sonz.ai');
  
  const apiKey = await question('Enter your Sonzai API Key: ');
  
  // Test the API with a sample address
  console.log('\nTesting API connection...');
  try {
    const testAddress = '0x0000000000000000000000000000000000000000';
    const response = await axios.get(`https://backend.sonz.ai/api/v1/whitelist/${testAddress}`, {
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      }
    });
    console.log('API connection successful!');
    console.log(`API response: ${JSON.stringify(response.data)}`);
  } catch (error) {
    console.log('API connection failed. Please check your API key and try again.');
    console.log(`Error: ${error.message}`);
    if (error.response) {
      console.log(`Status: ${error.response.status}`);
      console.log(`Data: ${JSON.stringify(error.response.data)}`);
    }
    // Continue anyway, as the API might not be available during setup
    console.log('Continuing with setup despite API connection failure...');
  }
  
  // Step 3: Update .env file
  console.log('\n=== Step 3: Updating Environment Variables ===');
  
  const royaltyReceiver = await question('Enter the initial royalty receiver address (your address): ');
  const callbackGasLimit = await question('Enter the callback gas limit (default: 300000): ') || '300000';
  
  // Read existing .env file or create a new one
  let envContent = '';
  try {
    envContent = fs.readFileSync('.env', 'utf8');
  } catch (error) {
    console.log('No existing .env file found. Creating a new one.');
    envContent = fs.readFileSync('.env.example', 'utf8');
  }
  
  // Update environment variables
  envContent = envContent
    .replace(/CHAINLINK_SUBSCRIPTION_ID=.*/, `CHAINLINK_SUBSCRIPTION_ID=${subscriptionId}`)
    .replace(/CHAINLINK_DON_ID=.*/, `CHAINLINK_DON_ID=${donId}`)
    .replace(/CHAINLINK_ROUTER_ADDRESS=.*/, `CHAINLINK_ROUTER_ADDRESS=${routerAddress}`)
    .replace(/SONZAI_API_KEY=.*/, `SONZAI_API_KEY=${apiKey}`)
    .replace(/ROYALTY_RECEIVER_ADDRESS=.*/, `ROYALTY_RECEIVER_ADDRESS=${royaltyReceiver}`)
    .replace(/CALLBACK_GAS_LIMIT=.*/, `CALLBACK_GAS_LIMIT=${callbackGasLimit}`);
  
  fs.writeFileSync('.env', envContent);
  console.log('.env file updated successfully!');
  
  // Step 4: Create Chainlink Functions source code
  console.log('\n=== Step 4: Creating Chainlink Functions Source Code ===');
  
  const functionsSourceCode = `
// Chainlink Functions source code for whitelist verification
// This code will be executed off-chain by Chainlink Functions

// Args:
// - args[0]: User address to check against the whitelist

// Secrets:
// - apiKey: API key for backend.sonz.ai authentication

const address = args[0];
const apiKey = secrets.apiKey;

// Make HTTP request to backend.sonz.ai
const response = await Functions.makeHttpRequest({
  url: \`https://backend.sonz.ai/api/v1/whitelist/\${address}\`,
  headers: {
    'Authorization': \`Bearer \${apiKey}\`,
    'Content-Type': 'application/json'
  }
});

if (response.error) {
  throw Error('Request failed: ' + response.error);
}

// Check if the address is whitelisted
// The API should return a 200 status code if the address is whitelisted
const isWhitelisted = response.status === 200;

// Return 1 if whitelisted, 0 if not
return Functions.encodeUint256(isWhitelisted ? 1 : 0);
`;

  fs.writeFileSync('chainlink-functions-source.js', functionsSourceCode);
  console.log('Chainlink Functions source code created at: chainlink-functions-source.js');
  console.log('You will need to upload this code to Chainlink Functions UI or use it with the Chainlink Functions SDK.');
  
  // Step 5: Instructions for deployment
  console.log('\n=== Step 5: Deployment Instructions ===');
  console.log('Your environment is now configured for deployment.');
  console.log('To deploy the contract, run:');
  console.log('forge script script/DeploySonzaiGenesisPass.s.sol:DeploySonzaiGenesisPass --rpc-url $RPC_URL --broadcast --verify');
  console.log('\nAfter deployment:');
  console.log('1. Add your contract as a consumer to your Chainlink Functions subscription');
  console.log('   - Go to functions.chain.link');
  console.log('   - Connect your wallet');
  console.log('   - Navigate to "Subscriptions" and find your subscription');
  console.log('   - Click "Add Consumer" and enter your contract address');
  console.log('2. Test the whitelist verification functionality');
  console.log('3. Transfer ownership to your Gnosis Safe multisig');
  
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
