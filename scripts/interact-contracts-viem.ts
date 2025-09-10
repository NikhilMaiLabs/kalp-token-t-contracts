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
    "name": "getCreatorTokens",
    "inputs": [{"name": "creator", "type": "address"}],
    "outputs": [{"name": "", "type": "address[]"}],
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
    "inputs": [{"name": "amount", "type": "uint256"}],
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

// Uniswap V2 Router ABI (simplified)
const ROUTER_ABI = [
  {
    "type": "function",
    "name": "WETH",
    "inputs": [],
    "outputs": [{"name": "", "type": "address"}],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "factory",
    "inputs": [],
    "outputs": [{"name": "", "type": "address"}],
    "stateMutability": "pure"
  }
] as const;

// Uniswap V2 Factory ABI (simplified)
const FACTORY_ABI = [
  {
    "type": "function",
    "name": "getPair",
    "inputs": [
      {"name": "tokenA", "type": "address"},
      {"name": "tokenB", "type": "address"}
    ],
    "outputs": [{"name": "pair", "type": "address"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "createPair",
    "inputs": [
      {"name": "tokenA", "type": "address"},
      {"name": "tokenB", "type": "address"}
    ],
    "outputs": [{"name": "pair", "type": "address"}],
    "stateMutability": "nonpayable"
  }
] as const;

interface TokenParams {
  name: string;
  symbol: string;
  slope: bigint;
  basePrice: bigint;
  graduationThreshold: bigint;
}

interface ContractAddresses {
  tokenFactory: string;
  v2Factory: string;
  router2: string;
}

class TokenInteractionManager {
  private client: any;
  private viem: any;
  private tokenFactory: any;
  private v2Factory: any;
  private router2: any;
  private contractAddresses: ContractAddresses;

  constructor(client: any, viem: any, contractAddresses: ContractAddresses) {
    this.client = client;
    this.viem = viem;
    this.contractAddresses = contractAddresses;
  }

  async initialize() {
    console.log("🔧 Initializing contract connections...");
    
    // Initialize TokenFactory
    this.tokenFactory = await this.viem.getContractAt(
      "TokenFactory",
      this.contractAddresses.tokenFactory as `0x${string}`,
      { client: this.client }
    );

    // Initialize V2 Factory
    this.v2Factory = await this.viem.getContractAt(
      "IUniswapV2Factory",
      this.contractAddresses.v2Factory as `0x${string}`,
      { client: this.client }
    );

    // Initialize Router2
    this.router2 = await this.viem.getContractAt(
      "IUniswapV2Router02",
      this.contractAddresses.router2 as `0x${string}`,
      { client: this.client }
    );

    console.log("✅ Contract connections initialized");
  }

  async getFactoryInfo() {
    console.log("\n📊 TokenFactory Information:");
    
    const creationFee = await this.tokenFactory.read.creationFee();
    const tokenCount = await this.tokenFactory.read.getTokenCount();
    const [liquidityFee, creatorFee, platformFee] = await this.tokenFactory.read.getFeeDistribution();
    const [buyFee, sellFee] = await this.tokenFactory.read.getTradingFees();

    console.log(`   Creation Fee: ${formatEther(creationFee)} POL`);
    console.log(`   Total Tokens Created: ${tokenCount.toString()}`);
    console.log(`   Fee Distribution: ${Number(liquidityFee)/100}% Liquidity, ${Number(creatorFee)/100}% Creator, ${Number(platformFee)/100}% Platform`);
    console.log(`   Trading Fees: ${Number(buyFee)/100}% Buy, ${Number(sellFee)/100}% Sell`);
  }

  async createToken(params: TokenParams): Promise<string> {
    console.log(`\n🚀 Creating token: ${params.name} (${params.symbol})`);
    
    const creationFee = await this.tokenFactory.read.creationFee();
    
    console.log(`   Slope: ${formatEther(params.slope)} POL per token`);
    console.log(`   Base Price: ${formatEther(params.basePrice)} POL`);
    console.log(`   Graduation Threshold: ${formatEther(params.graduationThreshold)} POL`);
    console.log(`   Creation Fee: ${formatEther(creationFee)} POL`);

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
    console.log(`   Current Price: ${formatEther(currentPrice)} POL`);
    console.log(`   Total Supply: ${formatEther(currentSupply)} tokens`);
    console.log(`   Market Cap: ${formatEther(marketCap)} POL`);
    console.log(`   Graduation Progress: ${Number(graduationProgress)/100}%`);
    console.log(`   Remaining for Graduation: ${formatEther(remainingForGraduation)} POL`);
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
    
    const amountWei = parseEther(amount);
    const amountTokens = BigInt(amount); // Convert string to BigInt for token count
    
    // Get current token info for debugging
    const currentSupply = await token.read.totalSupply();
    const currentPrice = await token.read.getCurrentPrice();
    const [buyFee] = await token.read.getTradingFees();
    
    console.log(`   Current Supply: ${formatEther(currentSupply)} tokens`);
    console.log(`   Current Price: ${formatEther(currentPrice)} POL per token`);
    console.log(`   Buy Fee: ${Number(buyFee)/100}%`);
    
    // Get buy price - use token count, not wei amount
    const buyPrice = await token.read.getBuyPrice([amountTokens]);
    
    // Validate buy price is reasonable
    if (buyPrice > parseEther("1000")) { // More than 1000 POL
      console.log(`   ⚠️  Warning: Buy price is very high: ${formatEther(buyPrice)} POL`);
      console.log(`   This might be due to large amount or high slope. Consider buying smaller amounts.`);
    }
    
    const tradingFee = (buyPrice * BigInt(buyFee)) / 10000n;
    const totalCost = buyPrice + tradingFee;

    console.log(`   Buy Price: ${formatEther(buyPrice)} POL`);
    console.log(`   Trading Fee: ${formatEther(tradingFee)} POL`);
    console.log(`   Total Cost: ${formatEther(totalCost)} POL`);

    // Additional validation
    if (totalCost > parseEther("10000")) { // More than 10,000 POL
      throw new Error(`Total cost too high: ${formatEther(totalCost)} POL. This suggests an issue with the bonding curve parameters.`);
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
      console.log(`   ✅ Purchased ${formatEther(decoded.args.amount)} tokens for ${formatEther(decoded.args.cost)} POL`);
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
    
    const amountTokens = BigInt(amount); // Convert string to BigInt for token count
    
    // Get sell price
    const sellPrice = await token.read.getSellPrice([amountTokens]);
    const [, sellFee] = await token.read.getTradingFees();
    const tradingFee = (sellPrice * BigInt(sellFee)) / 10000n;
    const netRefund = sellPrice - tradingFee;

    console.log(`   Sell Price: ${formatEther(sellPrice)} POL`);
    console.log(`   Trading Fee: ${formatEther(tradingFee)} POL`);
    console.log(`   Net Refund: ${formatEther(netRefund)} POL`);

    // Execute sell transaction
    const hash = await token.write.sellTokens([amountTokens]);
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
      console.log(`   ✅ Sold ${formatEther(decoded.args.amount)} tokens for ${formatEther(decoded.args.refund)} POL`);
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
      console.log(`   Market Cap: ${formatEther(decoded.args.marketCap)} POL`);
      console.log(`   DEX Pair: ${decoded.args.dexPair}`);
      console.log(`   Liquidity Tokens: ${formatEther(decoded.args.liquidityAmount)}`);
    }
  }

  async checkDEXPair(tokenAddress: string) {
    console.log(`\n🔍 Checking DEX pair for ${tokenAddress}`);
    
    const token = await this.viem.getContractAt(
      "BondingCurveToken",
      tokenAddress as `0x${string}`,
      { client: this.client }
    );
    const wethAddress = await this.router2.read.WETH();
    
    // Check if pair exists
    const pairAddress = await this.v2Factory.read.getPair([tokenAddress as `0x${string}`, wethAddress]);
    
    if (pairAddress === "0x0000000000000000000000000000000000000000") {
      console.log("   ❌ No DEX pair found");
    } else {
      console.log(`   ✅ DEX pair found: ${pairAddress}`);
      console.log(`   WETH Address: ${wethAddress}`);
    }

    return pairAddress;
  }
}

async function main() {
  console.log("🚀 Starting Token Contract Interaction Script");
  console.log("=" .repeat(60));

  // Validate environment variables
  const requiredEnvVars = [
    'PLATFORM_FEE_COLLECTOR',
    'FACTORY_OWNER', 
    'AMOY_PRIVATE_KEY',
    'V2_FACTORY',
    'ROUTER2'
  ];

  for (const envVar of requiredEnvVars) {
    if (!process.env[envVar]) {
      throw new Error(`❌ Missing required environment variable: ${envVar}`);
    }
  }

  // Connect to network
  const { viem } = await hre.network.connect();
  const client = await viem.getPublicClient();
  const [account] = await viem.getWalletClients();
  
  console.log(`👤 Using account: ${account.account.address}`);
  console.log(`💰 Account balance: ${formatEther(await client.getBalance({ address: account.account.address }))} POL`);

  // Contract addresses from environment
  const contractAddresses: ContractAddresses = {
    tokenFactory: process.env.TOKEN_FACTORY_ADDRESS || "", // You'll need to deploy or provide this
    v2Factory: process.env.V2_FACTORY!,
    router2: process.env.ROUTER2!
  };

  if (!contractAddresses.tokenFactory) {
    throw new Error("❌ TOKEN_FACTORY_ADDRESS not provided. Please deploy the TokenFactory first or set the address in .env");
  }

  // Initialize the interaction manager
  const manager = new TokenInteractionManager(client, viem, contractAddresses);
  await manager.initialize();

  // Get factory information
  await manager.getFactoryInfo();

  // Token parameters for creation
  const tokenParams: TokenParams = {
    name: "Test Bonding Token",
    symbol: "TBT",
    slope: parseEther("0.0001"), // 0.0001 POL increase per token (reasonable slope)
    basePrice: parseEther("0.001"), // 0.001 POL starting price (very low)
    graduationThreshold: parseEther("1") // 1 POL market cap threshold (low for testing)
  };

  try {
    // Step 1: Create a new token
    const tokenAddress = await manager.createToken(tokenParams);
    
    // Step 2: Get token information
    await manager.getTokenInfo(tokenAddress);

    // Step 3: Buy some tokens
    console.log("\n" + "=".repeat(60));
    console.log("🛒 BUYING PHASE");
    console.log("=".repeat(60));
    
    await manager.buyTokens(tokenAddress, "1"); // Buy 1 token
    await manager.getTokenInfo(tokenAddress);

    await manager.buyTokens(tokenAddress, "2"); // Buy 2 more tokens
    await manager.getTokenInfo(tokenAddress);

    // Step 4: Sell some tokens
    console.log("\n" + "=".repeat(60));
    console.log("💸 SELLING PHASE");
    console.log("=".repeat(60));
    
    await manager.sellTokens(tokenAddress, "1"); // Sell 1 token
    await manager.getTokenInfo(tokenAddress);

    // Step 5: Check graduation progress
    console.log("\n" + "=".repeat(60));
    console.log("📈 GRADUATION CHECK");
    console.log("=".repeat(60));
    
    const tokenInfo = await manager.getTokenInfo(tokenAddress);
    
    if (tokenInfo.graduated) {
      console.log("🎉 Token has already graduated!");
      await manager.checkDEXPair(tokenAddress);
    } else {
      console.log("⏳ Token has not graduated yet. Triggering manual graduation...");
      
      // Step 6: Trigger graduation (manual for testing)
      await manager.triggerGraduation(tokenAddress);
      
      // Step 7: Check DEX pair after graduation
      await manager.checkDEXPair(tokenAddress);
    }

    console.log("\n" + "=".repeat(60));
    console.log("✅ INTERACTION SCRIPT COMPLETED SUCCESSFULLY!");
    console.log("=".repeat(60));

  } catch (error) {
    console.error("❌ Error during interaction:", error);
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
