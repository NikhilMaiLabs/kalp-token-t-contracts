# Local Blockchain Interaction Guide

This guide explains how to interact with the TokenFactory and BondingCurveToken contracts in a local blockchain environment.

## Prerequisites

1. **Node.js** (v16 or higher) and **npm** installed
2. **Hardhat** project set up
3. **Local blockchain** running (Hardhat node)

## Setup

1. **Install dependencies:**
   ```bash
   npm install
   ```

2. **Start local blockchain:**
   ```bash
   npm run node
   ```
   This will start a local Hardhat node on `http://127.0.0.1:8545`

3. **In a new terminal, compile contracts:**
   ```bash
   npm run compile
   ```

4. **Set up environment variables (optional):**
   ```bash
   # Create .env file for custom configuration
   touch .env
   
   # Add any custom configuration
   echo "LOCAL_FACTORY_ADDRESS=0x..." >> .env
   ```

## Available Scripts

### 1. Quick Test (Recommended for beginners)
This script performs a simple test with proper mock contracts:

```bash
npm run quick-test:local
```

**What it does:**
- Deploys all necessary mock contracts (WETH, Uniswap V2 Factory, Router)
- Deploys TokenFactory contract
- Creates a single test token
- Tests basic buying functionality
- Tests graduation process
- Provides simple logging and error handling

### 2. Deploy and Interact (Comprehensive testing)
This script deploys all contracts and performs comprehensive testing:

```bash
npm run deploy-and-interact:local
```

**What it does:**
- Deploys all necessary mock contracts
- Deploys TokenFactory contract
- Creates two test tokens with different parameters
- Tests buying and selling tokens
- Tests pause/unpause functionality
- Tests blacklist functionality
- Tests graduation process
- Provides comprehensive logging and error handling

### 3. Deploy Factory Only
Deploy just the TokenFactory contract:

```bash
npm run deploy:local
```

**What it does:**
- Deploys TokenFactory contract
- Requires existing Uniswap V2 contracts
- Useful for testing with external DEX contracts

## Script Features

### Token Creation
- Creates tokens with customizable parameters:
  - **Name**: Human-readable token name
  - **Symbol**: Short token symbol
  - **Slope**: Price increase per token (in ETH)
  - **Base Price**: Starting price for first token (in ETH)
  - **Graduation Threshold**: Market cap needed to graduate to DEX (in ETH)

### Trading Functions
- **Buy Tokens**: Purchase tokens using ETH
- **Sell Tokens**: Sell tokens back to the bonding curve
- **Price Calculation**: Automatic price calculation with trading fees
- **Slippage Protection**: Minimum proceeds protection for sells

### Administrative Functions
- **Pause/Unpause**: Emergency stop functionality
- **Blacklist**: Block specific accounts from trading
- **Graduation**: Manual graduation trigger for testing

### Information Queries
- **Token Info**: Complete token information
- **Factory Info**: Factory configuration and statistics
- **Account Balances**: Check token balances
- **Graduation Progress**: Track graduation status

## Demo UI

The project includes an interactive HTML demo interface:

```bash
# Open the demo UI in your browser
open demo-ui.html
```

**Features:**
- Real-time price calculation and display
- Interactive token creation and trading
- Visual bonding curve representation
- Graduation progress tracking
- Error handling and user feedback

## Example Usage

### Basic Token Creation and Trading
```typescript
// Token parameters
const tokenParams = {
  name: "My Test Token",
  symbol: "MTT",
  slope: parseEther("0.0001"), // 0.0001 ETH increase per token
  basePrice: parseEther("0.001"), // 0.001 ETH starting price
  graduationThreshold: parseEther("1") // 1 ETH market cap threshold
};

// Create token through factory
const tokenAddress = await factory.createToken(
  tokenParams.name,
  tokenParams.symbol,
  tokenParams.slope,
  tokenParams.basePrice,
  tokenParams.graduationThreshold,
  { value: parseEther("1") } // Creation fee
);

// Buy tokens
await token.buyTokens(parseEther("1"), { value: buyCost }); // Buy 1 token
await token.buyTokens(parseEther("2"), { value: buyCost }); // Buy 2 more tokens

// Sell tokens
await token.sellTokens(parseEther("1"), minProceeds); // Sell 1 token

// Check token info
const info = await token.getTokenInfo();
```

### Testing Administrative Functions
```typescript
// Pause token
await token.pause();

// Try to buy while paused (will fail)
try {
  await token.buyTokens(parseEther("1"), { value: buyCost });
} catch (error) {
  console.log("Buy correctly failed while paused");
}

// Unpause token
await token.unpause();

// Block account
await token.blockAccount("0x1234...");

// Unblock account
await token.unblockAccount("0x1234...");
```

## Understanding the Bonding Curve

The bonding curve uses a linear pricing model with WAD scaling for precision:

### Price Formula
```
Price = Base Price + (Slope × Total Supply) / WAD
```

Where:
- **Base Price**: Starting price for the first token (in wei, WAD scaled)
- **Slope**: Price increase per token (in wei, WAD scaled)
- **WAD**: Fixed-point scale (1e18) for precision
- **Total Supply**: Current number of tokens in circulation

### Buy/Sell Calculations

**Buy Cost (exact integral):**
```
Cost = (Base Price × Amount) / WAD + (Slope × Amount × (2 × Current Supply + Amount)) / (2 × WAD²)
```

