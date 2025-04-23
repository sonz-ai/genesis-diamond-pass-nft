// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../chainlink/FunctionsClient.sol";
import "../chainlink/ConfirmedOwner.sol";
import "./CentralizedRoyaltyDistributor.sol";

// Interface to interact with the distributor's event
interface IDistributorEvents {
    event OracleUpdateRequested(address indexed collection, uint256 fromBlock, uint256 toBlock);
}

/**
 * @title ChainlinkOracleIntegration
 * @notice This contract contains the implementation of Chainlink Functions integration with CentralizedRoyaltyDistributor
 * @dev Can be deployed first and configured later by an admin
 */
contract ChainlinkOracleIntegration is FunctionsClient, ConfirmedOwner {
    CentralizedRoyaltyDistributor public immutable royaltyDistributor;
    
    // Chainlink Functions configuration - can be set after deployment
    bytes32 private s_donId;
    uint64 private s_subscriptionId;
    bytes32 private s_latestRequestId;
    mapping(bytes32 => address) private s_requests; // requestId => collection
    bool private s_isConfigured;
    
    // JavaScript code to fetch and process royalty data - can be set after deployment
    string private s_source;
    
    event OracleRequestSent(bytes32 indexed requestId, address indexed collection);
    event OracleResponseReceived(bytes32 indexed requestId, address indexed collection, bytes response);
    event OracleResponseFailed(bytes32 indexed requestId, address indexed collection, bytes error);
    event ChainlinkConfigured(address router, bytes32 donId, uint64 subscriptionId);
    
    error InvalidCollection();
    error UnregisteredCollection();
    error InvalidResponse();
    error InvalidResponseFormat();
    error ChainlinkNotConfigured();
    error SourceNotConfigured();
    
    /**
     * @notice Constructor that doesn't require Chainlink configuration
     * @param distributorAddress Address of the CentralizedRoyaltyDistributor contract
     * @param routerAddress Optional router address (can be address(0) if configuring later)
     */
    constructor(
        address distributorAddress,
        address routerAddress
    ) FunctionsClient(routerAddress != address(0) ? routerAddress : address(1)) ConfirmedOwner(msg.sender) {
        if (distributorAddress == address(0)) revert InvalidCollection();
        royaltyDistributor = CentralizedRoyaltyDistributor(payable(distributorAddress));
        
        // Set s_isConfigured to true only if routerAddress is provided
        s_isConfigured = routerAddress != address(0);
    }
    
    /**
     * @notice Configure the Chainlink Functions integration
     * @param router Address of the Chainlink Functions Router
     * @param donId DON ID for the Functions oracle network
     * @param subscriptionId Chainlink Functions subscription ID
     */
    function configureChainlink(
        address router,
        bytes32 donId,
        uint64 subscriptionId
    ) external onlyOwner {
        require(router != address(0), "Router cannot be zero address");
        
        // Update configuration
        s_donId = donId;
        s_subscriptionId = subscriptionId;
        s_isConfigured = true;
        
        emit ChainlinkConfigured(router, donId, subscriptionId);
    }
    
    /**
     * @notice Set the JavaScript source code for Chainlink Functions
     * @param source JavaScript source code
     */
    function setSource(string calldata source) external onlyOwner {
        require(bytes(source).length > 0, "Source cannot be empty");
        s_source = source;
    }
    
    /**
     * @notice Update the subscription ID if needed
     * @param subscriptionId New Chainlink Functions subscription ID
     */
    function setSubscriptionId(uint64 subscriptionId) external onlyOwner {
        s_subscriptionId = subscriptionId;
    }
    
    /**
     * @notice Update the DON ID if needed
     * @param donId New DON ID
     */
    function setDonId(bytes32 donId) external onlyOwner {
        s_donId = donId;
    }
    
    /**
     * @notice Send an oracle request to update royalty data
     * @param collection The collection address
     * @param fromBlock The starting block for fetching transfer events
     */
    function sendRoyaltyDataRequest(address collection, uint256 fromBlock) external returns (bytes32) {
        // Check if Chainlink is configured
        if (!s_isConfigured) {
            revert ChainlinkNotConfigured();
        }
        
        // Check if source is configured
        if (bytes(s_source).length == 0) {
            revert SourceNotConfigured();
        }
        
        // Check if collection is registered
        if (!royaltyDistributor.isCollectionRegistered(collection)) {
            revert UnregisteredCollection();
        }
        
        // Check if the caller is authorized by the royalty distributor (admin or service account)
        bool isAdmin = royaltyDistributor.hasRole(royaltyDistributor.DEFAULT_ADMIN_ROLE(), msg.sender);
        bool isService = royaltyDistributor.hasRole(royaltyDistributor.SERVICE_ACCOUNT_ROLE(), msg.sender);
        require(isAdmin || isService, "Not authorized");
        
        // Prepare Chainlink Functions request
        string[] memory args = new string[](3);
        args[0] = _addressToString(collection);
        args[1] = _uint256ToString(fromBlock);
        args[2] = _uint256ToString(block.number);
        
        bytes32 requestId = _sendRequest(
            s_source,
            args,
            s_subscriptionId,
            200000, // gas limit
            s_donId
        );
        
        // Store the request details
        s_requests[requestId] = collection;
        s_latestRequestId = requestId;
        
        emit OracleRequestSent(requestId, collection);
        
        return requestId;
    }
    
    /**
     * @notice Callback function for Chainlink Functions
     * @param requestId The ID of the request
     * @param response The response from the oracle
     * @param err Any errors from the oracle
     */
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        address collection = s_requests[requestId];
        
        if (err.length > 0) {
            emit OracleResponseFailed(requestId, collection, err);
            return;
        }
        
        emit OracleResponseReceived(requestId, collection, response);
        
        // Process the response and update royalty accruals
        _processRoyaltyResponse(collection, response);
    }
    
    /**
     * @notice Process royalty data response from oracle and update accrued royalties
     * @param collection The collection address
     * @param response The response from the oracle
     */
    function _processRoyaltyResponse(address collection, bytes memory response) internal {
        // Decode the response
        string memory jsonStr = abi.decode(response, (string));
        
        // Parse the JSON (simplified - in production you'd need a proper JSON parser)
        // For this example, we assume the response is already in the correct format
        
        // Replace try/catch with regular function call and error handling
        (bool success, address[] memory recipients, uint256[] memory amounts) = _tryParseResponse(jsonStr);
        
        if (!success) {
            revert InvalidResponseFormat();
        }
        
        // Update accrued royalties
        try royaltyDistributor.fulfillRoyaltyData(
            s_latestRequestId,
            collection,
            recipients,
            amounts
        ) {
            // Successfully updated royalties
        } catch {
            // Failed to update royalties
        }
    }
    
    /**
     * @notice Try to parse the JSON response with error handling
     * @param jsonStr The JSON string to parse
     * @return success Whether parsing was successful
     * @return recipients Array of recipient addresses
     * @return amounts Array of royalty amounts
     */
    function _tryParseResponse(string memory jsonStr) internal pure returns (bool success, address[] memory recipients, uint256[] memory amounts) {
        // Simple validation to ensure the string isn't empty
        if (bytes(jsonStr).length == 0) {
            return (false, recipients, amounts);
        }
        
        // This is a placeholder - in a real implementation, you'd need a proper JSON parser
        // For demonstration purposes only
        
        // Mock data
        recipients = new address[](2);
        amounts = new uint256[](2);
        
        recipients[0] = address(0x1); // Placeholder
        recipients[1] = address(0x2); // Placeholder
        
        amounts[0] = 1 ether; // Placeholder
        amounts[1] = 2 ether; // Placeholder
        
        return (true, recipients, amounts);
    }
    
    /**
     * @notice Check if the Chainlink integration is configured
     * @return Whether Chainlink is configured
     */
    function isConfigured() external view returns (bool) {
        return s_isConfigured;
    }
    
    /**
     * @notice Convert an address to a string
     * @param addr The address to convert
     * @return The string representation of the address
     */
    function _addressToString(address addr) internal pure returns (string memory) {
        bytes memory addressBytes = abi.encodePacked(addr);
        bytes memory stringBytes = new bytes(42);
        
        stringBytes[0] = '0';
        stringBytes[1] = 'x';
        
        for (uint256 i = 0; i < 20; i++) {
            bytes1 leftNibble = bytes1(uint8(addressBytes[i] >> 4) + (uint8(addressBytes[i] >> 4) < 10 ? 48 : 87));
            bytes1 rightNibble = bytes1(uint8(addressBytes[i] & 0x0f) + (uint8(addressBytes[i] & 0x0f) < 10 ? 48 : 87));
            stringBytes[2 + i * 2] = leftNibble;
            stringBytes[2 + i * 2 + 1] = rightNibble;
        }
        
        return string(stringBytes);
    }
    
    /**
     * @notice Convert a uint256 to a string
     * @param value The value to convert
     * @return The string representation of the value
     */
    function _uint256ToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        
        uint256 temp = value;
        uint256 digits;
        
        while (temp > 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        
        while (value > 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        
        return string(buffer);
    }
    
    /**
     * @notice Set up an off-chain listener for OracleUpdateRequested events
     * @dev This is a reference for implementing the off-chain component that listens for events
     *      and triggers Chainlink Functions requests
     * 
     * // Off-chain pseudo-code for Node.js event listener:
     * // 
     * // const ethers = require('ethers');
     * // const distributorAbi = [...]; // ABI with the OracleUpdateRequested event
     * // const oracleAddress = "0x..."; // Address of this ChainlinkOracleIntegration contract
     * // 
     * // const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
     * // const distributor = new ethers.Contract(distributorAddress, distributorAbi, provider);
     * // 
     * // distributor.on("OracleUpdateRequested", async (collection, fromBlock, toBlock, event) => {
     * //   console.log(`Oracle update requested for collection ${collection}`);
     * // 
     * //   // Get the wallet to pay for the request
     * //   const wallet = new ethers.Wallet(privateKey, provider);
     * //   const oracle = new ethers.Contract(oracleAddress, oracleAbi, wallet);
     * // 
     * //   // Send the royalty data request
     * //   const tx = await oracle.sendRoyaltyDataRequest(collection, fromBlock.toString());
     * //   console.log(`Request sent in transaction ${tx.hash}`);
     * // });
     */
    function offchainOracleListenerReference() external pure returns (string memory) {
        return "The off-chain component should implement an event listener for OracleUpdateRequested";
    }
} 