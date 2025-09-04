import type { HardhatUserConfig } from "hardhat/config";
import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import "dotenv/config";

// Helper function to get environment variables with fallbacks
function getEnvVar(name: string, fallback?: string): string {
  const value = process.env[name];
  if (!value) {
    if (fallback) {
      return fallback;
    }
    console.warn(`⚠️  Warning: Environment variable ${name} is not set`);
    return "";
  }
  return value;
}

// Helper function to get private key array (filters out invalid keys)
function getPrivateKeyArray(envVarName: string): string[] {
  const key = getEnvVar(envVarName);
  
  // Check if it's a valid private key (not the placeholder)
  if (!key || key === "0x0000000000000000000000000000000000000000000000000000000000000000" || key.length !== 66) {
    console.warn(`⚠️  Warning: Invalid or missing private key for ${envVarName}. Network will use default account.`);
    return [];
  }
  
  return [key];
}

const config: HardhatUserConfig = {
  plugins: [hardhatToolboxViemPlugin],
  solidity: {
    profiles: {
      default: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1, // Low runs value for deployment size optimization
          },
          viaIR: true, // Enable IR-based code generation to handle stack too deep
        },
      },
      production: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          viaIR: true, // Enable IR-based code generation to handle stack too deep
        },
      },
    },
  },
  networks: {
    // Local development networks
    hardhat: {
      type: "edr-simulated",
      chainId: 31337,
    },
    localhost: {
      type: "http",
      url: "http://127.0.0.1:8545",
      chainId: 31337,
    },
    hardhatMainnet: {
      type: "edr-simulated",
      chainType: "l1",
    },
    hardhatOp: {
      type: "edr-simulated",
      chainType: "op",
    },
    
    // Ethereum networks
    mainnet: {
      type: "http",
      chainType: "l1",
      url: getEnvVar("ETHEREUM_RPC_URL", "https://eth-mainnet.g.alchemy.com/v2/demo"),
      accounts: getPrivateKeyArray("ETHEREUM_PRIVATE_KEY"),
      chainId: 1,
    },
    sepolia: {
      type: "http",
      chainType: "l1",
      url: getEnvVar("SEPOLIA_RPC_URL", "https://ethereum-sepolia-rpc.publicnode.com"),
      accounts: getPrivateKeyArray("SEPOLIA_PRIVATE_KEY"),
      chainId: 11155111,
    },
    
    // Polygon networks
    polygon: {
      type: "http",
      chainType: "l1",
      url: getEnvVar("POLYGON_RPC_URL", "https://polygon-rpc.com"),
      accounts: getPrivateKeyArray("POLYGON_PRIVATE_KEY"),
      chainId: 137,
    },
    amoy: {
      type: "http",
      chainType: "l1",
      url: getEnvVar("AMOY_RPC_URL", "https://rpc-amoy.polygon.technology"),
      accounts: getPrivateKeyArray("AMOY_PRIVATE_KEY"),
      chainId: 80002,
    },
  },
};

export default config;
