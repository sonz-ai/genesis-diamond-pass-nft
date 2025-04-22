#!/bin/bash

# Script to initialize and update all git submodules for the Sonzai Diamond Genesis Pass NFT project

echo "Setting up git submodules for Sonzai Diamond Genesis Pass NFT..."

# Initialize and update all submodules recursively
git submodule update --init --recursive

# Check if the submodule initialization was successful
if [ $? -eq 0 ]; then
    echo "✅ Submodules successfully initialized and updated!"
    echo "The following submodules are now available:"
    git submodule status | sed 's/^/  - /'
    echo ""
    echo "You can now run 'forge build' to build the project."
else
    echo "❌ Error initializing submodules. Please check the error messages above."
    exit 1
fi 