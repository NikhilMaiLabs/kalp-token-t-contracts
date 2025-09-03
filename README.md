# Token Factory with Linear Bonding Curve and Graduation Mechanics

A comprehensive smart contract system that allows users to launch ERC20 tokens with linear bonding curve pricing and automatic graduation to DEX trading, similar to platforms like pump.fun.

## 🚀 Features

### Core Functionality
- **Linear Bonding Curve Pricing**: Fair launch mechanism with predictable price discovery
- **Automatic Graduation**: Tokens automatically graduate to DEX when market cap threshold is reached
- **Uniswap V2 Integration**: Seamless liquidity provision and pair creation
- **Comprehensive Analytics**: Detailed statistics and tracking for all tokens
- **Security First**: Reentrancy protection, input validation, and access controls

### Token Factory Contract
- Deploy new bonding curve tokens with custom parameters
- Track all created tokens with metadata storage
- Implement creation fee system (default: 0.01 ETH)
- Owner controls for fee management
- Statistics tracking for total tokens, graduated tokens, fees collected

### Bonding Curve Token Contract
- ERC20 compliant with 18 decimals
- Linear price increase based on supply
- Buy/sell functionality with automatic price calculation
- Reentrancy protection on all state-changing functions
- Market cap tracking for graduation triggers

## 📊 Mathematical Implementation

### Linear Bonding Curve Formula
```
price = basePrice + slope × currentSupply
```

### Buy Price Calculation
For linear bonding curve, the cost to buy `amount` tokens is:
```
cost = basePrice × amount + slope × currentSupply × amount + slope × amount × (amount - 1) / 2
```

### Market Cap Calculation
```
marketCap = currentSupply × currentPrice
currentPrice = basePrice + slope × currentSupply
```

## 🏗️ Architecture

### Contracts

1. **TokenFactory.sol** - Main factory contract for creating and managing tokens
2. **BondingCurveToken.sol** - Individual token contract with bonding curve mechanics
3. **TokenFactory.t.sol** - Comprehensive test suite

### Key Components

- **Token Creation**: Users can create tokens with custom parameters
- **Bonding Curve Trading**: Buy/sell tokens at calculated prices
- **Graduation System**: Automatic transition to DEX when threshold is met
- **Fee Distribution**: 80% liquidity, 10% creator, 10% platform
- **Analytics**: Comprehensive tracking and statistics

## 🛠️ Installation & Setup

### Prerequisites
- Node.js (v16 or higher)
- npm or yarn
- Hardhat

### Installation
```bash
# Clone the repository
git clone <repository-url>
cd kalp-token-t-contracts

# Install dependencies
npm install

# Compile contracts
npm run compile

# Run tests
npm test

# Deploy to local network
npm run node
npm run deploy
```

## 📝 Usage

### Creating a Token

```solidity
// Create a token with default graduation threshold (69 ETH)
address tokenAddress = factory.createToken{value: 0.01 ether}(
    "My Token",
    "MTK",
    0.001 ether,  // slope
    0.001 ether   // basePrice
);

// Create a token with custom graduation threshold
address tokenAddress = factory.createTokenWithCustomThreshold{value: 0.01 ether}(
    "My Token",
    "MTK",
    0.001 ether,  // slope
    0.001 ether,  // basePrice
    100 ether     // graduationThreshold
);
```

### Trading Tokens

```solidity
BondingCurveToken token = BondingCurveToken(tokenAddress);

// Buy tokens
uint256 amount = 1000;
uint256 cost = token.getBuyPrice(amount);
token.buyTokens{value: cost}(amount);

// Sell tokens (only before graduation)
token.sellTokens(500);
```

### Getting Token Information

```solidity
// Get current price
uint256 currentPrice = token.getCurrentPrice();

// Get market cap
uint256 marketCap = token.getMarketCap();

// Get graduation progress
(uint256 progress, uint256 remaining) = token.getGraduationProgress();

// Get comprehensive token info
(
    uint256 currentPrice,
    uint256 currentSupply,
    uint256 marketCap,
    uint256 graduationProgress,
    uint256 remainingForGraduation,
    bool graduated,
    address pairAddress
) = token.getTokenInfo();
```

## 🔧 Configuration

### Factory Defaults
- **Creation Fee**: 0.01 ETH
- **Default Graduation Threshold**: 69 ETH market cap
- **Liquidity Percentage**: 80%
- **Creator Fee**: 10%
- **Platform Fee**: 10%

### Token Defaults
- **ERC20 Decimals**: 18
- **Scale Factor**: 1e18 for internal calculations
- **Slippage Tolerance**: 5% for DEX operations

## 🧪 Testing

The project includes comprehensive tests covering:

- Token creation and initialization
- Bonding curve price calculations
- Buy/sell functionality
- Graduation mechanics
- Factory statistics and analytics
- Access control and security
- Error handling and edge cases

Run tests with:
```bash
npm test
```

## 🔒 Security Features

