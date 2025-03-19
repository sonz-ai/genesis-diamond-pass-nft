// SetupWhitelist.js
// This script provides instructions for setting up Chainlink Functions for whitelist verification

const readline = require('readline');

// Create readline interface for user input
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

// Function to prompt user for input
const prompt = (question) => {
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      resolve(answer);
    });
  });
};

// Main function
async function main() {
  console.log('=== Sonzai Diamond Genesis Pass - Whitelist Setup ===');
  console.log('This script provides instructions for setting up Chainlink Functions for whitelist verification.');
  console.log('');

  // Step 1: API Key setup
  console.log('=== Step 1: API Key Setup ===');
  console.log('You need an API key to authenticate with the backend.sonz.ai service.');
  console.log('This key will be used in the Chainlink Functions to verify whitelist status.');
  console.log('');

  const apiKey = await prompt('Enter your API key (or press Enter to skip): ');

  // Step 2: Chainlink Functions setup
  console.log('\n=== Step 2: Chainlink Functions Setup ===');
  console.log('1. Create a Chainlink Functions subscription at https://functions.chain.link');
  console.log('2. Fund your subscription with LINK tokens');
  console.log('3. Get your subscription ID and DON ID');
  console.log('4. Set up encrypted secrets for your API key');
  console.log('');
  console.log('For detailed instructions, visit: https://docs.chain.link/chainlink-functions');
  console.log('');
  
  console.log('JavaScript source code for Chainlink Functions:');
  console.log(`
const address = args[0];
const apiKey = secrets.apiKey;

const response = await Functions.makeHttpRequest({
  url: \`https://backend.sonz.ai/whitelist/\${address}\`,
  headers: {
    'Authorization': \`Bearer \${apiKey}\`,
    'Content-Type': 'application/json'
  }
});

if (response.error) {
  throw Error('Request failed');
}

const data = response.data;
return Functions.encodeUint256(data.isWhitelisted ? 1 : 0);
  `);
  
  if (apiKey) {
    console.log('\nSecrets for Chainlink Functions:');
    console.log(`
{
  "apiKey": "${apiKey}"
}
    `);
  } else {
    console.log('\nYou will need to set up your API key in the Chainlink Functions UI.');
  }
  
  console.log('\nUpdate your deployment script with the following parameters:');
  console.log(`
// Chainlink Functions parameters
address router = address(0x..); // Replace with actual Chainlink Functions router address for your network
bytes32 donId = bytes32(0x..); // Replace with actual DON ID
uint64 subscriptionId = ..; // Replace with your subscription ID
uint32 callbackGasLimit = 300000; // Adjust as needed
string memory apiKey = ""; // This will be set up separately in the Chainlink Functions UI
  `);

  console.log('\nSetup instructions complete! You can now deploy your contract with Chainlink Functions whitelist verification.');
  rl.close();
}

// Run the script
main().catch(error => {
  console.error('Error:', error);
  process.exit(1);
});
