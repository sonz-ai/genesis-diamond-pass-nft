# DiamondGenesisPass Implementation Guide

## Overview
This guide outlines how to implement the DiamondGenesisPass NFT with proper ERC721C support and royalty handling. The contract follows the Creator Token Standard required for OpenSea's Seaport fee enforcement.

## Prerequisites
- Solidity ^0.8.24
- OpenZeppelin Contracts (for ERC721, etc.)
- Existing ERC721C implementation

## Implementation Steps

### 1. Contract Structure
The DiamondGenesisPass inherits from:
- `ERC721C` - Base implementation with Creator Token Standard
- `MetadataURI` - For token URI handling
- `IERC2981` - For royalty support
- `Ownable` - For ownership functionality

```solidity
contract DiamondGenesisPass is 
    ERC721C, 
    MetadataURI,
    IERC2981,
    Ownable {
    // Implementation
}
```

### 2. Key Functionality
The following functionality needs to be implemented:

#### Creator Token Standard Implementation
ERC721C already implements the Creator Token Standard which includes:
```solidity
interface ICreatorToken {
    event TransferValidatorUpdated(address oldValidator, address newValidator);
    function getTransferValidator() external view returns (address validator);
    function getTransferValidationFunction() external view returns (bytes4 functionSignature, bool isViewFunction);
    function setTransferValidator(address validator) external;
}
```

#### Royalty Implementation
The contract needs to implement `royaltyInfo()` which directs payments to the CentralizedRoyaltyDistributor:

```solidity
function royaltyInfo(
    uint256 /* tokenId */,
    uint256 salePrice
) external view override returns (address receiver, uint256 royaltyAmount) {
    return (royaltyDistributor, (salePrice * royaltyFeeNumerator) / FEE_DENOMINATOR);
}
```

#### Minting Functions
Implement both public and whitelist minting with payment handling:

```solidity
// Whitelist minting with Merkle proof verification
function whitelistMint(uint256 quantity, bytes32[] calldata merkleProof) external payable {
    // 1. Verify Merkle proof
    // 2. Check payment
    // 3. Mint tokens
    // 4. Register minters with distributor
}

// Public minting
function mint(address to, uint256 tokenId) external payable {
    // Implementation
}
```

### 3. Token Minting and Royalty Record Keeping
When minting tokens, register the minter with the CentralizedRoyaltyDistributor:

```solidity
function _mint(address to, uint256 tokenId) internal virtual override {
    centralizedDistributor.setTokenMinter(address(this), tokenId, to);
    super._mint(to, tokenId);
}
```

### 4. Manual Sale Recording
For recording sales data, include a function that can be called by the contract owner:

```solidity
function recordSale(uint256 tokenId, uint256 salePrice) external {
    _requireCallerIsContractOwner();
    centralizedDistributor.recordSale(address(this), tokenId, salePrice);
    emit SaleDataUpdated(address(this), tokenId, salePrice);
}
```

### 5. Deployment Process
1. Deploy CentralizedRoyaltyDistributor
2. Deploy DiamondGenesisPass with:
   - Royalty distributor address
   - Royalty fee percentage (e.g., 7.5%)
   - Creator address
3. Set Merkle root for whitelist
4. Enable minting when ready

## Future Enhancements

### Chainlink Functions Integration
In a future version, the contract can be extended to include Chainlink Functions integration for automated sales data collection:

1. Inherit from ChainlinkFunctionsClient:
   ```solidity
   contract DiamondGenesisPassWithOracle is DiamondGenesisPass, ChainlinkFunctionsClient {
       // Additional implementation
   }
   ```

2. Implement Functions for fetching sale data:
   ```solidity
   // Request data from Chainlink Functions
   function requestTokenSaleData(uint256 tokenId) external {
       // Implementation
   }

   // Handle response from Chainlink Functions
   function _fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
       // Process response and update royalty information
   }
   ```

3. Create JavaScript code for Chainlink Functions execution:
   ```javascript
   // This is executed by Chainlink Functions oracle nodes
   async function fetchSaleData() {
     const tokenId = args[0];
     
     // Fetch data from marketplace APIs
     const apiRequest = await Functions.makeHttpRequest({
       url: `https://api.marketplace.com/sales?tokenId=${tokenId}`
     });
     
     // Process response
     const salePrice = apiRequest.data.price;
     
     // Return as tokenId:price format
     return `${tokenId}:${salePrice}`;
   }

   // Execute the function
   return fetchSaleData();
   ```

## Important Considerations
1. ERC721C already implements the Creator Token Standard interface
2. The contract should properly register each token's original minter with the distributor
3. Merkle tree implementation for whitelist should follow best practices
4. The current implementation directly includes CentralizedRoyaltyAdapter functionality rather than inheriting from it

## Notes on OpenSea Seaport Fee Enforcement
By implementing ERC721C which follows the Creator Token Standard, the contract becomes eligible for creator earnings enforcement via OpenSea's Seaport. The contract owner should set the StrictAuthorizedTransferSecurityRegistry as their transfer validator on OpenSea Studio to enable this functionality. 