### Critical Security Measures
- **ReentrancyGuard**: Protection against reentrancy attacks
- **Input Validation**: Comprehensive parameter validation
- **Access Control**: Owner-only functions with proper modifiers
- **Overflow Protection**: Safe math operations
- **Emergency Functions**: Recovery mechanisms for stuck funds

### Validation Requirements
- Non-zero parameters for slope, basePrice, graduationThreshold
- Non-empty strings for name and symbol
- Sufficient ETH for operations
- Balance checks before token burns/transfers

## 📈 Analytics & Statistics

### Factory Statistics
```solidity
struct FactoryStats {
    uint256 totalTokens;
    uint256 totalGraduated;
    uint256 totalActiveTokens;
    uint256 totalFeesCollected;
    uint256 totalVolume;
}
```

### Available Analytics Functions
- `getTokenCount()` - Total tokens created
- `getTokensByStatus(bool graduated)` - Filter by graduation status
- `getCreatorTokens(address creator)` - Tokens by creator
- `getFactoryStats()` - Comprehensive statistics
- `getTokensPaginated(offset, limit)` - Paginated token list
- `getRecentTokens(count)` - Recent token creations

## 🎯 Graduation Process

### Automatic Graduation Triggers
- Market cap reaches threshold (default: 69 ETH)
- Manual trigger by factory owner (emergency function)

### Graduation Steps
1. Set `hasGraduated = true`
2. Create Uniswap V2 pair automatically
3. Mint additional tokens equal to current supply for liquidity
4. Add liquidity to DEX with raised ETH
5. Distribute fees according to configured percentages
6. Burn LP tokens for permanent liquidity
7. Emit graduation events

### Fee Distribution
- **80%** of raised ETH → DEX liquidity pool
- **10%** of raised ETH → token creator
- **10%** of raised ETH → platform (factory owner)

## 🔗 Integration

### External Dependencies
- **OpenZeppelin Contracts**: ERC20, Ownable, ReentrancyGuard, Pausable
- **Uniswap V2**: Factory and Router interfaces

### Interface Requirements
```solidity
interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(...) external payable returns (...);
}
```

## 📋 Events

### Token Creation Events
```solidity
event TokenCreated(
    address indexed token,
    string name,
    string symbol,
    uint256 slope,
    uint256 basePrice,
    uint256 graduationThreshold,
    address indexed creator,
    uint256 creationFee
);
```

### Trading Events
```solidity
event TokensPurchased(address indexed buyer, uint256 amount, uint256 cost, uint256 newSupply);
event TokensSold(address indexed seller, uint256 amount, uint256 refund, uint256 newSupply);
```

### Graduation Events
```solidity
event GraduationTriggered(uint256 supply, uint256 marketCap, address dexPair, uint256 liquidityAdded);
event TokenGraduated(address indexed token, uint256 finalSupply, uint256 marketCap, address indexed dexPair, uint256 platformFee);
```

## 🚀 Deployment

### Local Development
```bash
# Start local Hardhat node
npm run node

# Deploy contracts
npm run deploy
```

### Mainnet/Testnet Deployment
```bash
# Deploy to specific network
npx hardhat run scripts/deploy-token-factory.ts --network <network-name>
```

### Environment Variables
Create a `.env` file with:
```
PRIVATE_KEY=your_private_key
INFURA_API_KEY=your_infura_key
ETHERSCAN_API_KEY=your_etherscan_key
```

## 📚 API Reference

### TokenFactory Functions

#### Token Creation
- `createToken(name, symbol, slope, basePrice)` - Create token with default threshold
- `createTokenWithCustomThreshold(name, symbol, slope, basePrice, threshold)` - Create with custom threshold

#### Analytics
- `getTokenCount()` - Total tokens created
- `getTokensByStatus(graduated)` - Filter tokens by status
- `getCreatorTokens(creator)` - Get tokens by creator
- `getFactoryStats()` - Comprehensive statistics
- `getTokenInfo(token)` - Get token metadata

#### Administration
- `updateCreationFee(newFee)` - Update creation fee (owner only)
- `withdrawFees()` - Withdraw collected fees (owner only)
- `triggerGraduation(token)` - Manual graduation trigger (owner only)

### BondingCurveToken Functions

#### Trading
- `buyTokens(amount)` - Buy tokens with ETH
- `sellTokens(amount)` - Sell tokens for ETH (pre-graduation only)
- `getBuyPrice(amount)` - Calculate buy cost
- `getSellPrice(amount)` - Calculate sell refund

#### Information
- `getCurrentPrice()` - Get current token price
- `getMarketCap()` - Calculate market cap
- `getGraduationProgress()` - Get graduation progress
- `getTokenInfo()` - Comprehensive token information

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## ⚠️ Disclaimer

This software is provided "as is" without warranty of any kind. Use at your own risk. Always conduct thorough testing before deploying to mainnet.

## 🆘 Support

For questions, issues, or contributions, please:
1. Check the existing issues
2. Create a new issue with detailed information
3. Join our community discussions

---

**Built with ❤️ for the decentralized future**