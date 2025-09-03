import { ethers } from "hardhat";

async function main() {
  console.log("Deploying Token Factory System...");

  // Get the contract factory
  const TokenFactory = await ethers.getContractFactory("TokenFactory");
  
  // For mainnet/testnet, you would use the actual Uniswap V2 Router address
  // For local testing, you can use a mock router or deploy one
  const UNISWAP_V2_ROUTER = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"; // Mainnet Uniswap V2 Router
  
  // Deploy the factory
  console.log("Deploying TokenFactory...");
  const factory = await TokenFactory.deploy(UNISWAP_V2_ROUTER);
  await factory.waitForDeployment();
  
  const factoryAddress = await factory.getAddress();
  console.log("TokenFactory deployed to:", factoryAddress);
  
  // Get deployment info
  const creationFee = await factory.creationFee();
  const router = await factory.uniswapV2Router();
  
  console.log("Factory Configuration:");
  console.log("- Creation Fee:", ethers.formatEther(creationFee), "ETH");
  console.log("- Uniswap Router:", router);
  
  // Verify deployment
  console.log("\nVerifying deployment...");
  const tokenCount = await factory.getTokenCount();
  console.log("- Initial token count:", tokenCount.toString());
  
  const stats = await factory.getFactoryStats();
  console.log("- Factory stats:", {
    totalTokens: stats.totalTokens.toString(),
    totalGraduated: stats.totalGraduated.toString(),
    totalActiveTokens: stats.totalActiveTokens.toString(),
    totalFeesCollected: ethers.formatEther(stats.totalFeesCollected),
    totalVolume: ethers.formatEther(stats.totalVolume)
  });
  
  console.log("\nDeployment completed successfully!");
  console.log("\nNext steps:");
  console.log("1. Verify the contract on Etherscan (if on mainnet/testnet)");
  console.log("2. Set up frontend integration");
  console.log("3. Test token creation and trading functionality");
  
  return {
    factoryAddress,
    factory
  };
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
