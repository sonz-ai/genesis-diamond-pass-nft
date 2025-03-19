// SetupWhitelist.js
// This script helps set up the Supabase database and Chainlink Functions for whitelist verification

const fs = require('fs');
const path = require('path');
const { createClient } = require('@supabase/supabase-js');
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
  console.log('=== Telemafia Genesis Pass - Whitelist Setup ===');
  console.log('This script will help you set up the whitelist verification system using Supabase and Chainlink Functions.');
  console.log('');

  // Step 1: Supabase setup
  console.log('=== Step 1: Supabase Setup ===');
  console.log('1. Create a Supabase account at https://supabase.com if you don\'t have one');
  console.log('2. Create a new project in Supabase');
  console.log('3. Get your Supabase URL and API key from the project settings');
  console.log('');

  const supabaseUrl = await prompt('Enter your Supabase URL: ');
  const supabaseKey = await prompt('Enter your Supabase API key: ');

  // Create Supabase client
  const supabase = createClient(supabaseUrl, supabaseKey);

  // Create whitelist table
  console.log('\nCreating whitelist table in Supabase...');
  try {
    const { error } = await supabase
      .from('whitelist')
      .select('*')
      .limit(1);

    if (error && error.code === '42P01') {
      // Table doesn't exist, create it
      const { error: createError } = await supabase.rpc('create_table', {
        table_name: 'whitelist',
        columns: 'address text primary key, created_at timestamp with time zone default now()'
      });

      if (createError) {
        console.log('Error creating table:', createError.message);
        console.log('Please create the table manually in the Supabase dashboard with the following SQL:');
        console.log(`
CREATE TABLE whitelist (
  address TEXT PRIMARY KEY,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
        `);
      } else {
        console.log('Whitelist table created successfully!');
      }
    } else {
      console.log('Whitelist table already exists.');
    }
  } catch (error) {
    console.log('Error checking/creating table:', error.message);
    console.log('Please create the table manually in the Supabase dashboard with the following SQL:');
    console.log(`
CREATE TABLE whitelist (
  address TEXT PRIMARY KEY,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
    `);
  }

  // Step 2: Add addresses to whitelist
  console.log('\n=== Step 2: Add Addresses to Whitelist ===');
  console.log('You can add addresses to the whitelist in two ways:');
  console.log('1. Enter addresses manually in this script');
  console.log('2. Import addresses from a file (one address per line)');
  console.log('');

  const addMethod = await prompt('Choose method (1 or 2): ');
  
  let addresses = [];
  
  if (addMethod === '1') {
    console.log('\nEnter addresses one by one. Type "done" when finished.');
    let address;
    let i = 1;
    
    while (true) {
      address = await prompt(`Address ${i}: `);
      if (address.toLowerCase() === 'done') break;
      
      // Validate Ethereum address format
      if (/^0x[a-fA-F0-9]{40}$/.test(address)) {
        addresses.push(address.toLowerCase());
        i++;
      } else {
        console.log('Invalid Ethereum address format. Please try again.');
      }
    }
  } else if (addMethod === '2') {
    const filePath = await prompt('Enter the path to your addresses file: ');
    
    try {
      const fileContent = fs.readFileSync(filePath, 'utf8');
      addresses = fileContent
        .split('\n')
        .map(line => line.trim())
        .filter(line => /^0x[a-fA-F0-9]{40}$/.test(line))
        .map(address => address.toLowerCase());
      
      console.log(`Loaded ${addresses.length} valid addresses from file.`);
    } catch (error) {
      console.log('Error reading file:', error.message);
      rl.close();
      return;
    }
  } else {
    console.log('Invalid option. Exiting.');
    rl.close();
    return;
  }

  // Add addresses to whitelist
  if (addresses.length > 0) {
    console.log(`\nAdding ${addresses.length} addresses to whitelist...`);
    
    // Process in batches to avoid API limits
    const batchSize = 100;
    for (let i = 0; i < addresses.length; i += batchSize) {
      const batch = addresses.slice(i, i + batchSize).map(address => ({ address }));
      
      const { error } = await supabase
        .from('whitelist')
        .upsert(batch, { onConflict: 'address' });
      
      if (error) {
        console.log(`Error adding batch ${i / batchSize + 1}:`, error.message);
      } else {
        console.log(`Added batch ${i / batchSize + 1} (${batch.length} addresses)`);
      }
    }
    
    console.log('Addresses added to whitelist successfully!');
  } else {
    console.log('No valid addresses to add.');
  }

  // Step 3: Chainlink Functions setup
  console.log('\n=== Step 3: Chainlink Functions Setup ===');
  console.log('1. Create a Chainlink Functions subscription at https://functions.chain.link');
  console.log('2. Fund your subscription with LINK tokens');
  console.log('3. Get your subscription ID and DON ID');
  console.log('4. Set up encrypted secrets for your Supabase API key');
  console.log('');
  console.log('For detailed instructions, visit: https://docs.chain.link/chainlink-functions');
  console.log('');
  
  console.log('JavaScript source code for Chainlink Functions:');
  console.log(`
const address = args[0];
const apiUrl = args[1];
const apiKey = secrets.apiKey;

const response = await Functions.makeHttpRequest({
  url: \`\${apiUrl}/rest/v1/whitelist?address=eq.\${address}\`,
  headers: {
    'apikey': apiKey,
    'Content-Type': 'application/json'
  }
});

if (response.error) {
  throw Error('Request failed');
}

const data = response.data;
return Functions.encodeUint256(data.length > 0 ? 1 : 0);
  `);
  
  console.log('\nSecrets for Chainlink Functions:');
  console.log(`
{
  "apiKey": "${supabaseKey}"
}
  `);
  
  console.log('\nUpdate your deployment script with the following parameters:');
  console.log(`
// Chainlink Functions parameters
address router = address(0x..); // Replace with actual Chainlink Functions router address for your network
bytes32 donId = bytes32(0x..); // Replace with actual DON ID
uint64 subscriptionId = ..; // Replace with your subscription ID
uint32 callbackGasLimit = 300000; // Adjust as needed
string memory supabaseUrl = "${supabaseUrl}";
string memory supabaseKey = ""; // This will be set up separately in the Chainlink Functions UI
  `);

  console.log('\nSetup complete! You can now deploy your contract with Chainlink Functions whitelist verification.');
  rl.close();
}

// Run the script
main().catch(error => {
  console.error('Error:', error);
  process.exit(1);
});
