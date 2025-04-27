#!/usr/bin/env bash

# Load environment variables from .env file
if [ -f .env ]
then
  export $(egrep -v '^#' .env | xargs)
else
  echo "Please set your .env file"
  exit 1
fi

# Check if PRIVATE_KEY is set in the environment
if [ -z "$PRIVATE_KEY" ]; then
  echo "PRIVATE_KEY must be set in the .env file."
  exit 1
fi

# Set Basecamp RPC URL
RPC_URL="https://rpc.basecamp.t.raas.gelato.cloud"

# Request additional information from the user
echo "Please enter the oracle address (default: $ORACLE_ADDRESS):"
read input_oracle
ORACLE=${input_oracle:-$ORACLE_ADDRESS}

echo "Please enter collateral token address (leave empty to deploy a new token):"
read collateral_token_address

echo "Please enter house fee percentage (default: $HOUSE_FEE):"
read input_fee
FEE=${input_fee:-$HOUSE_FEE}

# Confirm input with the user
echo "Deploying EnhancedSportsPrediction contract with the following parameters:"
echo "Network: Basecamp"
echo "RPC URL: $RPC_URL"
echo "Collateral Token Address: $collateral_token_address"
echo "Oracle Address: $ORACLE"
echo "Fee: $FEE"
echo ""

# Deploy the contract
echo "Deploying contract..."
forge create ./src/EnhancedSportsPrediction.sol:EnhancedSportsPrediction \
    --broadcast \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --constructor-args $collateral_token_address $ORACLE $FEE \
    --legacy \
    --chain-id 123420001114 \
    --verify \
    --verifier blockscout \
    --verifier-url https://rpc.camp-network-testnet.gelato.digitalurl/api \
    --etherscan-api-key TNWAH96HFPTKCHFPCH964PW43FNV8642PM 

# Note about verification
echo ""
echo "EnhancedSportsPrediction deployed! 🎉🎉"
echo ""
echo "To verify your contract on Basecamp explorer:"
echo "forge verify-contract --chain-id 123420001114 --rpc-url $RPC_URL --verifier blockscout --verifier-url https://basecamp.cloud.blockscout.com/api <CONTRACT_ADDRESS> src/EnhancedSportsPrediction.sol:EnhancedSportsPrediction --constructor-args \$(cast abi-encode \"constructor(address,address,uint256)\" $collateral_token_address $ORACLE $FEE)"
echo ""
echo "Check your contract at: https://basecamp.cloud.blockscout.com/"
