# TokenFactory Deployment Guide

This guide provides comprehensive instructions for deploying the TokenFactory contract to various networks.

## Prerequisites

1. **Node.js and npm** installed
2. **Hardhat** configured
3. **Private key** with sufficient funds for deployment
4. **RPC endpoint** for your target network
5. **Block explorer API key** for contract verification (optional)

## Quick Start

### 1. Environment Setup

Copy the example environment file and fill in your configuration:

```bash
cp .env.example .env
```

Edit `.env` with your configuration:

```env
# Required for production deployment
POSITION_MANAGER_ADDRESS=0xC36442b4a4522E871399CD717aBDD847Ab11FE88
PLATFORM_FEE_COLLECTOR=0xYourFeeCollectorAddress
FACTORY_OWNER=0xYourOwnerAddress

# Optional configuration (uses defaults if not set)
CREATION_FEE=1.0
LIQUIDITY_FEE=8000
CREATOR_FEE=0
PLATFORM_FEE=2000
```

### 2. Local Development Deployment

For testing and development:

```bash
# Deploy to built-in hardhat network (no separate node needed)
npx hardhat run scripts/deploy-token-factory.ts --network hardhat

# OR start local hardhat node and deploy (requires two terminals)
npx hardhat node
# In a new terminal:
npx hardhat run scripts/deploy-token-factory.ts --network localhost
```

### 3. Testnet Deployment

Deploy to Mumbai testnet for testing:

```bash
npx hardhat run scripts/deploy-token-factory.ts --network mumbai
```

### 4. Production Deployment

For mainnet deployment with additional security checks:

```bash
npx hardhat run scripts/deploy-token-factory-production.ts --network polygon
```

## Network Configurations

### Supported Networks

| Network | Chain ID | Position Manager | Native Currency |
|---------|----------|------------------|-----------------|
| Polygon Mainnet | 137 | `0xC36442b4a4522E871399CD717aBDD847Ab11FE88` | MATIC |
| Mumbai Testnet | 80001 | `0xC36442b4a4522E871399CD717aBDD847Ab11FE88` | MATIC |
| Ethereum Mainnet | 1 | `0xC36442b4a4522E871399CD717aBDD847Ab11FE88` | ETH |
| Sepolia Testnet | 11155111 | `0x1238536071E1c677A632429e3655c799b22cDA52` | ETH |

### Hardhat Network Configuration

Add networks to your `hardhat.config.ts`:

```typescript
networks: {
  polygon: {
    url: process.env.POLYGON_RPC_URL,
    accounts: [process.env.POLYGON_PRIVATE_KEY!]
  },
  mumbai: {
    url: process.env.MUMBAI_RPC_URL,
    accounts: [process.env.MUMBAI_PRIVATE_KEY!]
  }
}
```

## Deployment Scripts

### Standard Deployment (`deploy-token-factory.ts`)

Features:
- Multi-network support with auto-detection
- Comprehensive deployment verification
- User-friendly console output
- Basic configuration validation

Usage:
```bash
npx hardhat run scripts/deploy-token-factory.ts --network <network>
```

### Production Deployment (`deploy-token-factory-production.ts`)

Features:
- Environment variable validation
- Enhanced security checks
- Automatic contract verification
- Deployment info persistence
- Post-deployment configuration
- Production-ready safeguards

Usage:
```bash
npx hardhat run scripts/deploy-token-factory-production.ts --network <network>
```

## Configuration Parameters

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `positionManager` | Uniswap V3 Position Manager address | `0xC36442b4a4522E871399CD717aBDD847Ab11FE88` |
| `platformFeeCollector` | Address receiving platform fees | `0x742d35Cc6634C0532925a3b8D0e8fC8E8b2a8B8A` |
| `owner` | Factory owner with admin privileges | `0x742d35Cc6634C0532925a3b8D0e8fC8E8b2a8B8A` |

### Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `creationFee` | 1.0 ETH | Fee to create new tokens |
| `liquidityFee` | 8000 (80%) | Graduation fee to liquidity |
| `creatorFee` | 0 (0%) | Graduation fee to creator |
| `platformFee` | 2000 (20%) | Graduation fee to platform |
| `buyTradingFee` | 0 (0%) | Trading fee on purchases |
| `sellTradingFee` | 0 (0%) | Trading fee on sales |

## Fee Structure Explained

### Creation Fees
- Charged when deploying new tokens
- Goes to factory owner
- Default: 1 native token (ETH/MATIC)

### Graduation Fees
Applied when tokens graduate to DEX trading:

- **Liquidity Fee (80% default)**: Creates DEX liquidity pool
- **Creator Fee (0% default)**: Reward for token creator
- **Platform Fee (20% default)**: Platform revenue

