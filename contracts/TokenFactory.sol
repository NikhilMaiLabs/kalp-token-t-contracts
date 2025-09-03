// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./BondingCurveToken.sol";

/**
 * @title TokenFactory
 * @dev Factory contract for creating bonding curve tokens with graduation mechanics
 */
contract TokenFactory is Ownable, ReentrancyGuard {
    // Token metadata structure
    struct TokenInfo {
        address tokenAddress;
        string name;
        string symbol;
        uint256 slope;
        uint256 basePrice;
        uint256 graduationThreshold;
        address creator;
        uint256 createdAt;
        bool hasGraduated;
        address dexPair;
    }
    
    // Factory statistics
    struct FactoryStats {
        uint256 totalTokens;
        uint256 totalGraduated;
        uint256 totalActiveTokens;
        uint256 totalFeesCollected;
        uint256 totalVolume;
    }
    
    // State variables
    uint256 public creationFee = 0.01 ether; // Default creation fee
    address public uniswapV2Router;
    
    // Default fee distribution percentages (in basis points, 10000 = 100%)
    uint256 public liquidityFee = 8000;  // 80% 
    uint256 public creatorFee = 0;       // 0%
    uint256 public platformFee = 2000;   // 20%
    
    // Token tracking
    TokenInfo[] public tokens;
    mapping(address => uint256) public tokenIndex;
    mapping(address => bool) public isTokenCreated;
    mapping(address => uint256[]) public creatorTokens;
    
    // Statistics
    uint256 public totalFeesCollected;
    uint256 public totalVolume;
    
    // Events
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
    
    event TokenGraduated(
        address indexed token,
        uint256 finalSupply,
        uint256 marketCap,
        address indexed dexPair,
        uint256 platformFee
    );
    
    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeesWithdrawn(address indexed owner, uint256 amount);
    event RouterUpdated(address indexed oldRouter, address indexed newRouter);
    event FeeDistributionUpdated(uint256 liquidityFee, uint256 creatorFee, uint256 platformFee);
    
    // Modifiers
    modifier validTokenAddress(address token) {
        require(token != address(0), "Invalid token address");
        require(isTokenCreated[token], "Token not created by this factory");
        _;
    }
    
    modifier validParameters(
        string memory name,
        string memory symbol,
        uint256 slope,
        uint256 basePrice,
        uint256 graduationThreshold
    ) {
        require(bytes(name).length > 0, "Name cannot be empty");
        require(bytes(symbol).length > 0, "Symbol cannot be empty");
        require(slope > 0, "Slope must be greater than 0");
        require(basePrice > 0, "Base price must be greater than 0");
        require(graduationThreshold > 0, "Graduation threshold must be greater than 0");
        _;
    }

    constructor(address _uniswapV2Router) Ownable(msg.sender) {
        require(_uniswapV2Router != address(0), "Router cannot be zero address");
        uniswapV2Router = _uniswapV2Router;
    }
    
    /**
     * @dev Create a new bonding curve token with default graduation threshold
     * @param name Token name
     * @param symbol Token symbol
     * @param slope Price increase per token
     * @param basePrice Initial token price
     * @return tokenAddress Address of the created token
     */
    function createToken(
        string memory name,
        string memory symbol,
        uint256 slope,
        uint256 basePrice
    ) external payable nonReentrant validParameters(name, symbol, slope, basePrice, 69 ether) returns (address tokenAddress) {
        return _createTokenInternal(name, symbol, slope, basePrice, 69 ether);
    }
    
    /**
     * @dev Create a new bonding curve token with custom graduation threshold
     * @param name Token name
     * @param symbol Token symbol
     * @param slope Price increase per token
     * @param basePrice Initial token price
     * @param graduationThreshold Market cap threshold for graduation
     * @return tokenAddress Address of the created token
     */
    function createTokenWithCustomThreshold(
        string memory name,
        string memory symbol,
        uint256 slope,
        uint256 basePrice,
        uint256 graduationThreshold
    ) public payable nonReentrant validParameters(name, symbol, slope, basePrice, graduationThreshold) returns (address tokenAddress) {
        return _createTokenInternal(name, symbol, slope, basePrice, graduationThreshold);
    }
    
    /**
     * @dev Internal function to create tokens without reentrancy protection
     */
    function _createTokenInternal(
        string memory name,
        string memory symbol,
        uint256 slope,
        uint256 basePrice,
        uint256 graduationThreshold
    ) internal returns (address tokenAddress) {
        require(msg.value >= creationFee, "Insufficient creation fee");
        
        // Create new bonding curve token
        BondingCurveToken newToken = new BondingCurveToken(
            name,
            symbol,
            slope,
            basePrice,
            graduationThreshold,
            msg.sender,
            address(this),
            uniswapV2Router,
            liquidityFee,
            creatorFee,
            platformFee
        );
        
        tokenAddress = address(newToken);
        
        // Store token information
        TokenInfo memory tokenInfo = TokenInfo({
            tokenAddress: tokenAddress,
            name: name,
            symbol: symbol,
            slope: slope,
            basePrice: basePrice,
            graduationThreshold: graduationThreshold,
            creator: msg.sender,
            createdAt: block.timestamp,
            hasGraduated: false,
            dexPair: address(0)
        });
        
        tokens.push(tokenInfo);
        tokenIndex[tokenAddress] = tokens.length - 1;
        isTokenCreated[tokenAddress] = true;
        creatorTokens[msg.sender].push(tokens.length - 1);
        
        // Update statistics
        totalFeesCollected += creationFee;
        
        // Refund excess payment
        if (msg.value > creationFee) {
            payable(msg.sender).transfer(msg.value - creationFee);
        }
        
        emit TokenCreated(
            tokenAddress,
            name,
            symbol,
            slope,
            basePrice,
            graduationThreshold,
            msg.sender,
            creationFee
        );
        
        return tokenAddress;
    }
    
    /**
     * @dev Get total number of tokens created
     * @return Total token count
     */
    function getTokenCount() external view returns (uint256) {
        return tokens.length;
    }
    
    /**
     * @dev Get tokens created by a specific creator
     * @param creator Creator address
     * @return tokenAddresses Array of token addresses created by the creator
     */
    function getCreatorTokens(address creator) external view returns (address[] memory tokenAddresses) {
        uint256[] memory tokenIndices = creatorTokens[creator];
        tokenAddresses = new address[](tokenIndices.length);
        
        for (uint256 i = 0; i < tokenIndices.length; i++) {
            tokenAddresses[i] = tokens[tokenIndices[i]].tokenAddress;
        }
        
        return tokenAddresses;
    }
    
    /**
     * @dev Get token information by address
     * @param token Token address
     * @return tokenInfo Token information struct
     */
    function getTokenInfo(address token) external view validTokenAddress(token) returns (TokenInfo memory tokenInfo) {
        uint256 index = tokenIndex[token];
        return tokens[index];
    }
    
    /**
     * @dev Update creation fee (owner only)
     * @param newFee New creation fee in wei
     */
    function updateCreationFee(uint256 newFee) external onlyOwner {
        require(newFee > 0, "Creation fee must be greater than 0");
        uint256 oldFee = creationFee;
        creationFee = newFee;
        
        emit CreationFeeUpdated(oldFee, newFee);
    }
    
    /**
     * @dev Update fee distribution percentages (owner only)
     * @param _liquidityFee New liquidity fee in basis points
     * @param _creatorFee New creator fee in basis points  
     * @param _platformFee New platform fee in basis points
     */
    function updateFeeDistribution(
        uint256 _liquidityFee, 
        uint256 _creatorFee, 
        uint256 _platformFee
    ) external onlyOwner {
        require(_liquidityFee + _creatorFee + _platformFee == 10000, "Fees must sum to 10000 (100%)");
        require(_liquidityFee >= 5000, "Liquidity fee must be at least 50% for proper DEX functionality");
        require(_platformFee <= 3000, "Platform fee cannot exceed 30%");
        
        liquidityFee = _liquidityFee;
        creatorFee = _creatorFee;
        platformFee = _platformFee;
        
        emit FeeDistributionUpdated(_liquidityFee, _creatorFee, _platformFee);
    }
    
    /**
     * @dev Get current fee distribution percentages
     * @return Current liquidity, creator, and platform fee percentages
     */
    function getFeeDistribution() external view returns (uint256, uint256, uint256) {
        return (liquidityFee, creatorFee, platformFee);
    }
    
    /**
     * @dev Update Uniswap router address (owner only)
     * @param newRouter New router address
     */
    function updateRouter(address newRouter) external onlyOwner {
        require(newRouter != address(0), "Router cannot be zero address");
        address oldRouter = uniswapV2Router;
        uniswapV2Router = newRouter;
        
        emit RouterUpdated(oldRouter, newRouter);
    }
    
    /**
     * @dev Withdraw collected fees (owner only)
     */
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        
        payable(owner()).transfer(balance);
        
        emit FeesWithdrawn(owner(), balance);
    }
    
    /**
     * @dev Manual graduation trigger for emergency cases (owner only) // TODO: currently in dev mode to test graduations will be removed later
     * @param token Token address to graduate
     */
    function triggerGraduation(address token) external onlyOwner validTokenAddress(token) {
        BondingCurveToken tokenContract = BondingCurveToken(payable(token));
        tokenContract.triggerGraduation();
        
        // Update token status
        uint256 index = tokenIndex[token];
        tokens[index].hasGraduated = true;
        tokens[index].dexPair = tokenContract.dexPair();
        
        emit TokenGraduated(
            token,
            tokenContract.totalSupply(),
            tokenContract.getMarketCap(),
            tokens[index].dexPair,
            0 // Platform fee handled internally by token
        );
    }
    
    /**
     * @dev Receive ETH
     */
    receive() external payable {}
    
    /**
     * @dev Fallback function
     */
    fallback() external payable {}
}
