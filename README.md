# Kalp Token T-Contracts

A comprehensive bonding curve token system that enables seamless token creation, trading, and automatic graduation to decentralized exchange (DEX) trading on Uniswap V2.

## 🌟 Overview

Kalp Token T-Contracts provides a complete infrastructure for creating and managing bonding curve tokens with the following key features:

- **Linear Bonding Curve**: Predictable price discovery using mathematical formulas
- **Native POL Trading**: Direct trading with Polygon's native token (no wrapping required)
- **Automatic Graduation**: Tokens automatically graduate to Uniswap V2 when market cap threshold is reached
- **Comprehensive Fee System**: Configurable trading fees and graduation fee distribution
- **Security Features**: Pause/unpause, blacklist functionality, and reentrancy protection
- **Precise Mathematics**: Fixed-point arithmetic with WAD scaling for accurate calculations

## 🏗️ Architecture

### Core Contracts

1. **TokenFactory** - Central hub for deploying and managing bonding curve tokens
2. **BondingCurveToken** - Individual token contracts with bonding curve mechanics
3. **Blacklist** - Utility contract for account management and compliance

### Key Features

- **Factory Pattern**: Centralized token creation and management
- **Graduation System**: Automatic transition from bonding curve to DEX trading
- **Fee Management**: Flexible fee structures for trading and graduation
- **Admin Controls**: Pause, blacklist, and emergency functions
- **Mathematical Precision**: Exact integral calculations for pricing

## 🚀 Quick Start

### Prerequisites

- Node.js (v16 or higher)
- npm or yarn
- Hardhat
- Local blockchain or testnet access

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd kalp-token-t-contracts

# Install dependencies
npm install

# Compile contracts
npm run compile
```

### Local Development

```bash
# Start local blockchain
npm run node

# In a new terminal, run quick test
npm run quick-test:local

# Or run comprehensive testing
npm run deploy-and-interact:local
```

## 📊 Bonding Curve Mechanics

### Linear Pricing Formula

The bonding curve uses a linear pricing model:

```
Price = Base Price + (Slope × Total Supply) / WAD
```

Where:
- **Base Price**: Starting price for the first token
- **Slope**: Price increase per token minted
- **WAD**: Fixed-point scale (1e18) for precision

### Buy/Sell Calculations

The system uses exact integral calculations for precise pricing:

**Buy Cost:**
```
Cost = (Base Price × Amount) / WAD + (Slope × Amount × (2 × Current Supply + Amount)) / (2 × WAD²)
```

**Sell Proceeds:**
```
Proceeds = (Base Price × Amount) / WAD + (Slope × Amount × (2 × Current Supply - Amount)) / (2 × WAD²)
```

### Example

```solidity
// Token parameters
Base Price: 0.001 ETH (1000e18 wei)
Slope: 0.0001 ETH per token (100e18 wei)
Current Supply: 100 tokens

// Current price
Price = 1000e18 + (100e18 × 100e18) / 1e18 = 11000e18 wei = 0.011 ETH

// Cost to buy 1 token
Cost = 1000e18 + (100e18 × (200e18 + 1e18)) / (2 × 1e18) = 11050e18 wei = 0.01105 ETH
```

## 🎯 Graduation System

### Graduation Process

When a token reaches its graduation threshold:

1. **Market Cap Check**: Token graduates when market cap ≥ graduation threshold
2. **Liquidity Provision**: 80% of raised funds go to Uniswap V2 liquidity
3. **Fee Distribution**: 20% goes to platform, 0% to creator (configurable)
4. **DEX Trading**: Token becomes tradeable on Uniswap V2
5. **Supply Doubling**: Total supply doubles (50% circulating, 50% in liquidity)

### Graduation Parameters

- **Liquidity Fee**: 80% (8000 basis points)
- **Creator Fee**: 0% (0 basis points)
- **Platform Fee**: 20% (2000 basis points)

## 💰 Fee Structure

### Trading Fees

- **Buy Trading Fee**: 0% (configurable, max 10%)
- **Sell Trading Fee**: 0% (configurable, max 10%)

### Creation Fees

- **Token Creation**: 1 POL (configurable)

### Fee Collection

- **Trading Fees**: Sent directly to platform fee collector
- **Creation Fees**: Collected by factory owner
- **Graduation Fees**: Distributed according to configured percentages

## 🔧 Usage

### Creating a Token

```typescript
// Token parameters
const tokenParams = {
  name: "My Awesome Token",
  symbol: "MAT",
  slope: parseEther("0.0001"), // 0.0001 ETH increase per token
  basePrice: parseEther("0.001"), // 0.001 ETH starting price
  graduationThreshold: parseEther("10") // 10 ETH market cap threshold
};

// Create token through factory
const tokenAddress = await factory.createToken(
  tokenParams.name,
  tokenParams.symbol,
  tokenParams.slope,
  tokenParams.basePrice,
  tokenParams.graduationThreshold,
  { value: creationFee }
);
```

### Trading Tokens

```typescript
// Buy tokens
await token.buyTokens(parseEther("1"), { value: buyCost });

