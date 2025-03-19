// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/TelemafiaGenesisPass.sol";

contract DeployTelemafiaGenesisPass is Script {
    function run() external {
        // Get private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the contract with constructor parameters
        // 1. Royalty receiver address (replace with actual address)
        address royaltyReceiver = address(0x123); // Replace with actual address
        
        // 2. Base URI for token metadata
        string memory baseURI = "https://api.telemafia.com/metadata/";
        
        // 3. Chainlink Functions router address (replace with actual address for the network)
        address router = address(0x456); // Replace with actual Chainlink Functions router address
        
        // 4. Chainlink Functions DON ID (replace with actual DON ID)
        bytes32 donId = bytes32(0);
        
        // 5. Chainlink Functions subscription ID (replace with actual subscription ID)
        uint64 subscriptionId = 1; // Replace with actual subscription ID
        
        // 6. Callback gas limit for Chainlink Functions
        uint32 callbackGasLimit = 300000; // Adjust as needed
        
        // 7. Supabase API URL
        string memory supabaseUrl = "https://your-project.supabase.co"; // Replace with actual Supabase URL
        
        // 8. Supabase API key (encrypted)
        string memory supabaseKey = ""; // This will be set up separately in the Chainlink Functions UI
        
        // Deploy the contract
        TelemafiaGenesisPass genesisPass = new TelemafiaGenesisPass(
            royaltyReceiver,
            baseURI,
            router,
            donId,
            subscriptionId,
            callbackGasLimit,
            supabaseUrl,
            supabaseKey
        );
        
        // End broadcasting transactions
        vm.stopBroadcast();
        
        // Log the deployed contract address
        console.log("TelemafiaGenesisPass deployed at:", address(genesisPass));
    }
}
