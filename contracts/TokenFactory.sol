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
            uniswapV2Router
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
     * @dev Get tokens filtered by graduation status
     * @param graduated True for graduated tokens, false for active tokens
     * @return tokenAddresses Array of token addresses
     */
    function getTokensByStatus(bool graduated) external view returns (address[] memory tokenAddresses) {
        uint256 count = 0;
        
        // Count tokens with the specified status
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i].hasGraduated == graduated) {
                count++;
            }
        }
        
        // Create array and populate it
        tokenAddresses = new address[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i].hasGraduated == graduated) {
                tokenAddresses[index] = tokens[i].tokenAddress;
                index++;
            }
        }
        
        return tokenAddresses;
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
     * @dev Get comprehensive factory statistics
     * @return stats Factory statistics struct
     */
    function getFactoryStats() external view returns (FactoryStats memory stats) {
        uint256 graduatedCount = 0;
        uint256 activeCount = 0;
        
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i].hasGraduated) {
                graduatedCount++;
            } else {
                activeCount++;
            }
        }
        
        stats = FactoryStats({
            totalTokens: tokens.length,
            totalGraduated: graduatedCount,
            totalActiveTokens: activeCount,
            totalFeesCollected: totalFeesCollected,
            totalVolume: totalVolume
        });
        
        return stats;
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
     * @dev Manual graduation trigger for emergency cases (owner only)
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
     * @dev Get paginated token list
     * @param offset Starting index
     * @param limit Maximum number of tokens to return
     * @return tokenAddresses Array of token addresses
     * @return hasMore Whether there are more tokens available
     */
    function getTokensPaginated(uint256 offset, uint256 limit) external view returns (
        address[] memory tokenAddresses,
        bool hasMore
    ) {
        require(offset < tokens.length, "Offset out of bounds");
        
        uint256 end = offset + limit;
        if (end > tokens.length) {
            end = tokens.length;
        }
        
        uint256 count = end - offset;
        tokenAddresses = new address[](count);
        
        for (uint256 i = 0; i < count; i++) {
            tokenAddresses[i] = tokens[offset + i].tokenAddress;
        }
        
        hasMore = end < tokens.length;
        
        return (tokenAddresses, hasMore);
    }
    
    /**
     * @dev Get recent tokens (last N tokens created)
     * @param count Number of recent tokens to return
     * @return tokenAddresses Array of recent token addresses
     */
    function getRecentTokens(uint256 count) external view returns (address[] memory tokenAddresses) {
        if (tokens.length == 0) {
            return new address[](0);
        }
        
        uint256 start = tokens.length > count ? tokens.length - count : 0;
        uint256 actualCount = tokens.length - start;
        
        tokenAddresses = new address[](actualCount);
        
        for (uint256 i = 0; i < actualCount; i++) {
            tokenAddresses[i] = tokens[start + i].tokenAddress;
        }
        
        return tokenAddresses;
    }
    
    /**
     * @dev Check if a token has graduated
     * @param token Token address
     * @return hasGraduated Whether the token has graduated
     */
    function isTokenGraduated(address token) external view validTokenAddress(token) returns (bool) {
        uint256 index = tokenIndex[token];
        return tokens[index].hasGraduated;
    }
    
    /**
     * @dev Get token creation timestamp
     * @param token Token address
     * @return createdAt Creation timestamp
     */
    function getTokenCreationTime(address token) external view validTokenAddress(token) returns (uint256) {
        uint256 index = tokenIndex[token];
        return tokens[index].createdAt;
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