**Sell Proceeds (exact integral):**
```
Proceeds = (Base Price × Amount) / WAD + (Slope × Amount × (2 × Current Supply - Amount)) / (2 × WAD²)
```

### Example Calculation
- Base Price: 1000e18 wei (0.001 ETH)
- Slope: 100e18 wei (0.0001 ETH per token)
- Current Supply: 100e18 wei (100 tokens)
- Current Price: 1000e18 + (100e18 × 100e18) / 1e18 = 11000e18 wei = 0.011 ETH per token

**Cost to buy 1 token:**
- Cost = 1000e18 + (100e18 × (200e18 + 1e18)) / (2 × 1e18) = 11050e18 wei = 0.01105 ETH

## Graduation Process

When a token reaches its graduation threshold:
1. **Market Cap Check**: Token graduates when market cap ≥ graduation threshold
2. **Liquidity Provision**: 80% of raised funds go to Uniswap V2 liquidity
3. **Fee Distribution**: 20% goes to platform, 0% to creator (configurable)
4. **DEX Trading**: Token becomes tradeable on Uniswap V2
5. **Supply Doubling**: Total supply doubles (50% circulating, 50% in liquidity)

## Error Handling

The scripts include comprehensive error handling:
- **Validation**: Parameter validation before transactions
- **Slippage Protection**: Minimum proceeds protection for sells
- **Balance Checks**: Sufficient balance validation
- **State Checks**: Pause and blacklist state validation
- **Transaction Monitoring**: Event emission verification

## Troubleshooting

### Common Issues

1. **"Insufficient funds"**
   - Ensure you have enough ETH in your account
   - Check if the bonding curve parameters are too high

2. **"Token not created by this factory"**
   - Make sure you're using the correct factory address
   - Verify the token was created by the factory

3. **"Token has already graduated"**
   - Check if the token has already graduated to DEX
   - Use `getTokenInfo()` to check graduation status

4. **"Contract paused"**
   - Token is paused, use `unpauseToken()` to resume trading

5. **"Account blocked"**
   - Account is blacklisted, use `unblockAccount()` to restore access

6. **"Internal error" during token creation**
   - This usually happens when using invalid router addresses
   - Use the proper scripts: `quick-test:local` or `deploy-and-interact:local`
   - These scripts properly deploy mock contracts first

7. **"Contract function reverted"**
   - Check that all required mock contracts are deployed
   - Ensure the router has a valid factory address
   - Use the scripts which handle mock contract deployment automatically

8. **"There are multiple artifacts for contract"**
   - This happens when there are duplicate contract names in different files
   - The scripts use fully qualified names to avoid this issue
   - Use `quick-test:local` or `deploy-and-interact:local` scripts

9. **"Insufficient funds for gas"**
   - Ensure your account has enough ETH for gas fees
   - Check that the local blockchain is running and funded
   - Try restarting the local node if needed

10. **"Contract not deployed"**
    - Make sure contracts are compiled first: `npm run compile`
    - Verify the local blockchain is running: `npm run node`
    - Check that the script is using the correct network

### Debug Tips

1. **Check token info** before trading:
   ```typescript
   await manager.getTokenInfo(tokenAddress);
   ```

2. **Verify factory configuration**:
   ```typescript
   await manager.getFactoryInfo();
   ```

3. **Check account balances**:
   ```typescript
   await manager.getAccountBalance(tokenAddress, accountAddress);
   ```

4. **Monitor transaction events** for detailed information

## Testing with Foundry

The project also includes Foundry tests for comprehensive testing:

```bash
# Run all tests
forge test

# Run specific test
forge test --match-test testBuyTokens

# Run tests with verbose output
forge test -vvv

# Run tests and show gas usage
forge test --gas-report
```

**Test Coverage:**
- Token creation and parameter validation
- Bonding curve mathematics and pricing
- Trading operations (buy/sell)
- Graduation process and DEX integration
- Administrative functions (pause, blacklist)
- Edge cases and error conditions

## Next Steps

1. **Test with different parameters** to understand bonding curve behavior
2. **Test with multiple accounts** to simulate real-world usage
3. **Test edge cases** like very high/low parameters
4. **Use the demo UI** for interactive testing
5. **Run Foundry tests** for comprehensive coverage
6. **Deploy to testnet** for more comprehensive testing
7. **Integrate with frontend** for user interface testing

## Gas Optimization Tips

### Efficient Trading
- **Batch operations**: Combine multiple buys/sells in single transaction when possible
- **Optimal amounts**: Use round numbers to minimize gas costs
- **Timing**: Trade during low network congestion periods

### Contract Interaction
- **Read functions**: Use view functions for price calculations before trading
- **Event monitoring**: Listen to events instead of polling for state changes
- **Gas estimation**: Always estimate gas before sending transactions

### Best Practices
- **Slippage protection**: Always set appropriate slippage limits
- **Balance checks**: Verify sufficient balance before trading
- **Error handling**: Implement proper error handling for failed transactions

## Support

For issues or questions:
1. Check the console output for detailed error messages
2. Verify your local blockchain is running
3. Ensure contracts are compiled and deployed
4. Check that you have sufficient ETH balance
5. Review the [PRICING_APPROACH.md](PRICING_APPROACH.md) for mathematical details
6. Check the [README.md](README.md) for comprehensive documentation
