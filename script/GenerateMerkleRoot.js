// This script generates a Merkle root from a list of addresses for the whitelist
// Usage: node script/GenerateMerkleRoot.js

const { MerkleTree } = require('merkletreejs');
const keccak256 = require('keccak256');
const { ethers } = require('ethers');

// Replace this array with your whitelist addresses
const whitelistAddresses = [
  '0x1234567890123456789012345678901234567890',
  '0x2345678901234567890123456789012345678901',
  '0x3456789012345678901234567890123456789012',
  // Add more addresses as needed
];

// Function to generate a Merkle tree and root
function generateMerkleRoot(addresses) {
  // Hash each address
  const leaves = addresses.map(addr => 
    ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(['address'], [addr]))
  );
  
  // Create a Merkle tree
  const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
  
  // Get the Merkle root
  const root = tree.getHexRoot();
  
  return { tree, root, leaves };
}

// Generate the Merkle tree and root
const { tree, root, leaves } = generateMerkleRoot(whitelistAddresses);

console.log('Merkle Root:', root);
console.log('\nMerkle Tree:');
console.log(tree.toString());

// Generate proofs for each address
console.log('\nProofs for each address:');
whitelistAddresses.forEach((addr, index) => {
  const leaf = leaves[index];
  const proof = tree.getHexProof(leaf);
  
  console.log(`\nAddress: ${addr}`);
  console.log('Proof:', JSON.stringify(proof));
  
  // Verify the proof
  const isValid = tree.verify(proof, leaf, root);
  console.log('Proof is valid:', isValid);
});

// Instructions for using the Merkle root in the contract
console.log('\n-----------------------------------------');
console.log('Instructions:');
console.log('-----------------------------------------');
console.log('1. Use this Merkle root in your contract deployment:');
console.log(`   bytes32 merkleRoot = ${root};`);
console.log('\n2. When users want to mint with the whitelist, they need to provide the proof for their address.');
console.log('   The proof is the array shown above for each address.');
console.log('\n3. Example usage in JavaScript/ethers.js:');
console.log(`   const proof = [...]; // The proof array for the user's address`);
console.log('   await contract.whitelistMint(proof, { value: ethers.utils.parseEther("0.28") });');
