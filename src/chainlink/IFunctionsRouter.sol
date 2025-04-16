// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IFunctionsRouter
 * @notice Interface for Chainlink Functions Router contract
 */
interface IFunctionsRouter {
  /**
   * @notice Send a request to the Chainlink Functions oracle
   * @param subscriptionId Subscription ID that's responsible for paying for the request
   * @param data Encoded Chainlink Functions request data
   * @param dataVersion Version of the data format
   * @param callbackGasLimit Gas limit for the fulfillment callback
   * @param donId DON ID for the request
   * @return requestId The ID of the request
   */
  function sendRequest(
    uint64 subscriptionId,
    bytes calldata data,
    uint16 dataVersion,
    uint32 callbackGasLimit,
    bytes32 donId
  ) external returns (bytes32);
} 