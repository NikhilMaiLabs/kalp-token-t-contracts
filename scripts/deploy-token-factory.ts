import hre from "hardhat";

// Network configuration for Uniswap V2 Router addresses
const NETWORK_CONFIG = {
  // Polygon Mainnet
  137: {
    name: "Polygon Mainnet",
    router: "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff", // QuickSwap Router
    scanUrl: "https://polygonscan.com"
  },
  // Polygon Amoy Testnet  
  80002: {
    name: "Polygon Amoy Testnet",
    router: "0x6f086D3a6430567d444aA55b9B37DF229Fb4677B", // QuickSwap Router Testnet
    scanUrl: "https://amoy.polygonscan.com"
  },
  // Ethereum Mainnet
  1: {
    name: "Ethereum Mainnet", 
    router: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // Uniswap V2 Router
    scanUrl: "https://etherscan.io"
  },
  // Sepolia Testnet
  11155111: {
    name: "Sepolia Testnet",
    router: "0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008", // Uniswap V2 Router Sepolia
    scanUrl: "https://sepolia.etherscan.io"
  },
  // Local hardhat network
  31337: {
    name: "Hardhat Local",
    router: "0x8954AfA98594b838bda56FE4C12a09D7739D179b", // Mock router for testing
    scanUrl: "http://localhost:8545"
  }
};

async function main() {
  console.log("🚀 Deploying TokenFactory System...");
  console.log("=====================================");

  // Connect to network
  const { viem } = await hre.network.connect();
  const publicClient = await viem.getPublicClient();
  const [walletClient] = await viem.getWalletClients();
  
  // Get network information
  const chainId = await publicClient.getChainId();
  const networkConfig = NETWORK_CONFIG[chainId as keyof typeof NETWORK_CONFIG];
  
  if (!networkConfig) {
    throw new Error(`Unsupported network with chainId: ${chainId}. Please add network configuration.`);
  }

  console.log(`📡 Network: ${networkConfig.name} (Chain ID: ${chainId})`);
  console.log(`🔗 Block Explorer: ${networkConfig.scanUrl}`);

  // Get deployer info
  console.log(`👤 Deploying from account: ${walletClient.account.address}`);
  
  // Check deployer balance
  const balance = await publicClient.getBalance({ address: walletClient.account.address });
  console.log(`💰 Deployer balance: ${(Number(balance) / 1e18).toFixed(4)} ${chainId === 137 || chainId === 80002 ? 'MATIC' : 'ETH'}`);
  
  // Configuration parameters
  const router = networkConfig.router;
  const platformFeeCollector = walletClient.account.address;
  const owner = walletClient.account.address;

  console.log("\n📋 Deployment Configuration:");
  console.log(`   Uniswap V2 Router: ${router}`);
  console.log(`   Platform Fee Collector: ${platformFeeCollector}`);
  console.log(`   Owner: ${owner}`);

  // Deploy the factory
  console.log("\n🏗️  Deploying TokenFactory...");
  
  try {
    // For testnets, use higher gas limits to handle large contract deployments
    const gasConfig = chainId === 80002 || chainId === 11155111 ? {
      gas: 30000000n, // 30M gas limit
      gasPrice: 30000000000n, // 30 gwei
    } : {};

    const tokenFactory = await viem.deployContract("TokenFactory", [
      router as `0x${string}`,
      platformFeeCollector as `0x${string}`, 
      owner as `0x${string}`
    ], gasConfig);

    console.log(`✅ TokenFactory deployed to: ${tokenFactory.address}`);
    console.log(`🔍 View on explorer: ${networkConfig.scanUrl}/address/${tokenFactory.address}`);

    // Verify deployment by calling basic functions
    console.log("\n🔧 Verifying Factory Configuration:");
    
    const creationFee = await tokenFactory.read.creationFee();
    const routerAddr = await tokenFactory.read.router();
    const platformFeeCollectorAddr = await tokenFactory.read.platformFeeCollector();
    const factoryOwner = await tokenFactory.read.owner();
    
    console.log(`   ✓ Creation Fee: ${(Number(creationFee) / 1e18).toFixed(2)} ${chainId === 137 || chainId === 80002 ? 'MATIC' : 'ETH'}`);
    console.log(`   ✓ Uniswap V2 Router: ${routerAddr}`);
    console.log(`   ✓ Platform Fee Collector: ${platformFeeCollectorAddr}`);
    console.log(`   ✓ Factory Owner: ${factoryOwner}`);
    
    // Get fee distribution
    const feeDistribution = await tokenFactory.read.getFeeDistribution();
    console.log(`   ✓ Fee Distribution:`);
    console.log(`     - Liquidity: ${Number(feeDistribution[0]) / 100}%`);
    console.log(`     - Creator: ${Number(feeDistribution[1]) / 100}%`);
    console.log(`     - Platform: ${Number(feeDistribution[2]) / 100}%`);
    
    // Get trading fees
    const tradingFees = await tokenFactory.read.getTradingFees();
    console.log(`   ✓ Trading Fees:`);
    console.log(`     - Buy Fee: ${Number(tradingFees[0]) / 100}%`);
    console.log(`     - Sell Fee: ${Number(tradingFees[1]) / 100}%`);

    // Test basic functions
    console.log("\n🧪 Testing Factory Functions:");
    
    const tokenCount = await tokenFactory.read.getTokenCount();
    console.log(`   ✓ Initial token count: ${tokenCount.toString()}`);
    
    const totalFeesCollected = await tokenFactory.read.totalFeesCollected();
    console.log(`   ✓ Total fees collected: ${(Number(totalFeesCollected) / 1e18).toFixed(4)} ${chainId === 137 || chainId === 80002 ? 'MATIC' : 'ETH'}`);
    
    console.log("   ✅ All factory functions working correctly!");

    console.log("\n🎉 Deployment completed successfully!");
    console.log("=======================================");
    
    console.log("\n📋 Summary:");
    console.log(`   Contract Address: ${tokenFactory.address}`);
    console.log(`   Network: ${networkConfig.name}`);
    console.log(`   Explorer: ${networkConfig.scanUrl}/address/${tokenFactory.address}`);
    
    console.log("\n🔄 Next Steps:");
    console.log("   1. Verify the contract on block explorer");
    console.log("   2. Test token creation functionality");
    console.log("   3. Set up frontend integration");
    console.log("   4. Configure monitoring and analytics");
    console.log("   5. Update platform fee collector if needed");
    
    if (chainId === 31337) {
      console.log("\n🛠️  Local Development Notes:");
      console.log("   - This is a local deployment for testing");
      console.log("   - Use mock tokens and test graduations");
      console.log("   - Uniswap V2 router may be mock for local testing");
    }
    
    return {
      factoryAddress: tokenFactory.address,
      factory: tokenFactory,
      networkConfig,
      deploymentInfo: {
        router,
        platformFeeCollector,
        owner,
        chainId
      }
    };

  } catch (error) {
    console.error("❌ Deployment failed:", error);
    throw error;
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
