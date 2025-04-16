// This is a Chainlink Functions request script to fetch NFT sale data from a marketplace
// It will be executed by Chainlink oracle nodes

// Define the API secrets (these would be encrypted when sent to Chainlink Functions)
// const apiKey = args[1] || secrets.OPENSEA_API_KEY;

/**
 * @notice Fetches sale price data for a specific NFT from a marketplace API
 * @param tokenId The ID of the token to fetch sale data for
 * @return A string containing the token ID and sale price in the format "tokenId:salePrice"
 */
async function fetchSaleData() {
  // Get the token ID from the arguments
  const tokenId = args[0];
  
  if (!tokenId) {
    throw Error("Token ID is required");
  }

  // Collection contract address (replace with the actual address if needed)
  const contractAddress = "0x..."; // Replace with the actual contract address
  
  // Marketplace API endpoint to get sales data (example using OpenSea API)
  const apiUrl = `https://api.opensea.io/api/v2/events/chain/ethereum?event_type=sale&token_ids=${tokenId}&asset_contract_address=${contractAddress}`;
  
  // Make request to the marketplace API
  const openseaRequest = {
    url: apiUrl,
    headers: {
      "X-API-KEY": secrets.OPENSEA_API_KEY,
      "Accept": "application/json"
    }
  };
  
  // Send the HTTP request to the OpenSea API
  const openseaResponse = await Functions.makeHttpRequest(openseaRequest);
  
  if (openseaResponse.error) {
    throw Error(`OpenSea API request failed: ${openseaResponse.error}`);
  }
  
  // Check if the response has data and contains the sale events
  if (
    !openseaResponse.data ||
    !openseaResponse.data.asset_events ||
    openseaResponse.data.asset_events.length === 0
  ) {
    // Try to fetch from a backup marketplace API (e.g., LooksRare)
    const looksRareRequest = {
      url: `https://api.looksrare.org/api/v1/events?tokenId=${tokenId}&collection=${contractAddress}&eventType=SALE`,
      headers: {
        "Accept": "application/json"
      }
    };
    
    const looksRareResponse = await Functions.makeHttpRequest(looksRareRequest);
    
    if (looksRareResponse.error) {
      throw Error(`Backup API request failed: ${looksRareResponse.error}`);
    }
    
    if (
      !looksRareResponse.data ||
      !looksRareResponse.data.data ||
      looksRareResponse.data.data.length === 0
    ) {
      throw Error("No sale data found on any marketplace");
    }
    
    // Parse the sale price from the backup marketplace
    const saleEvent = looksRareResponse.data.data[0];
    const salePrice = saleEvent.price;
    
    // Return the tokenId and salePrice in the required format
    return `${tokenId}:${salePrice}`;
  }
  
  // Parse the sale price from OpenSea
  const saleEvent = openseaResponse.data.asset_events[0];
  const salePrice = saleEvent.total_price;
  
  // Return the tokenId and salePrice in the required format
  return `${tokenId}:${salePrice}`;
}

// Execute the function
return fetchSaleData(); 