// Sell tokens
await token.sellTokens(parseEther("1"), minProceeds);

// Get current price
const currentPrice = await token.getCurrentPrice();

// Get token info
const info = await token.getTokenInfo();
```

### Administrative Functions

```typescript
// Pause token trading
await token.pause();

// Unpause token trading
await token.unpause();

// Block an account
await token.blockAccount(accountAddress);

// Unblock an account
await token.unblockAccount(accountAddress);
```

## 🧪 Testing

### Test Scripts

```bash
# Quick test with mock contracts
npm run quick-test:local

# Comprehensive testing
npm run deploy-and-interact:local

# Test on testnet
npm run deploy-and-interact:amoy
```

### Test Coverage

- **Token Creation**: Factory deployment and token creation
- **Trading Mechanics**: Buy/sell operations with various amounts
- **Price Calculations**: Mathematical accuracy of pricing formulas
- **Graduation Process**: Automatic graduation to DEX
- **Admin Functions**: Pause, blacklist, and emergency functions
- **Edge Cases**: Fractional amounts, large trades, boundary conditions

## 📁 Project Structure

```
kalp-token-t-contracts/
├── contracts/
│   ├── BondingCurveToken.sol      # Main token contract
│   ├── TokenFactory.sol           # Factory contract
│   ├── utils/
│   │   └── Blacklist.sol          # Blacklist utility
│   └── mocks/                     # Mock contracts for testing
├── test/
│   ├── TokenTradingTest.t.sol     # Comprehensive trading tests
│   ├── GraduationTest.t.sol       # Graduation process tests
│   └── ...                        # Additional test files
├── scripts/
│   ├── deploy-token-factory.ts    # Deployment scripts
│   ├── quick-test-local.ts        # Quick testing script
│   └── ...                        # Additional scripts
├── demo-ui.html                   # Interactive demo interface
└── docs/
    ├── PRICING_APPROACH.md        # Detailed pricing documentation
    └── LOCAL_INTERACTION_GUIDE.md # Local development guide
```

## 🔒 Security Features

### Access Control

- **Owner Functions**: Pause, blacklist, and emergency controls
- **Factory Functions**: Fee updates and graduation triggers
- **Reentrancy Protection**: Prevents reentrancy attacks

### Safety Mechanisms

- **Slippage Protection**: Minimum proceeds protection for sells
- **Balance Validation**: Sufficient balance checks
- **State Validation**: Pause and blacklist state checks
- **Overflow Protection**: Safe math operations

### Compliance Features

- **Blacklist System**: Block specific accounts
- **Pause Functionality**: Emergency stop capability
- **Fee Transparency**: Clear fee structure and collection

## 🌐 Network Support

### Supported Networks

- **Local Development**: Hardhat local network
- **Polygon Testnet**: Amoy testnet
- **Polygon Mainnet**: Production deployment
- **Ethereum Testnet**: Sepolia testnet
- **Ethereum Mainnet**: Production deployment

### Deployment

```bash
# Deploy to testnet
npm run deploy:amoy

# Deploy to mainnet
npm run deploy:polygon

# Verify contracts
npm run verify:polygon
```

## 📈 Monitoring and Analytics

### Events

The system emits comprehensive events for monitoring:

- **TokenCreated**: New token deployment
- **TokensPurchased**: Token buy operations
- **TokensSold**: Token sell operations
- **GraduationTriggered**: Token graduation to DEX
- **TradingFeesUpdated**: Fee structure changes

### Information Queries

```typescript
// Get comprehensive token information
const info = await token.getTokenInfo();
// Returns: currentPrice, currentSupply, marketCap, graduationProgress, etc.

// Get factory statistics
const stats = await factory.getTokenCount();
const creatorTokens = await factory.getCreatorTokens(creatorAddress);
```

## 🛠️ Development

### Prerequisites

- Solidity ^0.8.24
- OpenZeppelin Contracts ^5.4.0
- Hardhat ^3.0.3
- Foundry (for testing)

### Building

```bash
# Compile contracts
npm run compile

# Run tests
npm run test

# Run specific test
forge test --match-test testBuyTokens
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## 📚 Documentation

- [Pricing Approach](PRICING_APPROACH.md) - Detailed mathematical documentation
- [Local Interaction Guide](LOCAL_INTERACTION_GUIDE.md) - Local development setup
- [Deployment Guide](DEPLOYMENT.md) - Production deployment instructions

## 🤝 Support

For questions, issues, or contributions:

1. Check the documentation
2. Review existing issues
3. Create a new issue with detailed information
4. Join our community discussions

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## ⚠️ Disclaimer

This software is provided for educational and experimental purposes. Use at your own risk. Always conduct thorough testing and security audits before deploying to production networks.

---

**Built with ❤️ by the Kalp Team**
