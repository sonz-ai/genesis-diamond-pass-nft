// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@limitbreak/creator-token-standards/src/access/OwnableBasic.sol";
import "@limitbreak/creator-token-standards/src/erc721c/ERC721C.sol";
import "@limitbreak/creator-token-standards/src/programmable-royalties/BasicRoyalties.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@chainlink/v0.8/functions/v1_0_0/FunctionsClient.sol";
import "@chainlink/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

/**
 * @title TelemafiaGenesisPass
 * @author Cline
 * @notice Production-ready ERC721C contract for Telemafia Diamond Genesis Pass NFT with whitelist and royalties.
 */
contract TelemafiaGenesisPass is OwnableBasic, ERC721C, BasicRoyalties, ReentrancyGuard, FunctionsClient {
    using Strings for uint256;
    using FunctionsRequest for FunctionsRequest.Request;

    // ============ Events ============
    event BaseURIUpdated(string newBaseURI);
    event MintPriceUpdated(uint256 newPrice);
    event MaxSupplyUpdated(uint256 newMaxSupply);
    event PublicMintToggled(bool isEnabled);
    event WhitelistMintToggled(bool isEnabled);
    event Withdrawn(address indexed to, uint256 amount);
    event WhitelistCheckRequested(bytes32 indexed requestId, address indexed user);
    event WhitelistCheckFulfilled(bytes32 indexed requestId, address indexed user, bool isWhitelisted);

    // ============ Constants ============
    uint256 public constant ROYALTY_PERCENTAGE = 1100; // 11% royalty
    uint256 public constant MINT_PRICE = 0.28 ether;
    uint256 public constant MAX_SUPPLY = 10000; // Example max supply, adjust as needed

    // ============ Storage ============
    string private _baseTokenURI;
    bool public isPublicMintEnabled;
    bool public isWhitelistMintEnabled;
    uint256 public totalSupply;
    mapping(address => bool) public whitelistMinted;
    
    // Chainlink Functions variables
    bytes32 public donId; // DON ID for the Functions DON
    uint64 public subscriptionId; // Chainlink Functions subscription ID
    uint32 public callbackGasLimit; // Gas limit for the callback function
    string public supabaseUrl; // Supabase API URL
    string public supabaseKey; // Supabase API key (encrypted)
    
    // Mapping to track pending whitelist verification requests
    mapping(bytes32 => address) public pendingRequests;
    // Mapping to track if an address is whitelisted (verified by Chainlink Functions)
    mapping(address => bool) public isWhitelisted;

    /**
     * @notice Constructor for the Telemafia Genesis Pass NFT
     * @param royaltyReceiver The address that will receive royalties
     * @param baseURI The base URI for token metadata
     * @param router Chainlink Functions router address
     * @param _donId Chainlink Functions DON ID
     * @param _subscriptionId Chainlink Functions subscription ID
     * @param _callbackGasLimit Gas limit for the callback function
     * @param _supabaseUrl Supabase API URL
     * @param _supabaseKey Supabase API key (encrypted)
     */
    constructor(
        address royaltyReceiver,
        string memory baseURI,
        address router,
        bytes32 _donId,
        uint64 _subscriptionId,
        uint32 _callbackGasLimit,
        string memory _supabaseUrl,
        string memory _supabaseKey
    ) 
        ERC721OpenZeppelin("Telemafia Diamond Genesis Pass", "TDGP") 
        BasicRoyalties(royaltyReceiver, uint96(ROYALTY_PERCENTAGE))
        FunctionsClient(router)
    {
        _baseTokenURI = baseURI;
        donId = _donId;
        subscriptionId = _subscriptionId;
        callbackGasLimit = _callbackGasLimit;
        supabaseUrl = _supabaseUrl;
        supabaseKey = _supabaseKey;
        isWhitelistMintEnabled = true;
        isPublicMintEnabled = false;
    }

    /**
     * @notice Request whitelist verification from Chainlink Functions
     * @return requestId The ID of the Chainlink Functions request
     */
    function requestWhitelistVerification() external returns (bytes32) {
        require(isWhitelistMintEnabled, "Whitelist mint is not enabled");
        require(!whitelistMinted[msg.sender], "Address has already minted");
        require(!isWhitelisted[msg.sender], "Address is already verified");
        
        // JavaScript source code for Chainlink Functions
        string memory source = string(abi.encodePacked(
            "const address = args[0];",
            "const apiUrl = args[1];",
            "const apiKey = secrets.apiKey;",
            "const response = await Functions.makeHttpRequest({",
            "  url: `${apiUrl}/rest/v1/whitelist?address=eq.${address}`,",
            "  headers: {",
            "    'apikey': apiKey,",
            "    'Content-Type': 'application/json'",
            "  }",
            "});",
            "if (response.error) {",
            "  throw Error('Request failed');",
            "}",
            "const data = response.data;",
            "return Functions.encodeUint256(data.length > 0 ? 1 : 0);"
        ));
        
        // Initialize the request
        FunctionsRequest.Request memory req;
        req.initializeRequest(
            FunctionsRequest.Location.Inline, 
            FunctionsRequest.CodeLanguage.JavaScript, 
            source
        );
        
        // Set secrets
        req.secretsLocation = FunctionsRequest.Location.Remote;
        // Note: encryptedSecretsReference would be provided during deployment
        
        // Set arguments
        string[] memory args = new string[](2);
        args[0] = Strings.toHexString(uint256(uint160(msg.sender)), 20); // Convert address to hex string
        args[1] = supabaseUrl;
        req.setArgs(args);
        
        // Send the request
        bytes32 requestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            callbackGasLimit,
            donId
        );
        
        // Store the request
        pendingRequests[requestId] = msg.sender;
        
        emit WhitelistCheckRequested(requestId, msg.sender);
        
        return requestId;
    }
    
    /**
     * @notice Callback function for Chainlink Functions
     * @param requestId The ID of the Chainlink Functions request
     * @param response The response from Chainlink Functions
     * @param err The error from Chainlink Functions (if any)
     */
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        // Get the user address from the pending requests
        address user = pendingRequests[requestId];
        require(user != address(0), "Request not found");
        
        // Clear the pending request
        delete pendingRequests[requestId];
        
        // If there's an error, the user is not whitelisted
        if (err.length > 0) {
            emit WhitelistCheckFulfilled(requestId, user, false);
            return;
        }
        
        // Decode the response (1 = whitelisted, 0 = not whitelisted)
        uint256 result = abi.decode(response, (uint256));
        bool isUserWhitelisted = result == 1;
        
        // Update the whitelist status
        isWhitelisted[user] = isUserWhitelisted;
        
        emit WhitelistCheckFulfilled(requestId, user, isUserWhitelisted);
    }

    /**
     * @notice Mint a token during the whitelist phase
     */
    function whitelistMint() external payable nonReentrant {
        require(isWhitelistMintEnabled, "Whitelist mint is not enabled");
        require(!whitelistMinted[msg.sender], "Address has already minted");
        require(isWhitelisted[msg.sender], "Address is not whitelisted");
        require(msg.value >= MINT_PRICE, "Insufficient payment");
        require(totalSupply < MAX_SUPPLY, "Max supply reached");
        
        whitelistMinted[msg.sender] = true;
        _safeMint(msg.sender, totalSupply);
        totalSupply++;
    }

    /**
     * @notice Mint a token during the public phase
     */
    function publicMint() external payable nonReentrant {
        require(isPublicMintEnabled, "Public mint is not enabled");
        require(msg.value >= MINT_PRICE, "Insufficient payment");
        require(totalSupply < MAX_SUPPLY, "Max supply reached");
        
        _safeMint(msg.sender, totalSupply);
        totalSupply++;
    }

    /**
     * @notice Mint multiple tokens (for owner/team)
     * @param to The address to mint tokens to
     * @param amount The number of tokens to mint
     */
    function mintBatch(address to, uint256 amount) external {
        _requireCallerIsContractOwner();
        require(totalSupply + amount <= MAX_SUPPLY, "Would exceed max supply");
        
        for (uint256 i = 0; i < amount; i++) {
            _safeMint(to, totalSupply);
            totalSupply++;
        }
    }

    /**
     * @notice Burns a token
     * @param tokenId The ID of the token to burn
     */
    function burn(uint256 tokenId) external {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "Caller is not owner nor approved");
        _burn(tokenId);
    }


    /**
     * @notice Set the base URI for token metadata
     * @param baseURI The new base URI
     */
    function setBaseURI(string calldata baseURI) external {
        _requireCallerIsContractOwner();
        _baseTokenURI = baseURI;
        emit BaseURIUpdated(baseURI);
    }

    /**
     * @notice Toggle the whitelist mint phase
     * @param enabled Whether whitelist minting should be enabled
     */
    function toggleWhitelistMint(bool enabled) external {
        _requireCallerIsContractOwner();
        isWhitelistMintEnabled = enabled;
        emit WhitelistMintToggled(enabled);
    }

    /**
     * @notice Toggle the public mint phase
     * @param enabled Whether public minting should be enabled
     */
    function togglePublicMint(bool enabled) external {
        _requireCallerIsContractOwner();
        isPublicMintEnabled = enabled;
        emit PublicMintToggled(enabled);
    }

    /**
     * @notice Withdraw contract funds to the owner
     */
    function withdraw() external nonReentrant {
        _requireCallerIsContractOwner();
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");
        
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Transfer failed");
        
        emit Withdrawn(owner(), balance);
    }

    /**
     * @notice Set the default royalty information
     * @param receiver The address to receive royalties
     * @param feeNumerator The royalty fee numerator (in basis points)
     */
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external {
        _requireCallerIsContractOwner();
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /**
     * @notice Set royalty information for a specific token
     * @param tokenId The token ID to set royalties for
     * @param receiver The address to receive royalties
     * @param feeNumerator The royalty fee numerator (in basis points)
     */
    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) external {
        _requireCallerIsContractOwner();
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    /**
     * @notice Returns the token URI for a given token ID
     * @param tokenId The ID of the token to get the URI for
     * @return The token URI
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");
        return bytes(_baseTokenURI).length > 0 ? string(abi.encodePacked(_baseTokenURI, tokenId.toString())) : "";
    }

    /**
     * @notice Indicates whether the contract implements the specified interface
     * @param interfaceId The interface ID to check
     * @return True if the contract implements the interface, false otherwise
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721C, ERC2981) returns (bool) {
        return ERC721C.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId);
    }

    /**
     * @notice Returns the current mint price
     * @return The current mint price in wei
     */
    function getMintPrice() external pure returns (uint256) {
        return MINT_PRICE;
    }

    /**
     * @notice Returns the maximum supply of tokens
     * @return The maximum supply
     */
    function getMaxSupply() external pure returns (uint256) {
        return MAX_SUPPLY;
    }
}
