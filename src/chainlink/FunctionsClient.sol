// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Mock FunctionsClient
 * @notice A simple mock implementation of Chainlink Functions client for testing purposes
 */
abstract contract FunctionsClient {
    address private s_router;
    
    event RequestSent(bytes32 indexed requestId, bytes data);
    
    error EmptySource();
    error EmptyArgs();
    error EmptySecrets();
    error EmptySecretsLocation();
    
    constructor(address router) {
        s_router = router;
    }
    
    function getRouter() internal view returns (address) {
        return s_router;
    }
    
    function _sendRequest(
        string memory source,
        string[] memory args,
        uint64 subscriptionId,
        uint32 gasLimit,
        bytes32 donId
    ) internal returns (bytes32) {
        if (bytes(source).length == 0) revert EmptySource();
        
        bytes memory encodedData = abi.encode(source, args, block.timestamp, msg.sender);
        bytes32 requestId = keccak256(encodedData);
        
        emit RequestSent(requestId, abi.encode(source, args));
        
        return requestId;
    }
    
    /**
     * @notice Override this function to process responses from the oracle
     * @param requestId The ID of the request
     * @param response The response data from the oracle
     * @param err Any error from the oracle
     */
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal virtual;
} 