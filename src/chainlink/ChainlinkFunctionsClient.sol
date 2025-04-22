// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IFunctionsRouter.sol";
import "./IFunctionsClient.sol";
import "./FunctionsRequest.sol";

/**
 * @title Chainlink Functions Client
 * @notice A wrapper contract for Chainlink Functions to allow our contracts to interact with the service
 * @dev This is a simplified version of the official Chainlink FunctionsClient contract
 */
abstract contract ChainlinkFunctionsClient is IFunctionsClient {
  using FunctionsRequest for FunctionsRequest.Request;

  IFunctionsRouter internal immutable i_functionsRouter;

  event RequestSent(bytes32 indexed id);
  event RequestFulfilled(bytes32 indexed id);

  error OnlyRouterCanFulfill();

  constructor(address router) {
    i_functionsRouter = IFunctionsRouter(router);
  }

  /**
   * @notice Sends a Chainlink Functions request
   * @param data The CBOR encoded bytes data for a Functions request
   * @param subscriptionId The subscription ID that will be charged to service the request
   * @param callbackGasLimit the amount of gas that will be available for the fulfillment callback
   * @return requestId The generated request ID for this request
   */
  function _sendRequest(
    bytes memory data,
    uint64 subscriptionId,
    uint32 callbackGasLimit,
    bytes32 donId
  ) internal returns (bytes32) {
    bytes32 requestId = i_functionsRouter.sendRequest(
      subscriptionId,
      data,
      FunctionsRequest.REQUEST_DATA_VERSION,
      callbackGasLimit,
      donId
    );
    emit RequestSent(requestId);
    return requestId;
  }

  /**
   * @notice User defined function to handle a response from the DON
   * @param requestId The request ID, returned by sendRequest()
   * @param response Aggregated response from the execution of the user's source code
   * @param err Aggregated error from the execution of the user code or from the execution pipeline
   * @dev Either response or error parameter will be set, but never both
   */
  function _fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal virtual;

  /**
   * @notice Chainlink Functions callback handler
   * @param requestId The request ID, returned by sendRequest()
   * @param response Aggregated response from the execution of the user's source code
   * @param err Aggregated error from the execution of the user code or from the execution pipeline
   * @dev Either response or error parameter will be set, but never both
   */
  function handleOracleFulfillment(bytes32 requestId, bytes memory response, bytes memory err) external override {
    if (msg.sender != address(i_functionsRouter)) {
      revert OnlyRouterCanFulfill();
    }
    _fulfillRequest(requestId, response, err);
    emit RequestFulfilled(requestId);
  }
} 