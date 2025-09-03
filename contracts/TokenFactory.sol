// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./BondingCurveToken.sol";

/**
 * @title TokenFactory
 * @author Kalp Team
 * @notice Factory contract for deploying and managing bonding curve tokens
 * @dev This contract serves as the central hub for the bonding curve token ecosystem
 * 
 * CORE FUNCTIONALITY:
 * - Deploy new bonding curve tokens with customizable parameters
 * - Manage fee structures and platform settings globally
 * - Track all tokens created through the factory
 * - Provide administrative functions for token management
 * - Handle creation fees and revenue collection
 * 
 * TOKEN DEPLOYMENT:
 * - Users pay a creation fee to deploy new bonding curve tokens
 * - Each token gets unique bonding curve parameters (slope, base price, graduation threshold)
 * - Factory sets fee structures for all tokens (graduation fees & trading fees)
 * - Tokens are automatically configured with DEX integration (Uniswap V2)
 * 
 * FEE MANAGEMENT:
 * - Creation fees: Charged when deploying new tokens
 * - Graduation fees: Split between liquidity, creator, and platform on graduation
 * - Trading fees: Applied to every buy/sell transaction on tokens
 * - Platform fee collector: Centralized address for all fee collection
 * 
 * ADMINISTRATIVE FEATURES:
 * - Update fee structures for future tokens
 * - Modify existing token configurations
 * - Emergency graduation triggers
 * - Revenue withdrawal for platform
 * 
 * SECURITY FEATURES:
 * - Ownable access control for administrative functions
 * - Reentrancy protection on critical functions
 * - Parameter validation for all token deployments
 * - Emergency controls for existing tokens
 * 
 * ACCESS CONTROL:
 * - Owner: Can update fees, withdraw revenue, manage existing tokens
 * - Users: Can deploy tokens, view information
 * - Tokens: Automatically get factory permissions for callbacks
 */
