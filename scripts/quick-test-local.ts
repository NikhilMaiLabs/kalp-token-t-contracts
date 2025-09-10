import hre from "hardhat";
import { parseEther, formatEther } from "viem";

/**
 * Quick test script for local blockchain interaction (Fixed)
 * This script demonstrates basic token creation and trading functionality
 * Uses proper mock contracts to avoid deployment issues
 */
async function main() {
  console.log("🚀 Quick Local Test Script (Fixed)");
  console.log("=" .repeat(40));

  // Connect to local network
  const { viem } = await hre.network.connect();
  const client = await viem.getPublicClient();
  const [account] = await viem.getWalletClients();
  
  console.log(`👤 Using account: ${account.account.address}`);
  console.log(`💰 Account balance: ${formatEther(await client.getBalance({ address: account.account.address }))} ETH`);

  try {
    // Step 1: Deploy mock contracts first
    console.log("\n🏗️  Deploying mock contracts...");
    
    // Deploy MockWETH
    console.log("   Deploying MockWETH...");
    const weth = await viem.deployContract("contracts/mocks/MockWETH.sol:MockWETH");
    console.log(`   ✅ MockWETH deployed to: ${weth.address}`);
    
    // Deploy MockUniswapV2Factory
    console.log("   Deploying MockUniswapV2Factory...");
    const v2Factory = await viem.deployContract("contracts/mocks/MockUniswapV2Factory.sol:MockUniswapV2Factory");
    console.log(`   ✅ MockUniswapV2Factory deployed to: ${v2Factory.address}`);
    
    // Deploy MockUniswapV2Router
    console.log("   Deploying MockUniswapV2Router...");
    const router = await viem.deployContract("contracts/mocks/MockUniswapV2Router.sol:MockUniswapV2Router", [
      v2Factory.address,
      weth.address
    ]);
    console.log(`   ✅ MockUniswapV2Router deployed to: ${router.address}`);
    
    // Step 2: Deploy TokenFactory
    console.log("\n🏗️  Deploying TokenFactory...");
    
    const platformFeeCollector = account.account.address;
    const owner = account.account.address;

    const tokenFactory = await viem.deployContract("TokenFactory", [
      router.address,
      platformFeeCollector as `0x${string}`, 
      owner as `0x${string}`
    ]);

    console.log(`✅ TokenFactory deployed to: ${tokenFactory.address}`);
    
    // Step 3: Create a test token
    console.log("\n🚀 Creating test token...");
    
    const tokenParams = {
      name: "Quick Test Token",
      symbol: "QTT",
      slope: parseEther("0.0001"), // 0.0001 ETH increase per token
      basePrice: parseEther("0.001"), // 0.001 ETH starting price
      graduationThreshold: parseEther("0.5") // 0.5 ETH market cap threshold
    };
    
    const creationFee = await tokenFactory.read.creationFee();
    console.log(`   Creation fee: ${formatEther(creationFee)} ETH`);
    
    const hash = await tokenFactory.write.createToken([
      tokenParams.name,
      tokenParams.symbol,
      tokenParams.slope,
      tokenParams.basePrice,
      tokenParams.graduationThreshold
    ], {
      value: creationFee
    });
    
    console.log(`   Transaction hash: ${hash}`);
    
    // Wait for transaction to be mined
    const receipt = await client.waitForTransactionReceipt({ hash });
    console.log(`✅ Token created successfully!`);
    
    // Extract token address from event (simplified)
    const tokenAddress = "0x" + (receipt.logs[0]?.topics[1]?.slice(26) || "");
    console.log(`   Token address: ${tokenAddress}`);
    
    // Step 4: Get token contract and test basic functions
    console.log("\n📋 Testing token functions...");
    
    const token = await viem.getContractAt(
      "BondingCurveToken",
      tokenAddress as `0x${string}`
    );
    
    // Get token info
    const name = await token.read.name();
    const symbol = await token.read.symbol();
    const currentPrice = await token.read.getCurrentPrice();
    const totalSupply = await token.read.totalSupply();
    const marketCap = await token.read.getMarketCap();
    
    console.log(`   Name: ${name}`);
    console.log(`   Symbol: ${symbol}`);
    console.log(`   Current Price: ${formatEther(currentPrice)} ETH`);
    console.log(`   Total Supply: ${formatEther(totalSupply)} tokens`);
    console.log(`   Market Cap: ${formatEther(marketCap)} ETH`);
    
    // Step 5: Buy some tokens
    console.log("\n💰 Buying tokens...");
    
    const amountToBuy = BigInt(1); // Buy 1 token
    const buyPrice = await token.read.getBuyPrice([amountToBuy]);
    const [buyFee] = await token.read.getTradingFees();
    const tradingFee = (buyPrice * BigInt(buyFee)) / 10000n;
    const totalCost = buyPrice + tradingFee;
    
    console.log(`   Buying ${amountToBuy.toString()} token(s)`);
    console.log(`   Buy price: ${formatEther(buyPrice)} ETH`);
    console.log(`   Trading fee: ${formatEther(tradingFee)} ETH`);
    console.log(`   Total cost: ${formatEther(totalCost)} ETH`);
    
    const buyHash = await token.write.buyTokens([amountToBuy], {
      value: totalCost
    });
    
    console.log(`   Transaction hash: ${buyHash}`);
    
    // Wait for transaction to be mined
    const buyReceipt = await client.waitForTransactionReceipt({ hash: buyHash });
    console.log(`✅ Tokens purchased successfully!`);
    
    // Check new token info
    const newTotalSupply = await token.read.totalSupply();
    const newMarketCap = await token.read.getMarketCap();
    const newPrice = await token.read.getCurrentPrice();
    
    console.log(`   New Total Supply: ${formatEther(newTotalSupply)} tokens`);
    console.log(`   New Market Cap: ${formatEther(newMarketCap)} ETH`);
    console.log(`   New Price: ${formatEther(newPrice)} ETH per token`);
    
    // Step 6: Test graduation
    console.log("\n🎓 Testing graduation...");
    
    const [graduationProgress, remainingForGraduation] = await token.read.getGraduationProgress();
    console.log(`   Graduation Progress: ${Number(graduationProgress)/100}%`);
    console.log(`   Remaining for Graduation: ${formatEther(remainingForGraduation)} ETH`);
    
    if (graduationProgress >= 10000n) {
      console.log("   🎉 Token is ready for graduation!");
      
      // Trigger graduation
      const graduationHash = await tokenFactory.write.triggerGraduation([tokenAddress as `0x${string}`]);
      console.log(`   Graduation transaction hash: ${graduationHash}`);
      
      const graduationReceipt = await client.waitForTransactionReceipt({ hash: graduationHash });
      console.log(`✅ Token graduated successfully!`);
    } else {
      console.log("   ⏳ Token not ready for graduation yet");
    }
    
    console.log("\n" + "=".repeat(40));
    console.log("✅ Quick test completed successfully!");
    console.log("=".repeat(40));
    
    console.log("\n📋 Summary:");
    console.log(`   Factory Address: ${tokenFactory.address}`);
    console.log(`   Token Address: ${tokenAddress}`);
    console.log(`   Token Name: ${name}`);
    console.log(`   Token Symbol: ${symbol}`);
    console.log(`   Final Supply: ${formatEther(newTotalSupply)} tokens`);
    console.log(`   Final Market Cap: ${formatEther(newMarketCap)} ETH`);
    
    console.log("\n🔄 Next Steps:");
    console.log("   1. Run the full interaction script: npm run deploy-and-interact:local-fixed");
    console.log("   2. Test with different parameters");
    console.log("   3. Test with multiple accounts");
    console.log("   4. Deploy to testnet for more comprehensive testing");

  } catch (error) {
    console.error("❌ Error during quick test:", error);
    throw error;
  }
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
