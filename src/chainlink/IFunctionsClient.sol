// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IFunctionsClient
 * @notice Interface for Chainlink Functions client contracts
 */
interface IFunctionsClient {
  /**
   * @notice Chainlink Functions callback handler called by the Functions Router
   * during fulfillment from the designated transmitter node in an OCR round.
   * @param requestId The requestId returned by the client contract when requesting data.
   * @param response Response data from the OCR round.
   * @param err Error from the OCR round, if any.
   */
  function handleOracleFulfillment(bytes32 requestId, bytes memory response, bytes memory err) external;
} 