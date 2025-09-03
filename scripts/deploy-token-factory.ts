import hre from "hardhat";

// Network configuration for Uniswap V3 Position Manager addresses
const NETWORK_CONFIG = {
  // Polygon Mainnet
  137: {
    name: "Polygon Mainnet",
    positionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
    scanUrl: "https://polygonscan.com"
  },
  // Polygon Mumbai Testnet  
  80001: {
    name: "Polygon Mumbai Testnet",
    positionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
    scanUrl: "https://mumbai.polygonscan.com"
  },
  // Ethereum Mainnet
  1: {
    name: "Ethereum Mainnet", 
    positionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
    scanUrl: "https://etherscan.io"
  },
  // Sepolia Testnet
  11155111: {
    name: "Sepolia Testnet",
    positionManager: "0x1238536071E1c677A632429e3655c799b22cDA52",
    scanUrl: "https://sepolia.etherscan.io"
  },
  // Local hardhat network
  31337: {
    name: "Hardhat Local",
    positionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
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
  console.log(`💰 Deployer balance: ${(Number(balance) / 1e18).toFixed(4)} ${chainId === 137 || chainId === 80001 ? 'MATIC' : 'ETH'}`);

  // Configuration parameters
  const positionManager = networkConfig.positionManager;
  const platformFeeCollector = walletClient.account.address;
  const owner = walletClient.account.address;

  console.log("\n📋 Deployment Configuration:");
  console.log(`   Position Manager: ${positionManager}`);
  console.log(`   Platform Fee Collector: ${platformFeeCollector}`);
  console.log(`   Owner: ${owner}`);

  // Deploy the factory
  console.log("\n🏗️  Deploying TokenFactory...");
  
  try {
    const tokenFactory = await viem.deployContract("TokenFactory", [
      positionManager as `0x${string}`,
      platformFeeCollector as `0x${string}`, 
      owner as `0x${string}`
    ]);

    console.log(`✅ TokenFactory deployed to: ${tokenFactory.address}`);
    console.log(`🔍 View on explorer: ${networkConfig.scanUrl}/address/${tokenFactory.address}`);

    // Verify deployment by calling basic functions
    console.log("\n🔧 Verifying Factory Configuration:");
    
    const creationFee = await tokenFactory.read.creationFee();
    const positionManagerAddr = await tokenFactory.read.positionManager();
    const platformFeeCollectorAddr = await tokenFactory.read.platformFeeCollector();
    const factoryOwner = await tokenFactory.read.owner();
    
    console.log(`   ✓ Creation Fee: ${(Number(creationFee) / 1e18).toFixed(2)} ${chainId === 137 || chainId === 80001 ? 'MATIC' : 'ETH'}`);
    console.log(`   ✓ Position Manager: ${positionManagerAddr}`);
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
    console.log(`   ✓ Total fees collected: ${(Number(totalFeesCollected) / 1e18).toFixed(4)} ${chainId === 137 || chainId === 80001 ? 'MATIC' : 'ETH'}`);
    
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
      console.log("   - Uniswap V3 may not be available locally");
    }
    
    return {
      factoryAddress: tokenFactory.address,
      factory: tokenFactory,
      networkConfig,
      deploymentInfo: {
        positionManager,
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
