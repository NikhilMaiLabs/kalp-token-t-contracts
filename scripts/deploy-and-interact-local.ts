import hre from "hardhat";
import { parseEther, formatEther, keccak256, decodeEventLog, toHex } from "viem";
import * as dotenv from "dotenv";

// Load environment variables
dotenv.config();

// Contract ABIs (simplified for interaction)
const TOKEN_FACTORY_ABI = [
  {
    "type": "function",
    "name": "createToken",
    "inputs": [
      {"name": "name", "type": "string"},
      {"name": "symbol", "type": "string"},
      {"name": "slope", "type": "uint256"},
      {"name": "basePrice", "type": "uint256"},
      {"name": "graduationThreshold", "type": "uint256"}
    ],
    "outputs": [{"name": "", "type": "address"}],
    "stateMutability": "payable"
  },
  {
    "type": "function",
    "name": "getTokenCount",
    "inputs": [],
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getTokenInfo",
    "inputs": [{"name": "token", "type": "address"}],
    "outputs": [
      {"name": "tokenAddress", "type": "address"},
      {"name": "name", "type": "string"},
      {"name": "symbol", "type": "string"},
      {"name": "slope", "type": "uint256"},
      {"name": "basePrice", "type": "uint256"},
      {"name": "graduationThreshold", "type": "uint256"},
      {"name": "creator", "type": "address"},
      {"name": "createdAt", "type": "uint256"},
      {"name": "hasGraduated", "type": "bool"},
      {"name": "dexPair", "type": "address"}
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "triggerGraduation",
    "inputs": [{"name": "token", "type": "address"}],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "creationFee",
    "inputs": [],
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getFeeDistribution",
    "inputs": [],
    "outputs": [
      {"name": "", "type": "uint256"},
      {"name": "", "type": "uint256"},
      {"name": "", "type": "uint256"}
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getTradingFees",
    "inputs": [],
    "outputs": [
      {"name": "", "type": "uint256"},
      {"name": "", "type": "uint256"}
    ],
    "stateMutability": "view"
  },
  {
    "type": "event",
    "name": "TokenCreated",
    "inputs": [
      {"name": "token", "type": "address", "indexed": true},
      {"name": "name", "type": "string", "indexed": false},
      {"name": "symbol", "type": "string", "indexed": false},
      {"name": "slope", "type": "uint256", "indexed": false},
      {"name": "basePrice", "type": "uint256", "indexed": false},
      {"name": "graduationThreshold", "type": "uint256", "indexed": false},
      {"name": "creator", "type": "address", "indexed": true},
      {"name": "creationFee", "type": "uint256", "indexed": false}
    ]
  }
] as const;

const BONDING_CURVE_TOKEN_ABI = [
  {
    "type": "function",
    "name": "buyTokens",
    "inputs": [{"name": "amount", "type": "uint256"}],
    "outputs": [],
    "stateMutability": "payable"
  },
  {
    "type": "function",
    "name": "sellTokens",
    "inputs": [
      {"name": "amount", "type": "uint256"},
      {"name": "minProceeds", "type": "uint256"}
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "getCurrentPrice",
    "inputs": [],
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getBuyPrice",
    "inputs": [{"name": "amount", "type": "uint256"}],
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getSellPrice",
    "inputs": [{"name": "amount", "type": "uint256"}],
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getMarketCap",
    "inputs": [],
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getGraduationProgress",
    "inputs": [],
    "outputs": [
      {"name": "", "type": "uint256"},
      {"name": "", "type": "uint256"}
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getTokenInfo",
    "inputs": [],
    "outputs": [
      {"name": "currentPrice", "type": "uint256"},
      {"name": "currentSupply", "type": "uint256"},
      {"name": "marketCap", "type": "uint256"},
      {"name": "graduationProgress", "type": "uint256"},
      {"name": "remainingForGraduation", "type": "uint256"},
      {"name": "graduated", "type": "bool"},
      {"name": "pairAddress", "type": "address"}
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getTradingFees",
    "inputs": [],
    "outputs": [
      {"name": "", "type": "uint256"},
      {"name": "", "type": "uint256"}
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "triggerGraduation",
    "inputs": [],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "totalSupply",
    "inputs": [],
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "balanceOf",
    "inputs": [{"name": "account", "type": "address"}],
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "name",
    "inputs": [],
    "outputs": [{"name": "", "type": "string"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "symbol",
    "inputs": [],
    "outputs": [{"name": "", "type": "string"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "hasGraduated",
    "inputs": [],
    "outputs": [{"name": "", "type": "bool"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "dexPool",
    "inputs": [],
    "outputs": [{"name": "", "type": "address"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "pause",
    "inputs": [],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "unpause",
    "inputs": [],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "blockAccount",
    "inputs": [{"name": "_account", "type": "address"}],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "unblockAccount",
    "inputs": [{"name": "_account", "type": "address"}],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "event",
    "name": "TokensPurchased",
    "inputs": [
      {"name": "buyer", "type": "address", "indexed": true},
      {"name": "amount", "type": "uint256", "indexed": false},
      {"name": "cost", "type": "uint256", "indexed": false},
      {"name": "newSupply", "type": "uint256", "indexed": false}
    ]
  },
  {
    "type": "event",
    "name": "TokensSold",
    "inputs": [
      {"name": "seller", "type": "address", "indexed": true},
      {"name": "amount", "type": "uint256", "indexed": false},
      {"name": "refund", "type": "uint256", "indexed": false},
      {"name": "newSupply", "type": "uint256", "indexed": false}
    ]
  },
  {
    "type": "event",
    "name": "GraduationTriggered",
    "inputs": [
      {"name": "supply", "type": "uint256", "indexed": false},
      {"name": "marketCap", "type": "uint256", "indexed": false},
      {"name": "dexPair", "type": "address", "indexed": false},
      {"name": "liquidityAmount", "type": "uint256", "indexed": false}
    ]
  }
] as const;

interface TokenParams {
  name: string;
  symbol: string;
  slope: bigint;
  basePrice: bigint;
  graduationThreshold: bigint;
}

class LocalDeployAndInteractManager {
  private client: any;
  private viem: any;
  private tokenFactory: any;
  private v2Factory: any;
  private router2: any;
  private weth: any;

  constructor(client: any, viem: any) {
    this.client = client;
    this.viem = viem;
  }

  async deployContracts() {
    console.log("🏗️  Deploying contracts for local testing...");
    
    // Deploy mock contracts first
    console.log("   Deploying MockWETH...");
    this.weth = await this.viem.deployContract("contracts/mocks/MockWETH.sol:MockWETH");
    console.log(`   ✅ MockWETH deployed to: ${this.weth.address}`);
    
    console.log("   Deploying MockUniswapV2Factory...");
    this.v2Factory = await this.viem.deployContract("contracts/mocks/MockUniswapV2Factory.sol:MockUniswapV2Factory");
    console.log(`   ✅ MockUniswapV2Factory deployed to: ${this.v2Factory.address}`);
    
    console.log("   Deploying MockUniswapV2Router...");
    this.router2 = await this.viem.deployContract("contracts/mocks/MockUniswapV2Router.sol:MockUniswapV2Router", [
      this.v2Factory.address,
      this.weth.address
    ]);
    console.log(`   ✅ MockUniswapV2Router deployed to: ${this.router2.address}`);
    
    // Now deploy the TokenFactory with the mock router
    const platformFeeCollector = (await this.viem.getWalletClients())[0].account.address;
    const owner = platformFeeCollector;

    console.log(`   Platform Fee Collector: ${platformFeeCollector}`);
    console.log(`   Owner: ${owner}`);

    console.log("   Deploying TokenFactory...");
    this.tokenFactory = await this.viem.deployContract("TokenFactory", [
      this.router2.address,
      platformFeeCollector as `0x${string}`, 
      owner as `0x${string}`
    ]);

    console.log(`   ✅ TokenFactory deployed to: ${this.tokenFactory.address}`);
    
    console.log("   ✅ All contracts deployed and initialized");
    
    return {
      factoryAddress: this.tokenFactory.address,
      routerAddress: this.router2.address,
      v2FactoryAddress: this.v2Factory.address,
      wethAddress: this.weth.address,
      platformFeeCollector,
      owner
    };
  }

  async getFactoryInfo() {
    console.log("\n📊 TokenFactory Information:");
    
    const creationFee = await this.tokenFactory.read.creationFee();
    const tokenCount = await this.tokenFactory.read.getTokenCount();
    const [liquidityFee, creatorFee, platformFee] = await this.tokenFactory.read.getFeeDistribution();
    const [buyFee, sellFee] = await this.tokenFactory.read.getTradingFees();
    const owner = await this.tokenFactory.read.owner();
    const router = await this.tokenFactory.read.router();
    const platformFeeCollector = await this.tokenFactory.read.platformFeeCollector();

    console.log(`   Creation Fee: ${formatEther(creationFee)} ETH`);
    console.log(`   Total Tokens Created: ${tokenCount.toString()}`);
    console.log(`   Fee Distribution: ${Number(liquidityFee)/100}% Liquidity, ${Number(creatorFee)/100}% Creator, ${Number(platformFee)/100}% Platform`);
    console.log(`   Trading Fees: ${Number(buyFee)/100}% Buy, ${Number(sellFee)/100}% Sell`);
    console.log(`   Owner: ${owner}`);
    console.log(`   Router: ${router}`);
    console.log(`   Platform Fee Collector: ${platformFeeCollector}`);
  }

  async createToken(params: TokenParams): Promise<string> {
    console.log(`\n🚀 Creating token: ${params.name} (${params.symbol})`);
    
    const creationFee = await this.tokenFactory.read.creationFee();
    
    console.log(`   Slope: ${formatEther(params.slope)} ETH per token`);
    console.log(`   Base Price: ${formatEther(params.basePrice)} ETH`);
    console.log(`   Graduation Threshold: ${formatEther(params.graduationThreshold)} ETH`);
    console.log(`   Creation Fee: ${formatEther(creationFee)} ETH`);

    // Create the token
    const hash = await this.tokenFactory.write.createToken([
      params.name,
      params.symbol,
      params.slope,
      params.basePrice,
      params.graduationThreshold
    ], {
      value: creationFee
    });

    console.log(`   Transaction hash: ${hash}`);
    
    // Wait for transaction to be mined
    const receipt = await this.client.waitForTransactionReceipt({ hash });
    
    // Find the TokenCreated event
    const tokenCreatedEvent = receipt.logs.find((log: any) => 
      log.topics[0] === keccak256(toHex("TokenCreated(address,string,string,uint256,uint256,uint256,address,uint256)"))
    );
    
    if (tokenCreatedEvent) {
      const tokenAddress = "0x" + tokenCreatedEvent.topics[1].slice(26); // Extract address from indexed topic
      console.log(`   ✅ Token created at: ${tokenAddress}`);
      return tokenAddress;
    } else {
      throw new Error("TokenCreated event not found in transaction receipt");
    }
  }

  async getTokenInfo(tokenAddress: string) {
    console.log(`\n📋 Token Information for ${tokenAddress}:`);
    
    const token = await this.viem.getContractAt(
      "BondingCurveToken",
      tokenAddress as `0x${string}`,
      { client: this.client }
    );
    
    const [
      currentPrice,
      currentSupply,
      marketCap,
      graduationProgress,
      remainingForGraduation,
      graduated,
      pairAddress
    ] = await token.read.getTokenInfo();

    const [buyFee, sellFee] = await token.read.getTradingFees();
    const name = await token.read.name();
    const symbol = await token.read.symbol();

    console.log(`   Name: ${name}`);
    console.log(`   Symbol: ${symbol}`);
    console.log(`   Current Price: ${formatEther(currentPrice)} ETH`);
    console.log(`   Total Supply: ${formatEther(currentSupply)} tokens`);
    console.log(`   Market Cap: ${formatEther(marketCap)} ETH`);
    console.log(`   Graduation Progress: ${Number(graduationProgress)/100}%`);
    console.log(`   Remaining for Graduation: ${formatEther(remainingForGraduation)} ETH`);
    console.log(`   Graduated: ${graduated}`);
    console.log(`   DEX Pair: ${pairAddress}`);
    console.log(`   Trading Fees: ${Number(buyFee)/100}% Buy, ${Number(sellFee)/100}% Sell`);

    return {
      currentPrice,
      currentSupply,
      marketCap,
      graduationProgress,
      remainingForGraduation,
      graduated,
      pairAddress,
      buyFee,
      sellFee
    };
  }

  async buyTokens(tokenAddress: string, amount: string) {
    console.log(`\n💰 Buying ${amount} tokens from ${tokenAddress}`);
    
    const token = await this.viem.getContractAt(
      "BondingCurveToken",
      tokenAddress as `0x${string}`,
      { client: this.client }
    );
    
    const amountTokens = BigInt(amount);
    
    // Get current token info for debugging
    const currentSupply = await token.read.totalSupply();
    const currentPrice = await token.read.getCurrentPrice();
    const [buyFee] = await token.read.getTradingFees();
    
    console.log(`   Current Supply: ${formatEther(currentSupply)} tokens`);
    console.log(`   Current Price: ${formatEther(currentPrice)} ETH per token`);
    console.log(`   Buy Fee: ${Number(buyFee)/100}%`);
    
    // Get buy price
    const buyPrice = await token.read.getBuyPrice([amountTokens]);
    
    // Validate buy price is reasonable
    if (buyPrice > parseEther("1000")) {
      console.log(`   ⚠️  Warning: Buy price is very high: ${formatEther(buyPrice)} ETH`);
      console.log(`   This might be due to large amount or high slope. Consider buying smaller amounts.`);
    }
    
    const tradingFee = (buyPrice * BigInt(buyFee)) / 10000n;
    const totalCost = buyPrice + tradingFee;

    console.log(`   Buy Price: ${formatEther(buyPrice)} ETH`);
    console.log(`   Trading Fee: ${formatEther(tradingFee)} ETH`);
    console.log(`   Total Cost: ${formatEther(totalCost)} ETH`);

    // Additional validation
    if (totalCost > parseEther("10000")) {
      throw new Error(`Total cost too high: ${formatEther(totalCost)} ETH. This suggests an issue with the bonding curve parameters.`);
    }

    // Execute buy transaction
    const hash = await token.write.buyTokens([amountTokens], {
      value: totalCost
    });
    
    console.log(`   Transaction hash: ${hash}`);
    
    // Wait for transaction to be mined
    const receipt = await this.client.waitForTransactionReceipt({ hash });
    
    // Find the TokensPurchased event
    const tokensPurchasedEvent = receipt.logs.find((log: any) => 
      log.topics[0] === keccak256(toHex("TokensPurchased(address,uint256,uint256,uint256)"))
    );
    
    if (tokensPurchasedEvent) {
      const decoded = decodeEventLog({
        abi: BONDING_CURVE_TOKEN_ABI,
        data: tokensPurchasedEvent.data,
        topics: tokensPurchasedEvent.topics
      }) as any;
      console.log(`   ✅ Purchased ${formatEther(decoded.args.amount)} tokens for ${formatEther(decoded.args.cost)} ETH`);
      console.log(`   New Supply: ${formatEther(decoded.args.newSupply)} tokens`);
    }
  }

  async sellTokens(tokenAddress: string, amount: string) {
    console.log(`\n💸 Selling ${amount} tokens to ${tokenAddress}`);
    
    const token = await this.viem.getContractAt(
      "BondingCurveToken",
      tokenAddress as `0x${string}`,
      { client: this.client }
    );
    
    const amountTokens = BigInt(amount);
    
    // Get sell price
    const sellPrice = await token.read.getSellPrice([amountTokens]);
    const [, sellFee] = await token.read.getTradingFees();
    const tradingFee = (sellPrice * BigInt(sellFee)) / 10000n;
    const netRefund = sellPrice - tradingFee;

    console.log(`   Sell Price: ${formatEther(sellPrice)} ETH`);
    console.log(`   Trading Fee: ${formatEther(tradingFee)} ETH`);
    console.log(`   Net Refund: ${formatEther(netRefund)} ETH`);

    // Execute sell transaction with minimum proceeds protection
    const hash = await token.write.sellTokens([amountTokens, netRefund]);
    console.log(`   Transaction hash: ${hash}`);
    
    // Wait for transaction to be mined
    const receipt = await this.client.waitForTransactionReceipt({ hash });
    
    // Find the TokensSold event
    const tokensSoldEvent = receipt.logs.find((log: any) => 
      log.topics[0] === keccak256(toHex("TokensSold(address,uint256,uint256,uint256)"))
    );
    
    if (tokensSoldEvent) {
      const decoded = decodeEventLog({
        abi: BONDING_CURVE_TOKEN_ABI,
        data: tokensSoldEvent.data,
        topics: tokensSoldEvent.topics
      }) as any;
      console.log(`   ✅ Sold ${formatEther(decoded.args.amount)} tokens for ${formatEther(decoded.args.refund)} ETH`);
      console.log(`   New Supply: ${formatEther(decoded.args.newSupply)} tokens`);
    }
  }

  async triggerGraduation(tokenAddress: string) {
    console.log(`\n🎓 Triggering graduation for ${tokenAddress}`);
    
    const token = await this.viem.getContractAt(
      "BondingCurveToken",
      tokenAddress as `0x${string}`,
      { client: this.client }
    );
    
    // Check if already graduated
    const hasGraduated = await token.read.hasGraduated();
    if (hasGraduated) {
      console.log("   ⚠️  Token has already graduated");
      return;
    }

    // Trigger graduation via factory (admin function)
    const hash = await this.tokenFactory.write.triggerGraduation([tokenAddress as `0x${string}`]);
    console.log(`   Transaction hash: ${hash}`);
    
    // Wait for transaction to be mined
    const receipt = await this.client.waitForTransactionReceipt({ hash });
    
    // Find the GraduationTriggered event
    const graduationEvent = receipt.logs.find((log: any) => 
      log.topics[0] === keccak256(toHex("GraduationTriggered(uint256,uint256,address,uint256)"))
    );
    
    if (graduationEvent) {
      const decoded = decodeEventLog({
        abi: BONDING_CURVE_TOKEN_ABI,
        data: graduationEvent.data,
        topics: graduationEvent.topics
      }) as any;
      console.log(`   ✅ Token graduated!`);
      console.log(`   Final Supply: ${formatEther(decoded.args.supply)} tokens`);
      console.log(`   Market Cap: ${formatEther(decoded.args.marketCap)} ETH`);
      console.log(`   DEX Pair: ${decoded.args.dexPair}`);
      console.log(`   Liquidity Tokens: ${formatEther(decoded.args.liquidityAmount)}`);
    }
  }

  async pauseToken(tokenAddress: string) {
    console.log(`\n⏸️  Pausing token ${tokenAddress}`);
    
    const token = await this.viem.getContractAt(
      "BondingCurveToken",
      tokenAddress as `0x${string}`,
      { client: this.client }
    );
    
    const hash = await token.write.pause();
    console.log(`   Transaction hash: ${hash}`);
    
    const receipt = await this.client.waitForTransactionReceipt({ hash });
    console.log(`   ✅ Token paused successfully`);
  }

  async unpauseToken(tokenAddress: string) {
    console.log(`\n▶️  Unpausing token ${tokenAddress}`);
    
    const token = await this.viem.getContractAt(
      "BondingCurveToken",
      tokenAddress as `0x${string}`,
      { client: this.client }
    );
    
    const hash = await token.write.unpause();
    console.log(`   Transaction hash: ${hash}`);
    
    const receipt = await this.client.waitForTransactionReceipt({ hash });
    console.log(`   ✅ Token unpaused successfully`);
  }

  async blockAccount(tokenAddress: string, account: string) {
    console.log(`\n🚫 Blocking account ${account} for token ${tokenAddress}`);
    
    const token = await this.viem.getContractAt(
      "BondingCurveToken",
      tokenAddress as `0x${string}`,
      { client: this.client }
    );
    
    const hash = await token.write.blockAccount([account as `0x${string}`]);
    console.log(`   Transaction hash: ${hash}`);
    
    const receipt = await this.client.waitForTransactionReceipt({ hash });
    console.log(`   ✅ Account blocked successfully`);
  }

  async unblockAccount(tokenAddress: string, account: string) {
    console.log(`\n✅ Unblocking account ${account} for token ${tokenAddress}`);
    
    const token = await this.viem.getContractAt(
      "BondingCurveToken",
      tokenAddress as `0x${string}`,
      { client: this.client }
    );
    
    const hash = await token.write.unblockAccount([account as `0x${string}`]);
    console.log(`   Transaction hash: ${hash}`);
    
    const receipt = await this.client.waitForTransactionReceipt({ hash });
    console.log(`   ✅ Account unblocked successfully`);
  }

  async getAccountBalance(tokenAddress: string, account: string) {
    const token = await this.viem.getContractAt(
      "BondingCurveToken",
      tokenAddress as `0x${string}`,
      { client: this.client }
    );
    
    const balance = await token.read.balanceOf([account as `0x${string}`]);
    console.log(`   Account ${account} balance: ${formatEther(balance)} tokens`);
    return balance;
  }
}

async function main() {
  console.log("🚀 Starting Local Deploy and Interact Script (Fixed)");
  console.log("=" .repeat(60));

  // Connect to local network
  const { viem } = await hre.network.connect();
  const client = await viem.getPublicClient();
  const [account] = await viem.getWalletClients();
  
  console.log(`👤 Using account: ${account.account.address}`);
  console.log(`💰 Account balance: ${formatEther(await client.getBalance({ address: account.account.address }))} ETH`);

  // Initialize the manager
  const manager = new LocalDeployAndInteractManager(client, viem);
  
  try {
    // Step 1: Deploy contracts
    console.log("\n" + "=".repeat(60));
    console.log("🏗️  DEPLOYMENT PHASE");
    console.log("=".repeat(60));
    
    const deploymentInfo = await manager.deployContracts();
    
    // Step 2: Get factory information
    console.log("\n" + "=".repeat(60));
    console.log("📊 FACTORY INFORMATION");
    console.log("=".repeat(60));
    
    await manager.getFactoryInfo();
    
    // Step 3: Create tokens with different parameters
    console.log("\n" + "=".repeat(60));
    console.log("🚀 TOKEN CREATION PHASE");
    console.log("=".repeat(60));
    
    // Token 1: Low slope, low graduation threshold
    const token1Params: TokenParams = {
      name: "Low Slope Token",
      symbol: "LST",
      slope: parseEther("0.0001"), // 0.0001 ETH increase per token
      basePrice: parseEther("0.001"), // 0.001 ETH starting price
      graduationThreshold: parseEther("0.5") // 0.5 ETH market cap threshold
    };
    
    const token1Address = await manager.createToken(token1Params);
    await manager.getTokenInfo(token1Address);
    
    // Token 2: Higher slope, higher graduation threshold
    const token2Params: TokenParams = {
      name: "High Slope Token",
      symbol: "HST",
      slope: parseEther("0.001"), // 0.001 ETH increase per token
      basePrice: parseEther("0.01"), // 0.01 ETH starting price
      graduationThreshold: parseEther("2") // 2 ETH market cap threshold
    };
    
    const token2Address = await manager.createToken(token2Params);
    await manager.getTokenInfo(token2Address);
    
    // Step 4: Test trading on Token 1
    console.log("\n" + "=".repeat(60));
    console.log("🛒 TRADING PHASE - TOKEN 1");
    console.log("=".repeat(60));
    
    await manager.buyTokens(token1Address, "1000000000000000000"); // Buy 1 token
    await manager.getTokenInfo(token1Address);

    await manager.buyTokens(token1Address, "2000000000000000000"); // Buy 2 more tokens
    await manager.getTokenInfo(token1Address);

    await manager.sellTokens(token1Address, "1000000000000000000"); // Sell 1 token
    await manager.getTokenInfo(token1Address);
    
    // Step 5: Test pause/unpause functionality
    console.log("\n" + "=".repeat(60));
    console.log("⏸️  PAUSE/UNPAUSE TESTING - TOKEN 1");
    console.log("=".repeat(60));
    
    await manager.pauseToken(token1Address);
    
    // Try to buy while paused (should fail)
    try {
      await manager.buyTokens(token1Address, "1");
      console.log("   ❌ Buy succeeded while paused - this shouldn't happen!");
    } catch (error) {
      console.log("   ✅ Buy correctly failed while paused");
    }
    
    await manager.unpauseToken(token1Address);
    await manager.buyTokens(token1Address, "1"); // Should work now
    console.log("   ✅ Buy succeeded after unpausing");
    
    // Step 6: Test blacklist functionality
    console.log("\n" + "=".repeat(60));
    console.log("🚫 BLACKLIST TESTING - TOKEN 1");
    console.log("=".repeat(60));
    
    // Create a second account for testing
    const testAccount = "0x1234567890123456789012345678901234567890"; // Mock address
    
    await manager.blockAccount(token1Address, testAccount);
    console.log("   ✅ Account blocked successfully");
    
    await manager.unblockAccount(token1Address, testAccount);
    console.log("   ✅ Account unblocked successfully");
    
    // Step 7: Test graduation
    console.log("\n" + "=".repeat(60));
    console.log("🎓 GRADUATION TESTING - TOKEN 1");
    console.log("=".repeat(60));
    
    const token1Info = await manager.getTokenInfo(token1Address);
    
    if (token1Info.graduated) {
      console.log("🎉 Token 1 has already graduated!");
    } else {
      console.log("⏳ Token 1 has not graduated yet. Triggering manual graduation...");
      await manager.triggerGraduation(token1Address);
    }
    
    // Step 8: Test trading on Token 2
    console.log("\n" + "=".repeat(60));
    console.log("🛒 TRADING PHASE - TOKEN 2");
    console.log("=".repeat(60));
    
    await manager.buyTokens(token2Address, "1"); // Buy 1 token
    await manager.getTokenInfo(token2Address);

    await manager.buyTokens(token2Address, "3"); // Buy 3 more tokens
    await manager.getTokenInfo(token2Address);

    await manager.sellTokens(token2Address, "2"); // Sell 2 tokens
    await manager.getTokenInfo(token2Address);
    
    // Step 9: Test graduation on Token 2
    console.log("\n" + "=".repeat(60));
    console.log("🎓 GRADUATION TESTING - TOKEN 2");
    console.log("=".repeat(60));
    
    const token2Info = await manager.getTokenInfo(token2Address);
    
    if (token2Info.graduated) {
      console.log("🎉 Token 2 has already graduated!");
    } else {
      console.log("⏳ Token 2 has not graduated yet. Triggering manual graduation...");
      await manager.triggerGraduation(token2Address);
    }

    console.log("\n" + "=".repeat(60));
    console.log("✅ LOCAL DEPLOY AND INTERACT SCRIPT COMPLETED SUCCESSFULLY!");
    console.log("=".repeat(60));
    
    console.log("\n📋 Summary:");
    console.log(`   Factory Address: ${deploymentInfo.factoryAddress}`);
    console.log(`   Token 1 Address: ${token1Address}`);
    console.log(`   Token 2 Address: ${token2Address}`);
    console.log(`   Network: Local Hardhat`);
    
    console.log("\n🔄 Next Steps:");
    console.log("   1. Test with different bonding curve parameters");
    console.log("   2. Test with multiple accounts");
    console.log("   3. Test edge cases and error conditions");
    console.log("   4. Test with real Uniswap V2 integration");
    console.log("   5. Deploy to testnet for more comprehensive testing");

  } catch (error) {
    console.error("❌ Error during execution:", error);
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