contract TokenFactory is Ownable, ReentrancyGuard {
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // DATA STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Stores comprehensive information about each deployed token
     * @dev This struct is stored in the tokens array and used for tracking and queries
     * @dev Updated when tokens graduate to reflect new state
     */
    struct TokenInfo {
        /// @notice The deployed token contract address
        address tokenAddress;
        
        /// @notice Human-readable name of the token (e.g., "My Awesome Token")
        string name;
        
        /// @notice Short symbol for the token (e.g., "MAT")
        string symbol;
        
        /// @notice Bonding curve slope parameter (price increase per token in wei)
        uint256 slope;
        
        /// @notice Initial token price in wei (minimum price)
        uint256 basePrice;
        
        /// @notice Market cap threshold in wei that triggers graduation to DEX
        uint256 graduationThreshold;
        
        /// @notice Address of the user who deployed this token
        address creator;
        
        /// @notice Block timestamp when the token was deployed
        uint256 createdAt;
        
        /// @notice Whether the token has graduated to DEX trading
        bool hasGraduated;
        
        /// @notice Address of the Uniswap V2 pair (only set after graduation)
        address dexPair;
    }
    
    /**
     * @notice Statistics struct for factory-wide metrics
     * @dev Used for analytics and monitoring factory performance
     * @dev Currently defined but not fully utilized in all functions
     */
    struct FactoryStats {
        /// @notice Total number of tokens ever deployed by this factory
        uint256 totalTokens;
        
        /// @notice Total number of tokens that have graduated to DEX
        uint256 totalGraduated;
        
        /// @notice Number of active tokens (not graduated yet)
        uint256 totalActiveTokens;
        
        /// @notice Total creation fees collected by the factory
        uint256 totalFeesCollected;
        
        /// @notice Total trading volume across all tokens (not currently tracked)
        uint256 totalVolume;
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // FACTORY CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /// @notice Fee charged for deploying a new token (in wei)
    /// @dev Default is 0.01 ETH, can be updated by owner
    /// @dev This fee goes to the factory owner for platform revenue
    uint256 public creationFee = 0.01 ether;
    
    /// @notice Address of the Uniswap V2 router contract
    /// @dev Used by all tokens for DEX integration during graduation
    /// @dev Can be updated by owner in case of router upgrades
    address public uniswapV2Router;
    
    /// @notice Address that receives all platform fees and trading fees
    /// @dev All tokens created by this factory send fees to this address
    /// @dev Can be updated by owner, affecting both future and existing tokens
    address public platformFeeCollector;
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // DEFAULT FEE STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /// @notice Default percentage of graduation funds allocated to liquidity (basis points)
    /// @dev Applied to all new tokens, typically 8000 (80%)
    /// @dev This ensures most funds go to DEX liquidity for healthy trading
    uint256 public liquidityFee = 8000;
    
    /// @notice Default percentage of graduation funds allocated to token creator (basis points)
    /// @dev Applied to all new tokens, typically 0 (0%)
    /// @dev Can be increased to incentivize high-quality token creation
    uint256 public creatorFee = 0;
    
    /// @notice Default percentage of graduation funds allocated to platform (basis points)
    /// @dev Applied to all new tokens, typically 2000 (20%)
    /// @dev This is the platform's revenue from successful token graduations
    uint256 public platformFee = 2000;
    
    /// @notice Default buy trading fee for new tokens (basis points)
    /// @dev Applied to all new tokens, typically 0 (0% by default)
    /// @dev Can be set to generate immediate revenue from token trading
    uint256 public buyTradingFee = 0;
    
    /// @notice Default sell trading fee for new tokens (basis points)
    /// @dev Applied to all new tokens, typically 0 (0% by default)
    /// @dev Can be set higher than buy fee to discourage selling pressure
    uint256 public sellTradingFee = 0;
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // TOKEN TRACKING AND INDEXING
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /// @notice Array storing information for all deployed tokens
    /// @dev Index in this array corresponds to token creation order
    /// @dev Used for pagination and bulk queries
    TokenInfo[] public tokens;
    
    /// @notice Maps token addresses to their index in the tokens array
    /// @dev Enables O(1) lookup of token information by address
    /// @dev Updated when new tokens are created
    mapping(address => uint256) public tokenIndex;
    
    /// @notice Maps token addresses to boolean indicating if created by this factory
    /// @dev Used for access control and validation
    /// @dev Prevents operations on tokens not created by this factory
    mapping(address => bool) public isTokenCreated;
    
    /// @notice Maps creator addresses to arrays of token indices they created
    /// @dev Enables efficient lookup of all tokens created by a specific user
    /// @dev Used for creator dashboards and analytics
    mapping(address => uint256[]) public creatorTokens;
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // FACTORY STATISTICS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /// @notice Total creation fees collected by the factory
    /// @dev Incremented each time a token is successfully created
    /// @dev Used for revenue tracking and owner withdrawals
    uint256 public totalFeesCollected;
    
    /// @notice Total trading volume across all tokens
    /// @dev Currently not actively updated by token contracts
    /// @dev Reserved for future analytics implementation
    uint256 public totalVolume;
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Emitted when a new bonding curve token is successfully deployed
     * @dev This is the primary event for tracking token creation across the ecosystem
     * @dev Used by frontends, analytics platforms, and indexing services
     * 
     * @param token Address of the newly deployed token contract
     * @param name Human-readable name of the token
     * @param symbol Short symbol identifier for the token
     * @param slope Bonding curve slope parameter (price increase per token)
     * @param basePrice Initial token price in wei
     * @param graduationThreshold Market cap threshold for DEX graduation
     * @param creator Address of the user who deployed the token
     * @param creationFee Amount of ETH paid as creation fee
     */
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
    
    /**
     * @notice Emitted when a token graduates from bonding curve to DEX trading
     * @dev Indicates successful transition to decentralized exchange trading
     * @dev Used to update token status in databases and user interfaces
     * 
     * @param token Address of the token that graduated
     * @param finalSupply Total token supply at the time of graduation
     * @param marketCap Market capitalization that triggered graduation
     * @param dexPair Address of the created Uniswap V2 trading pair
     * @param platformFee Amount of platform fees collected during graduation
     */
    event TokenGraduated(
        address indexed token,
        uint256 finalSupply,
        uint256 marketCap,
        address indexed dexPair,
        uint256 platformFee
    );
    
    /**
     * @notice Emitted when the factory owner updates the token creation fee
     * @dev Important for users to know cost changes for deploying new tokens
     * @param oldFee Previous creation fee amount
     * @param newFee New creation fee amount
     */
    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);
    
    /**
     * @notice Emitted when the factory owner withdraws collected creation fees
     * @dev Used for transparency and accounting of platform revenue
     * @param owner Address that received the withdrawn fees
     * @param amount Amount of ETH withdrawn
     */
    event FeesWithdrawn(address indexed owner, uint256 amount);
    
    /**
     * @notice Emitted when the Uniswap V2 router address is updated
     * @dev Critical event as it affects all future token graduations
     * @param oldRouter Previous router address
     * @param newRouter New router address that will be used for DEX integration
     */
    event RouterUpdated(address indexed oldRouter, address indexed newRouter);
    
    /**
     * @notice Emitted when default graduation fee distribution is updated
     * @dev Affects how graduation fees are split for all future tokens
     * @param liquidityFee New percentage allocated to DEX liquidity
     * @param creatorFee New percentage allocated to token creators
     * @param platformFee New percentage allocated to platform
     */
    event FeeDistributionUpdated(uint256 liquidityFee, uint256 creatorFee, uint256 platformFee);
    
    /**
     * @notice Emitted when the platform fee collector address is updated
     * @dev Critical for fee routing - affects where all fees are sent
     * @param oldCollector Previous fee collector address
     * @param newCollector New address that will receive platform fees
     */
    event PlatformFeeCollectorUpdated(address indexed oldCollector, address indexed newCollector);
    
    /**
     * @notice Emitted when default trading fees are updated
     * @dev Affects buy and sell fees for all future tokens
     * @param buyFee New default buy trading fee in basis points
     * @param sellFee New default sell trading fee in basis points
     */
    event TradingFeesUpdated(uint256 buyFee, uint256 sellFee);
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Validates that a token address is valid and was created by this factory
     * @dev Critical security modifier to prevent operations on unauthorized tokens
     * @dev Used by all functions that interact with specific tokens
     * 
     * @param token The token address to validate
     * 
     * Requirements:
     * - Token address must not be zero address
     * - Token must have been created by this factory (tracked in isTokenCreated)
     * 
     * Security Implications:
     * - Prevents external contracts from masquerading as factory-created tokens
     * - Ensures factory only manages tokens it actually deployed
     * - Protects against accidental operations on wrong contracts
     */
    modifier validTokenAddress(address token) {
        require(token != address(0), "Invalid token address");
        require(isTokenCreated[token], "Token not created by this factory");
        _;
    }
    
    /**
     * @notice Validates bonding curve parameters during token creation
     * @dev Ensures all token deployments meet minimum quality standards
     * @dev Prevents deployment of tokens with invalid or malicious parameters
     * 
     * @param name Token name string
     * @param symbol Token symbol string
     * @param slope Bonding curve slope parameter
     * @param basePrice Initial token price
     * @param graduationThreshold Market cap threshold for graduation
     * 
     * Requirements:
     * - Name must not be empty string
     * - Symbol must not be empty string  
     * - Slope must be greater than 0 (ensures price increases with supply)
     * - Base price must be greater than 0 (ensures tokens have value)
     * - Graduation threshold must be greater than 0 (ensures eventual graduation)
     * 
     * Quality Control:
     * - Prevents deployment of tokens with no name or symbol
     * - Ensures bonding curve mathematics will work correctly
     * - Guarantees tokens can eventually graduate to DEX
     */
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

    // ═══════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Initializes the TokenFactory with required addresses and configuration
     * @dev Sets up the factory with DEX integration and fee collection infrastructure
     * 
     * @param _uniswapV2Router Address of the Uniswap V2 router for DEX integration
     * @param _platformFeeCollector Address that will receive all platform fees
     * @param _owner Address that will become the factory owner with admin privileges
     * 
     * Requirements:
     * - Router address cannot be zero address
     * - Platform fee collector cannot be zero address
     * - Owner is set via Ownable constructor
     * 
     * Initial State:
     * - Creates empty tokens array for tracking deployments
     * - Sets default fee structures (80% liquidity, 0% creator, 20% platform)
     * - Sets default trading fees to 0% for both buy and sell
     * - Sets creation fee to 0.01 ETH
     * 
     * Post-Deployment:
     * - Factory owner can update all fee structures
     * - Users can immediately start deploying tokens
     * - All tokens will use the configured router for graduation
     */
    constructor(address _uniswapV2Router, address _platformFeeCollector, address _owner) Ownable(_owner) {
        // Validate critical addresses
        require(_uniswapV2Router != address(0), "Router cannot be zero address");
        require(_platformFeeCollector != address(0), "Platform fee collector cannot be zero address");
        
        // Initialize DEX integration
        uniswapV2Router = _uniswapV2Router;
        
        // Initialize fee collection
        platformFeeCollector = _platformFeeCollector;
        
        // Note: Default fee values are set in state variable declarations:
        // - liquidityFee = 8000 (80%)
        // - creatorFee = 0 (0%)
        // - platformFee = 2000 (20%)
        // - buyTradingFee = 0 (0%)
        // - sellTradingFee = 0 (0%)
        // - creationFee = 0.01 ether
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // TOKEN CREATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Creates a new bonding curve token with standard graduation threshold
     * @dev Convenient function for users who want to use the default graduation settings
     * @dev Uses fixed graduation threshold of 69 ETH market cap
     * 
     * @param name Human-readable name for the token (e.g., "My Awesome Token")
     * @param symbol Short identifier for the token (e.g., "MAT", recommended 3-5 chars)
     * @param slope Price increase per token in wei (higher = steeper price curve)
     * @param basePrice Starting price for the first token in wei
     * @return tokenAddress Address of the newly deployed token contract
     * 
     * Requirements:
     * - Must send at least the creation fee (0.01 ETH by default)
     * - Name and symbol cannot be empty
     * - Slope and basePrice must be greater than 0
     * - Function has reentrancy protection
     * 
     * Process:
     * 1. Validates parameters and payment
     * 2. Deploys new BondingCurveToken contract
     * 3. Records token information in factory storage
     * 4. Collects creation fee and refunds excess
     * 5. Emits TokenCreated event
     * 
     * Example Usage:
     * ```solidity
     * // Create token with 1000 wei base price, 100 wei slope increase per token
     * address myToken = factory.createToken{value: 0.01 ether}(
     *     "My Token", 
     *     "MTK", 
     *     100, 
     *     1000
     * );
     * ```
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
     * @notice Creates a new bonding curve token with custom graduation threshold
     * @dev Advanced function for users who want to customize when their token graduates
     * @dev Allows setting any graduation threshold above 0
     * 
     * @param name Human-readable name for the token
     * @param symbol Short identifier for the token
     * @param slope Price increase per token in wei
     * @param basePrice Starting price for the first token in wei
     * @param graduationThreshold Custom market cap threshold for DEX graduation in wei
     * @return tokenAddress Address of the newly deployed token contract
     * 
     * Requirements:
     * - Must send at least the creation fee
     * - All parameters must be valid (non-zero, non-empty)
     * - Graduation threshold must be greater than 0
     * - Function has reentrancy protection
     * 
     * Graduation Threshold Considerations:
     * - Lower threshold (1-10 ETH): Quick graduation, less bonding curve trading
     * - Medium threshold (10-50 ETH): Balanced approach
     * - Higher threshold (50+ ETH): Extended bonding curve phase
     * - Very high threshold (100+ ETH): May never graduate if not enough demand
     * 
     * Example Usage:
     * ```solidity
     * // Create token that graduates at 10 ETH market cap
     * address myToken = factory.createTokenWithCustomThreshold{value: 0.01 ether}(
     *     "Custom Token", 
     *     "CTK", 
     *     50, 
     *     500, 
     *     10 ether
     * );
     * ```
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
     * @notice Internal function that handles the actual token deployment and setup
     * @dev Called by both public creation functions after validation
     * @dev Performs all necessary setup and tracking for new tokens
     * 
     * @param name Token name (already validated)
     * @param symbol Token symbol (already validated)  
     * @param slope Bonding curve slope (already validated)
     * @param basePrice Initial token price (already validated)
     * @param graduationThreshold Market cap threshold (already validated)
     * @return tokenAddress Address of the deployed token contract
     * 
     * Process Flow:
     * 1. Validates payment meets creation fee requirement
     * 2. Deploys new BondingCurveToken with factory's current fee settings
     * 3. Records token in factory's tracking systems (arrays and mappings)
     * 4. Updates factory statistics
     * 5. Refunds any excess ETH payment
     * 6. Emits TokenCreated event for monitoring
     * 
     * Token Configuration:
     * - Sets caller as token creator and initial owner
     * - Configures factory as admin for fee updates and graduation triggers
     * - Uses factory's current Uniswap router for DEX integration
     * - Applies factory's current fee structures to the token
     * - Sets platform fee collector for all fee routing
     * 
     * Tracking Updates:
     * - Adds TokenInfo to main tokens array
     * - Maps token address to array index for O(1) lookup
     * - Marks token as factory-created for access control
     * - Adds to creator's token list for user dashboards
     */
    function _createTokenInternal(
        string memory name,
        string memory symbol,
        uint256 slope,
        uint256 basePrice,
        uint256 graduationThreshold
    ) internal returns (address tokenAddress) {
        // Ensure sufficient payment for creation fee
        require(msg.value >= creationFee, "Insufficient creation fee");
        
        // Deploy new bonding curve token with factory's current configuration
        BondingCurveToken newToken = new BondingCurveToken(
            name,                    // Token name
            symbol,                  // Token symbol
            slope,                   // Bonding curve slope
            basePrice,              // Initial token price
            graduationThreshold,    // Market cap for graduation
            msg.sender,             // Token creator (becomes owner)
            address(this),          // Factory address (gets admin permissions)
            uniswapV2Router,       // Uniswap router for DEX integration
            liquidityFee,          // Liquidity fee percentage
            creatorFee,            // Creator fee percentage
            platformFee,           // Platform fee percentage
            platformFeeCollector,  // Address to receive fees
            buyTradingFee,         // Buy trading fee
            sellTradingFee         // Sell trading fee
        );
        
        tokenAddress = address(newToken);
        
        // Create comprehensive token information record
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
            dexPair: address(0)  // Will be set when token graduates
        });
        
        // Update factory's tracking systems
        tokens.push(tokenInfo);                              // Add to main array
        tokenIndex[tokenAddress] = tokens.length - 1;       // Map address to index
        isTokenCreated[tokenAddress] = true;                 // Mark as factory-created
        creatorTokens[msg.sender].push(tokens.length - 1);  // Add to creator's list
        
        // Update factory statistics
        totalFeesCollected += creationFee;
        
        // Refund any excess ETH payment to user
        if (msg.value > creationFee) {
            payable(msg.sender).transfer(msg.value - creationFee);
        }
        
        // Emit creation event for monitoring and indexing
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
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // INFORMATION GETTER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Gets the total number of tokens deployed by this factory
     * @dev Simple counter for tracking factory usage and growth
     * @dev Does not distinguish between graduated and active tokens
     * 
     * @return totalCount Total number of tokens ever created
     * 
     * Usage:
     * - Analytics dashboards to show platform growth
     * - Pagination calculations for token lists  
     * - General factory statistics
     */
    function getTokenCount() external view returns (uint256 totalCount) {
        return tokens.length;
    }
    
    /**
     * @notice Gets all tokens created by a specific address
     * @dev Useful for creator dashboards and portfolio tracking
     * @dev Returns addresses in chronological creation order
     * 
     * @param creator Address of the token creator to query
     * @return tokenAddresses Array of token addresses created by this user
     * 
     * Gas Considerations:
     * - Gas cost increases with number of tokens created by user
     * - Consider implementing pagination for users with many tokens
     * - Frontend should cache results and update incrementally
     * 
     * Usage:
     * - Creator portfolio pages
     * - User token management interfaces
     * - Revenue tracking for individual creators
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
     * @notice Gets comprehensive information about a specific token
     * @dev Returns the complete TokenInfo struct for a given token address
     * @dev Only works for tokens created by this factory
     * 
     * @param token Address of the token to query
     * @return tokenInfo Complete TokenInfo struct with all token details
     * 
     * Requirements:
     * - Token must be a valid address (not zero)
     * - Token must have been created by this factory
     * 
     * Returns:
     * - tokenAddress: The token contract address
     * - name: Human-readable token name
     * - symbol: Short token identifier  
     * - slope: Bonding curve slope parameter
     * - basePrice: Initial token price
     * - graduationThreshold: Market cap needed for graduation
     * - creator: Address that deployed the token
     * - createdAt: Block timestamp of creation
     * - hasGraduated: Whether token has graduated to DEX
     * - dexPair: Uniswap pair address (if graduated)
     * 
     * Usage:
     * - Token detail pages
     * - Analytics and monitoring
     * - Integration with other contracts
     * - Portfolio tracking applications
     */
    function getTokenInfo(address token) external view validTokenAddress(token) returns (TokenInfo memory tokenInfo) {
        uint256 index = tokenIndex[token];
        return tokens[index];
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // FACTORY ADMINISTRATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Updates the fee charged for creating new tokens
     * @dev Only callable by factory owner, affects all future token deployments
     * @dev Existing tokens are not affected by this change
     * 
     * @param newFee New creation fee amount in wei
     * 
     * Requirements:
     * - Caller must be factory owner
     * - New fee must be greater than 0
     * 
     * Considerations:
     * - Higher fees reduce token creation but increase revenue
     * - Lower fees encourage more token creation but reduce revenue per token
     * - Consider market conditions and competitor pricing
     * - Changes affect all future deployments immediately
     * 
     * Emits:
     * - CreationFeeUpdated event with old and new fee amounts
     */
    function updateCreationFee(uint256 newFee) external onlyOwner {
        require(newFee > 0, "Creation fee must be greater than 0");
        uint256 oldFee = creationFee;
        creationFee = newFee;
        
        emit CreationFeeUpdated(oldFee, newFee);
    }
    
    /**
     * @notice Updates default graduation fee distribution for future tokens
     * @dev Only affects tokens created after this update
     * @dev Existing tokens keep their original fee structure
     * 
     * @param _liquidityFee Percentage allocated to DEX liquidity (basis points)
     * @param _creatorFee Percentage allocated to token creators (basis points)
     * @param _platformFee Percentage allocated to platform (basis points)
     * 
     * Requirements:
     * - Caller must be factory owner
     * - All fees must sum to exactly 10000 (100%)
     * - Liquidity fee must be at least 5000 (50%) for healthy DEX trading
     * - Platform fee cannot exceed 3000 (30%) to remain competitive
     * 
     * Economic Considerations:
     * - Higher liquidity fee = better DEX trading experience
     * - Higher creator fee = more incentive for quality token creation  
     * - Higher platform fee = more revenue but may deter creators
     * 
     * Emits:
     * - FeeDistributionUpdated event with new fee percentages
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
     * @notice Gets current default graduation fee distribution
     * @dev Shows the fee structure that will be applied to new tokens
     * @dev Useful for users to understand costs before creating tokens
     * 
     * @return liquidityFeePercent Percentage going to DEX liquidity
     * @return creatorFeePercent Percentage going to token creators
     * @return platformFeePercent Percentage going to platform
     * 
     * Usage:
     * - Frontend display of current fee structure
     * - Token creation calculators
     * - Platform transparency initiatives
     */
    function getFeeDistribution() external view returns (uint256 liquidityFeePercent, uint256 creatorFeePercent, uint256 platformFeePercent) {
        return (liquidityFee, creatorFee, platformFee);
    }
    
    /**
     * @notice Gets current default trading fees for new tokens
     * @dev Shows trading fees that will be applied to new tokens
     * @dev Existing tokens retain their original trading fee settings
     * 
     * @return buyFeePercent Default buy trading fee in basis points
     * @return sellFeePercent Default sell trading fee in basis points
     * 
     * Usage:
     * - User interfaces showing current trading costs
     * - Token creation decision tools
     * - Platform fee transparency
     */
    function getTradingFees() external view returns (uint256 buyFeePercent, uint256 sellFeePercent) {
        return (buyTradingFee, sellTradingFee);
    }
    
    /**
     * @notice Updates the platform fee collector address for future tokens
     * @dev Only affects tokens created after this change
     * @dev Does NOT update existing tokens - use updatePlatformFeeCollectorOnExistingToken for those
     * 
     * @param newPlatformFeeCollector New address to receive platform fees
     * 
     * Requirements:
     * - Caller must be factory owner
     * - New address cannot be zero address
     * 
     * Impact:
     * - All future tokens will send fees to the new address
     * - Existing tokens continue using their original fee collector
     * - Factory creation fees will still go to factory owner
     * 
     * Use Cases:
     * - Upgrading to a more secure fee collection system
     * - Changing from EOA to multisig for better security
     * - Implementing automated fee distribution contracts
     * 
     * Emits:
     * - PlatformFeeCollectorUpdated event
     */
    function updatePlatformFeeCollector(address newPlatformFeeCollector) external onlyOwner {
        require(newPlatformFeeCollector != address(0), "Platform fee collector cannot be zero address");
        address oldCollector = platformFeeCollector;
        platformFeeCollector = newPlatformFeeCollector;
        
        emit PlatformFeeCollectorUpdated(oldCollector, newPlatformFeeCollector);
    }

    /**
     * @notice Updates platform fee collector for a specific existing token
     * @dev Allows updating fee collection for tokens already deployed
     * @dev Only callable by factory owner with admin permissions on tokens
     * 
     * @param token Address of the token to update
     * @param newPlatformFeeCollector New fee collector address for this token
     * 
     * Requirements:
     * - Caller must be factory owner
     * - Token must have been created by this factory
     * - New address cannot be zero address
     
     * Security:
     * - Factory has special admin permissions on all tokens it creates
     * - This allows centralized management of fee collection
     * - Token creators cannot override factory's fee collector changes
     * 
     * Use Cases:
     * - Migrating existing tokens to new fee collection system
     * - Emergency updates to fee collection addresses
     * - Bulk updates when combined with batching logic
     */
    function updatePlatformFeeCollectorOnExistingToken(address token, address newPlatformFeeCollector) external onlyOwner validTokenAddress(token) {
        BondingCurveToken tokenContract = BondingCurveToken(payable(token));
        tokenContract.updatePlatformFeeCollector(newPlatformFeeCollector);
    }
    
    /**
     * @notice Updates default trading fees for future tokens
     * @dev Only affects tokens created after this change
     * @dev Existing tokens retain their original trading fee settings
     * 
     * @param newBuyTradingFee New default buy trading fee in basis points (max 1000)
     * @param newSellTradingFee New default sell trading fee in basis points (max 1000)
     * 
     * Requirements:
     * - Caller must be factory owner
     * - Both fees must be <= 1000 basis points (10%)
     * 
     * Economic Impact:
     * - Higher fees generate more revenue per transaction
     * - Lower fees encourage more trading activity
     * - Different buy/sell fees can influence trading patterns
     * - Zero fees maximize user adoption
     * 
     * Emits:
     * - TradingFeesUpdated event
     */
    function updateTradingFees(uint256 newBuyTradingFee, uint256 newSellTradingFee) external onlyOwner {
        require(newBuyTradingFee <= 1000, "Buy trading fee cannot exceed 10%");
        require(newSellTradingFee <= 1000, "Sell trading fee cannot exceed 10%");
        
        buyTradingFee = newBuyTradingFee;
        sellTradingFee = newSellTradingFee;
        
        emit TradingFeesUpdated(newBuyTradingFee, newSellTradingFee);
    }
    
    /**
     * @notice Updates trading fees for a specific existing token
     * @dev Allows dynamic adjustment of trading fees for already deployed tokens
     * @dev Can be used for promotions, anti-bot measures, or revenue optimization
     * 
     * @param token Address of the token to update
     * @param newBuyTradingFee New buy trading fee for this token (max 1000)
     * @param newSellTradingFee New sell trading fee for this token (max 1000)
     * 
     * Requirements:
     * - Caller must be factory owner
     * - Token must have been created by this factory
     * - Both fees must be <= 1000 basis points (10%)
     * 
     * Use Cases:
     * - Promotional periods with reduced fees
     * - Anti-bot measures with temporarily higher fees
     * - Revenue optimization for successful tokens
     * - Emergency fee adjustments
     */
    function updateTradingFeesOnExistingToken(address token, uint256 newBuyTradingFee, uint256 newSellTradingFee) external onlyOwner validTokenAddress(token) {
        BondingCurveToken tokenContract = BondingCurveToken(payable(token));
        tokenContract.updateTradingFees(newBuyTradingFee, newSellTradingFee);
    }
    
    /**
     * @notice Updates the Uniswap V2 router used for token graduations
     * @dev Affects all future token graduations but not existing graduated tokens
     * @dev Critical function as it determines DEX integration for new graduations
     * 
     * @param newRouter Address of the new Uniswap V2 router contract
     * 
     * Requirements:
     * - Caller must be factory owner
     * - New router address cannot be zero address
     * 
     * Considerations:
     * - Only affects tokens that graduate after this change
     * - Existing graduated tokens continue using their original DEX pairs
     * - Should only be changed for legitimate router upgrades
     * - Test thoroughly before changing in production
     * 
     * Emits:
     * - RouterUpdated event
     */
    function updateRouter(address newRouter) external onlyOwner {
        require(newRouter != address(0), "Router cannot be zero address");
        address oldRouter = uniswapV2Router;
        uniswapV2Router = newRouter;
        
        emit RouterUpdated(oldRouter, newRouter);
    }
    
    /**
     * @notice Withdraws all collected creation fees to the factory owner
     * @dev Reentrancy protected to prevent malicious re-entry attacks
     * @dev Only withdraws creation fees, not trading fees (those go to platform fee collector)
     * 
     * Requirements:
     * - Caller must be factory owner
     * - Contract must have ETH balance to withdraw
     * - Function has reentrancy protection
     * 
     * Process:
     * - Checks current contract balance
     * - Transfers entire balance to factory owner
     * - Emits withdrawal event for transparency
     * 
     * Revenue Sources:
     * - Token creation fees paid by users
     * - Any accidental ETH sent to factory contract
     * - Does NOT include trading fees (sent directly to platform fee collector)
     * 
     * Emits:
     * - FeesWithdrawn event
     */
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        
        payable(owner()).transfer(balance);
        
        emit FeesWithdrawn(owner(), balance);
    }
    
    /**
     * @notice Manually triggers graduation for a token (emergency function)
     * @dev currently in dev mode to test graduations , will be removed later
     * @dev Emergency function to force graduation without reaching market cap threshold
     * @dev Bypasses normal market cap requirement for graduation
     * @dev Should be used sparingly and only for valid reasons
     * 
     * @param token Address of the token to force graduate
     * 
     * Requirements:
     * - Caller must be factory owner
     * - Token must have been created by this factory
     * - Token must not already be graduated
     * 
     * Use Cases:
     * - Emergency situations requiring immediate graduation
     * - Testing purposes in development environments  
     * - Special milestone celebrations
     * - Resolution of technical issues preventing natural graduation
     * 
     * WARNING: This bypasses economic incentives and should be used cautiously
     * 
     * Process:
     * 1. Calls token's triggerGraduation function
     * 2. Updates factory's records of token status
     * 3. Emits TokenGraduated event
     */
    function triggerGraduation(address token) external onlyOwner validTokenAddress(token) {
        BondingCurveToken tokenContract = BondingCurveToken(payable(token));
        tokenContract.triggerGraduation();
        
        // Update token status in factory records
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
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // ETH HANDLING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Receives ETH sent directly to the factory contract
     * @dev Allows the contract to accept ETH from various sources
     * @dev ETH received here can be withdrawn by factory owner via withdrawFees()
     * 
     * Sources of ETH:
     * - Token creation fees (primary source)
     * - Accidental direct transfers
     * - Gas stipend refunds from failed transactions
     * - Donations to the platform
     * 
     * Note: This does NOT create tokens - use createToken() functions for that
     */
    receive() external payable {}
    
    /**
     * @notice Fallback function for handling unexpected calls
     * @dev Called when contract is called with data that doesn't match any function
     * @dev Also accepts ETH to ensure contract doesn't reject unexpected payments
     * 
     * Behavior:
     * - Accepts ETH sent with invalid function calls
     * - Does not execute any logic
     * - Prevents accidental ETH loss from misformed transactions
     * 
     * Security Note:
     * - Does not perform any state changes
     * - Simply accepts ETH if provided
     * - All received ETH can be withdrawn by factory owner
     */
    fallback() external payable {}
}
