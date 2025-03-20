// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/SonzaiGenesisPass.sol";

contract DeploySonzaiGenesisPass is Script {
    function run() external {
        // Get private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Load environment variables for constructor parameters
        // 1. Royalty receiver address (use default if not set)
        address royaltyReceiver;
        try vm.envAddress("ROYALTY_RECEIVER_ADDRESS") {
            royaltyReceiver = vm.envAddress("ROYALTY_RECEIVER_ADDRESS");
        } catch {
            royaltyReceiver = address(0x123); // Default value
        }
        
        // 2. Base URI for token metadata (use default if not set)
        string memory baseURI;
        try vm.envString("BASE_URI") {
            baseURI = vm.envString("BASE_URI");
        } catch {
            baseURI = "https://api.sonzai.io/metadata/"; // Default value
        }
        
        // 3. Chainlink Functions router address
        address router = vm.envAddress("CHAINLINK_ROUTER_ADDRESS");
        
        // 4. Chainlink Functions DON ID
        bytes32 donId = vm.envBytes32("CHAINLINK_DON_ID");
        
        // 5. Chainlink Functions subscription ID
        uint64 subscriptionId = uint64(vm.envUint("CHAINLINK_SUBSCRIPTION_ID"));
        
        // 6. Callback gas limit for Chainlink Functions (use default if not set)
        uint32 callbackGasLimit;
        try vm.envUint("CALLBACK_GAS_LIMIT") {
            callbackGasLimit = uint32(vm.envUint("CALLBACK_GAS_LIMIT"));
        } catch {
            callbackGasLimit = 300000; // Default value
        }
        
        // 7. API key for backend authentication (will be set up in Chainlink Functions UI)
        string memory apiKey = ""; // Not stored in .env for security reasons
        
        // 8. Encrypted secrets reference for Chainlink Functions
        string memory encryptedSecretsReference;
        try vm.envString("ENCRYPTED_SECRETS_REFERENCE") {
            encryptedSecretsReference = vm.envString("ENCRYPTED_SECRETS_REFERENCE");
        } catch {
            encryptedSecretsReference = ""; // Default empty value
            console.log("Warning: No encrypted secrets reference provided. Make sure to set it up in Chainlink Functions UI.");
        }
        
        // Deploy the contract
        SonzaiGenesisPass genesisPass = new SonzaiGenesisPass(
            royaltyReceiver,
            baseURI,
            router,
            donId,
            subscriptionId,
            callbackGasLimit,
            apiKey,
            encryptedSecretsReference
        );
        
        // End broadcasting transactions
        vm.stopBroadcast();
        
        // Log the deployed contract address
        console.log("SonzaiGenesisPass deployed at:", address(genesisPass));
    }
}
