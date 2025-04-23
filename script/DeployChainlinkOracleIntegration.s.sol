// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "src/programmable-royalties/ChainlinkOracleIntegration.sol";
import "src/programmable-royalties/CentralizedRoyaltyDistributor.sol";

/**
 * @title DeployChainlinkOracleIntegration
 * @notice Deployment script for ChainlinkOracleIntegration contract
 * @dev Two deployment scenarios:
 * 1. Deploy without Chainlink configuration (configure later)
 * 2. Deploy with Chainlink configuration (if available)
 */
contract DeployChainlinkOracleIntegration is Script {
    function run() external {
        // Load private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Get distributor address from environment variable
        address distributorAddress = vm.envAddress("DISTRIBUTOR_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Check if router address is provided
        bool hasChainlinkConfig = vm.envOr("HAS_CHAINLINK_CONFIG", false);
        
        if (hasChainlinkConfig) {
            // Deploy with initial Chainlink configuration
            address routerAddress = vm.envAddress("CHAINLINK_ROUTER_ADDRESS");
            
            ChainlinkOracleIntegration oracle = new ChainlinkOracleIntegration(
                distributorAddress,
                routerAddress
            );
            
            // Configure DON ID and subscription ID if provided
            bytes32 donId = vm.envBytes32("CHAINLINK_DON_ID");
            uint64 subscriptionId = uint64(vm.envUint("CHAINLINK_SUBSCRIPTION_ID"));
            
            // Configure remaining Chainlink settings
            oracle.configureChainlink(
                routerAddress,
                donId,
                subscriptionId
            );
            
            // Set the source code if provided
            string memory source = vm.envOr("CHAINLINK_SOURCE_CODE", string(""));
            if (bytes(source).length > 0) {
                oracle.setSource(source);
            }
            
            console.log("ChainlinkOracleIntegration deployed with configuration at:", address(oracle));
        } else {
            // Deploy without Chainlink configuration (configure later)
            ChainlinkOracleIntegration oracle = new ChainlinkOracleIntegration(
                distributorAddress,
                address(0) // No router address yet
            );
            
            console.log("ChainlinkOracleIntegration deployed at:", address(oracle));
            console.log("Configure Chainlink later using the admin functions.");
        }
        
        vm.stopBroadcast();
    }
}

/**
 * @title ConfigureChainlinkOracle
 * @notice Script to configure an existing ChainlinkOracleIntegration contract
 */
contract ConfigureChainlinkOracle is Script {
    function run() external {
        // Load private key from environment variable
        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Get oracle address from environment variable
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");
        ChainlinkOracleIntegration oracle = ChainlinkOracleIntegration(oracleAddress);
        
        vm.startBroadcast(adminPrivateKey);
        
        // Configure Chainlink settings
        address routerAddress = vm.envAddress("CHAINLINK_ROUTER_ADDRESS");
        bytes32 donId = vm.envBytes32("CHAINLINK_DON_ID");
        uint64 subscriptionId = uint64(vm.envUint("CHAINLINK_SUBSCRIPTION_ID"));
        
        oracle.configureChainlink(
            routerAddress,
            donId,
            subscriptionId
        );
        
        // Set the source code
        string memory source = vm.envString("CHAINLINK_SOURCE_CODE");
        oracle.setSource(source);
        
        console.log("ChainlinkOracleIntegration configured successfully");
        
        vm.stopBroadcast();
    }
} 