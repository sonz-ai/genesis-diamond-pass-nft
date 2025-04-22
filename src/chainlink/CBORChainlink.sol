// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title CBORChainlink
 * @notice CBOR encoding library for Chainlink Functions
 * @dev This is a simplified version of the CBOR encoding library
 */
library CBORChainlink {
  struct Buffer {
    bytes buf;
    uint256 bufPtr;
  }

  /**
   * @notice Initialize a CBOR buffer
   * @param buf The CBOR buffer to initialize
   * @param capacity The initial capacity of the buffer
   */
  function init(Buffer memory buf, uint256 capacity) internal pure {
    if (capacity == 0) {
      capacity = 32;
    }
    buf.buf = new bytes(capacity);
    buf.bufPtr = 0;
  }

  /**
   * @notice Start encoding a CBOR map
   * @param buf The CBOR buffer
   */
  function encodeMap(Buffer memory buf) internal pure {
    buf.buf[buf.bufPtr++] = 0xA0; // Empty map
  }

  /**
   * @notice Encode a string in the CBOR buffer
   * @param buf The CBOR buffer
   * @param value The string to encode
   */
  function encodeString(Buffer memory buf, string memory value) internal pure {
    uint256 len = bytes(value).length;
    
    // Encode the length
    if (len < 24) {
      buf.buf[buf.bufPtr++] = bytes1(uint8(0x60 + len));
    } else if (len < 256) {
      buf.buf[buf.bufPtr++] = 0x78;
      buf.buf[buf.bufPtr++] = bytes1(uint8(len));
    } else {
      buf.buf[buf.bufPtr++] = 0x79;
      buf.buf[buf.bufPtr++] = bytes1(uint8(len >> 8));
      buf.buf[buf.bufPtr++] = bytes1(uint8(len));
    }
    
    // Encode the string data
    bytes memory valueBytes = bytes(value);
    for (uint256 i = 0; i < len; i++) {
      buf.buf[buf.bufPtr++] = valueBytes[i];
    }
  }

  /**
   * @notice Encode bytes in the CBOR buffer
   * @param buf The CBOR buffer
   * @param value The bytes to encode
   */
  function encodeBytes(Buffer memory buf, bytes memory value) internal pure {
    uint256 len = value.length;
    
    // Encode the length
    if (len < 24) {
      buf.buf[buf.bufPtr++] = bytes1(uint8(0x40 + len));
    } else if (len < 256) {
      buf.buf[buf.bufPtr++] = 0x58;
      buf.buf[buf.bufPtr++] = bytes1(uint8(len));
    } else {
      buf.buf[buf.bufPtr++] = 0x59;
      buf.buf[buf.bufPtr++] = bytes1(uint8(len >> 8));
      buf.buf[buf.bufPtr++] = bytes1(uint8(len));
    }
    
    // Encode the bytes data
    for (uint256 i = 0; i < len; i++) {
      buf.buf[buf.bufPtr++] = value[i];
    }
  }

  /**
   * @notice Start encoding an array in the CBOR buffer
   * @param buf The CBOR buffer
   */
  function startArray(Buffer memory buf) internal pure {
    buf.buf[buf.bufPtr++] = 0x9F; // Start indefinite-length array
  }

  /**
   * @notice End a sequence (map or array) in the CBOR buffer
   * @param buf The CBOR buffer
   */
  function endSequence(Buffer memory buf) internal pure {
    buf.buf[buf.bufPtr++] = 0xFF; // Break
  }
} 