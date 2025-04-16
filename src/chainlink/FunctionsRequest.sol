// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/Strings.sol";
import "./CBORChainlink.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

/**
 * @title FunctionsRequest
 * @notice Library for Chainlink Functions request encoding
 * @dev A simplified version of the Chainlink Functions request library
 */
library FunctionsRequest {
  using CBORChainlink for CBORChainlink.Buffer;
  using Strings for string;

  enum Location {
    Inline, // Provided within the Request
    Remote  // Hosted through remote location
  }

  enum CodeLanguage {
    JavaScript, // JavaScript source code
    WebAssembly // WASM binary
  }

  uint16 public constant REQUEST_DATA_VERSION = 1;

  struct Request {
    CBORChainlink.Buffer buf;
    string source;
    string[] args;
    bytes secrets;
  }

  /**
   * @notice Initializes a Chainlink Functions request
   * @param location The location of the source code
   * @param codeLanguage The programming language of the source code
   * @param source The source code or a URL to fetch it from
   * @return A memory reference to a new Request
   */
  function initializeRequest(
    Location location,
    CodeLanguage codeLanguage,
    string memory source
  ) internal pure returns (Request memory) {
    Request memory req;
    req.buf.init(64);
    req.buf.encodeMap();
    
    if (location == Location.Inline) {
      req.buf.encodeString("source");
      req.buf.encodeString(source);
    } else {
      req.buf.encodeString("sourceURL");
      req.buf.encodeString(source);
    }
    
    if (codeLanguage == CodeLanguage.JavaScript) {
      req.buf.encodeString("language");
      req.buf.encodeString("javascript");
    } else {
      req.buf.encodeString("language");
      req.buf.encodeString("wasm");
    }
    
    req.source = source;
    return req;
  }

  /**
   * @notice Sets the arguments for the request
   * @param req The request to add arguments to
   * @param args The array of string arguments
   * @return The modified request
   */
  function setArgs(Request memory req, string[] memory args) internal pure returns (Request memory) {
    req.args = args;
    return req;
  }

  /**
   * @notice Encodes the request as CBOR
   * @param req The request to encode
   * @return CBOR encoded request
   */
  function encodeCBOR(Request memory req) internal pure returns (bytes memory) {
    if (req.args.length > 0) {
      req.buf.encodeString("args");
      req.buf.startArray();
      for (uint256 i = 0; i < req.args.length; i++) {
        req.buf.encodeString(req.args[i]);
      }
      req.buf.endSequence();
    }
    
    if (req.secrets.length > 0) {
      req.buf.encodeString("secrets");
      req.buf.encodeBytes(req.secrets);
    }
    
    req.buf.endSequence();
    return req.buf.buf;
  }
} 