**Important**: Fees must sum to exactly 10,000 basis points (100%)

### Trading Fees
- Applied to buy/sell transactions
- Sent to platform fee collector
- Maximum: 1,000 basis points (10%)

## Deployment Verification

The deployment scripts automatically verify:

1. ✅ Contract deployment success
2. ✅ Constructor parameters
3. ✅ Fee configuration
4. ✅ Access control setup
5. ✅ Basic function calls
6. ✅ Contract verification (production script)

## Post-Deployment Steps

### 1. Verify Contract (if not automatic)

```bash
npx hardhat verify --network <network> <contract-address> <constructor-arg1> <constructor-arg2> <constructor-arg3>
```

Example:
```bash
npx hardhat verify --network polygon 0x123...abc 0xC36442b4a4522E871399CD717aBDD847Ab11FE88 0x742d35Cc6634C0532925a3b8D0e8fC8E8b2a8B8A 0x742d35Cc6634C0532925a3b8D0e8fC8E8b2a8B8A
```

### 2. Test Token Creation

Create a test token to verify deployment:

```javascript
// Connect to deployed factory
const factory = await ethers.getContractAt("TokenFactory", factoryAddress);

// Create test token
const tx = await factory.createToken(
  "Test Token",
  "TEST", 
  ethers.parseEther("0.0001"), // slope
  ethers.parseEther("0.001"),  // base price
  { value: ethers.parseEther("1") } // creation fee
);

await tx.wait();
console.log("Test token created successfully!");
```

### 3. Configure Frontend Integration

Update your frontend with:
- Factory contract address
- Contract ABI
- Network configuration
- Fee structure information

### 4. Monitor Deployment

Set up monitoring for:
- Token creation events
- Fee collection
- Graduation events
- Trading activity

## Security Considerations

### Production Deployment

1. **Use Multisig Wallets**: Consider using multisig for factory owner
2. **Verify Addresses**: Double-check all addresses before deployment
3. **Test on Testnet**: Always test on testnet first
4. **Monitor Activity**: Set up alerts for unusual activity
5. **Backup Keys**: Securely backup all private keys

### Environment Security

1. **Never commit private keys** to version control
2. **Use environment variables** for sensitive data
3. **Limit API key permissions** to minimum required
4. **Rotate keys regularly** for production systems

## Troubleshooting

### Common Issues

#### Insufficient Balance
```
Error: Insufficient balance for deployment
```
**Solution**: Ensure deployer address has enough native tokens for gas fees.

#### Configuration Variable Not Found
```
HardhatError: Configuration Variable "SEPOLIA_RPC_URL" not found
```
**Solution**: The hardhat config has been updated to handle missing environment variables gracefully. Make sure you have a `.env` file with your configuration, or the system will use defaults.

#### Invalid Position Manager
```
Error: Position manager cannot be zero address
```
**Solution**: Verify the Uniswap V3 Position Manager address for your network.

#### Network Not Supported
```
Error: Unsupported network with chainId: X
```
**Solution**: Add network configuration to the deployment script.

#### Verification Failed
```
Warning: Contract verification failed
```
**Solution**: Verify manually using Hardhat verify command with constructor arguments.

### Getting Help

1. Check deployment logs for specific error messages
2. Verify network configuration and RPC endpoints
3. Ensure sufficient balance and correct private key
4. Test on local network first
5. Review Hardhat and network documentation

## Example Deployment Output

```
🚀 Deploying TokenFactory System...
=====================================
📡 Network: Polygon Mainnet (Chain ID: 137)
👤 Deploying from account: 0x742d35Cc6634C0532925a3b8D0e8fC8E8b2a8B8A
💰 Deployer balance: 5.2 MATIC

📋 Deployment Configuration:
   Position Manager: 0xC36442b4a4522E871399CD717aBDD847Ab11FE88
   Platform Fee Collector: 0x742d35Cc6634C0532925a3b8D0e8fC8E8b2a8B8A
   Owner: 0x742d35Cc6634C0532925a3b8D0e8fC8E8b2a8B8A

🏗️  Deploying TokenFactory...
📄 Transaction hash: 0xabcd1234...
⏳ Waiting for deployment confirmation...
✅ TokenFactory deployed to: 0x123abc456def...
🔍 View on explorer: https://polygonscan.com/address/0x123abc456def...

🔧 Verifying Factory Configuration:
   ✓ Creation Fee: 1.0 POL
   ✓ Position Manager: 0xC36442b4a4522E871399CD717aBDD847Ab11FE88
   ✓ Fee Distribution:
     - Liquidity: 80%
     - Creator: 0%
     - Platform: 20%

🧪 Testing Factory Functions:
   ✓ Initial token count: 0
   ✓ All factory functions working correctly!

🎉 Deployment completed successfully!
```
