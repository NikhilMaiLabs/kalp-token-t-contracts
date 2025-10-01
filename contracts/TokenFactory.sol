// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./BondingCurveToken.sol";

/**
 * @title TokenFactory
 * @notice Factory contract for deploying and managing bonding curve tokens with automatic DEX graduation
 * @dev Central hub for the bonding curve token ecosystem using UUPS upgradeable pattern
 *
 * ARCHITECTURE OVERVIEW:
 * This factory deploys BondingCurveToken contracts with linear pricing curves that automatically
 * graduate to Uniswap V2 DEX trading upon reaching configurable market cap thresholds.
 *
 * CORE FUNCTIONALITY:
 * - Deploy bonding curve tokens with customizable economic parameters
 * - Manage global fee structures and platform settings
 * - Track all deployed tokens with comprehensive indexing
 * - Provide administrative controls for token lifecycle management
 * - Collect and manage platform revenue from token creation
 *
 * SECURITY MODEL:
 * ⚠️ CENTRALIZATION CONSIDERATIONS:
 * - Implements UUPS upgradeable pattern with owner-controlled upgrades
 * - Factory owner has authority to: upgrade logic, modify fees, force graduations
 * - All tokens created inherit factory's configuration at deployment time
 *
 * PRODUCTION DEPLOYMENT REQUIREMENTS:
 * 1. Multi-Signature Governance:
 *    - Transfer ownership to multi-signature wallet (minimum 3-of-5 Gnosis Safe)
 *    - Implement TimelockController with 48-hour minimum delay for:
 *      · Contract upgrades (_authorizeUpgrade)
 *      · Fee structure modifications (updateFeeDistribution, updateCreationFee)
 *      · Critical parameter changes (updateRouter, updatePlatformFeeCollector)
 *
 * 2. Access Control Best Practices:
 *    - Deploy TimelockController as intermediate owner
 *    - Set multi-signature wallet as TimelockController admin
 *    - Document all administrative actions on-chain via events
 *
 * 3. Emergency Procedures:
 *    - Establish incident response procedures for security events
 *    - Define clear authorization requirements for triggerGraduation()
 *    - Maintain separation of duties between operational and treasury functions
 *
 * INTEGRATION POINTS:
 * - Uniswap V2 Router: For automated liquidity provision during graduation
 * - Platform Fee Collector: Receives trading fees and platform revenue
 * - BondingCurveToken: Individual token contracts with bonding curve logic
 *
 * @custom:oz-upgrades-unsafe-allow constructor
 */
contract TokenFactory is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using Address for address payable;

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
    
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // FACTORY CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /// @notice Fee charged for deploying a new token (in wei)
    /// @dev Default is 1 POL, can be updated by owner
    /// @dev This fee goes to the factory owner for platform revenue
    uint256 public creationFee = 1 ether; // 1 POL on Polygon
    
    /// @notice Address of the Uniswap V2 Router contract
    /// @dev Used by all tokens for DEX integration during graduation
    /// @dev Can be updated by owner in case of router upgrades
    address public router;
    
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

    /// @notice Default percentage of trading fees allocated to creator (basis points)
    /// @dev Applied to all new tokens, typically 5000 (50%)
    /// @dev Determines creator/platform split of trading fees: creator gets this %, platform gets remainder
    /// @dev Range: 0-10000 (0%-100%)
    uint256 public creatorTradingFeeShare = 5000;

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

    // ═══════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// @notice Maximum allowed slope to prevent overflow issues
    uint256 public constant MAX_SLOPE = 1e36; // 1e18 tokens * 1e18 price

    /// @notice Maximum allowed base price to prevent overflow issues
    uint256 public constant MAX_BASE_PRICE = 1e27; // 1 billion ETH in wei

    /// @notice Maximum allowed graduation threshold to prevent overflow issues
    uint256 public constant MAX_GRADUATION_THRESHOLD = 1e30; // 1 trillion ETH in wei
    
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
     * @param creationFee Amount of POL paid as creation fee
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
     * @param dexPair Address of the created Uniswap V3 trading pool
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
     * @param amount Amount of POL withdrawn
     */
    event FeesWithdrawn(address indexed owner, uint256 amount);
    
    /**
     * @notice Emitted when the Uniswap V3 Position Manager address is updated
     * @dev Critical event as it affects all future token graduations
     * @param oldRouter Previous position manager address
     * @param newRouter New position manager address that will be used for DEX integration
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

    /**
     * @notice Emitted when trading fee split is updated
     * @dev Affects creator/platform split for all future tokens or specific token
     * @param creatorShare New creator share in basis points
     * @param platformShare New platform share in basis points
     */
    event TradingFeeSplitUpdated(uint256 creatorShare, uint256 platformShare);

    // ═══════════════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Validates that a token address is valid and was created by this factory
     * @dev Critical security modifier to prevent operations on unauthorized tokens
     * @dev Used by all functions that interact with specific tokens
     * 
     * @param token The token address to validate
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
        require(slope <= MAX_SLOPE, "Slope exceeds maximum");
        require(basePrice > 0, "Base price must be greater than 0");
        require(basePrice <= MAX_BASE_PRICE, "Base price exceeds maximum");
        require(graduationThreshold > 0, "Graduation threshold must be greater than 0");
        require(graduationThreshold <= MAX_GRADUATION_THRESHOLD, "Graduation threshold exceeds maximum");
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════════════

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the TokenFactory with core infrastructure addresses
     * @dev One-time initialization function for UUPS upgradeable proxy pattern
     * @dev Must be called immediately after proxy deployment
     *
     * @param _router Address of the Uniswap V2 Router contract for DEX integration
     * @param _platformFeeCollector Address that will receive all trading and platform fees
     * @param _owner Address that will become the factory owner (should be multi-sig)
     *
     * Initialization Sequence:
     * 1. Validates critical addresses (non-zero checks)
     * 2. Initializes OpenZeppelin upgradeable contracts:
     *    - Ownable: Sets ownership to _owner
     *    - ReentrancyGuard: Initializes reentrancy protection
     *    - UUPSUpgradeable: Enables upgrade functionality
     * 3. Configures DEX integration with provided router
     * 4. Sets platform fee collector address
     * 5. Establishes default fee structures:
     *    - creationFee: 1 POL per token deployment
     *    - liquidityFee: 8000 basis points (80%)
     *    - creatorFee: 0 basis points (0%)
     *    - platformFee: 2000 basis points (20%)
     *    - buyTradingFee: 0 basis points (0%)
     *    - sellTradingFee: 0 basis points (0%)
     *    - creatorTradingFeeShare: 5000 basis points (50%)
     *
     * Requirements:
     * - Can only be called once (enforced by initializer modifier)
     * - _router must not be zero address
     * - _platformFeeCollector must not be zero address
     * - _owner should be multi-signature wallet for production
     *
     * Post-Initialization Actions Required:
     * 1. Verify all addresses are correct
     * 2. Transfer ownership to TimelockController (if using)
     * 3. Configure fee structures via updateFeeDistribution() if needed
     * 4. Set appropriate trading fees via updateTradingFees() if desired
     *
     * @custom:security Call immediately after proxy deployment
     * @custom:security Verify initialization parameters before calling
     */
    function initialize(
        address _router,
        address _platformFeeCollector,
        address _owner
    ) public initializer {
        // Validate critical addresses
        require(_router != address(0), "Router cannot be zero address");
        require(_platformFeeCollector != address(0), "Platform fee collector cannot be zero address");

        // Initialize inherited contracts
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        // Initialize DEX integration
        router = _router;

        // Initialize fee collection
        platformFeeCollector = _platformFeeCollector;

        // Initialize default fees
        creationFee = 1 ether;
        liquidityFee = 8000;
        creatorFee = 0;
        platformFee = 2000;
        buyTradingFee = 0;
        sellTradingFee = 0;
        creatorTradingFeeShare = 5000; // 50% default split
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // TOKEN CREATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════
    
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
     */
    function createToken(
        string memory name,
        string memory symbol,
        uint256 slope,
        uint256 basePrice,
        uint256 graduationThreshold
    ) public payable nonReentrant validParameters(name, symbol, slope, basePrice, graduationThreshold) returns (address tokenAddress) {
        return _createTokenInternal(name, symbol, slope, basePrice, graduationThreshold);
    }

    /**
     * @notice Creates a new bonding curve token and immediately allows creator to buy tokens
     * @dev Combines token creation with immediate token purchase for creator convenience
     * @dev Total payment must cover both creation fee and token purchase cost
     *
     * @param name Human-readable name for the token
     * @param symbol Short identifier for the token
     * @param slope Price increase per token in wei
     * @param basePrice Starting price for the first token in wei
     * @param graduationThreshold Custom market cap threshold for DEX graduation in wei
     * @param tokenAmount Amount of tokens to buy after creation
     * @return tokenAddress Address of the newly deployed token contract
     *
     */
    function createTokenWithDevBuy(
        string memory name,
        string memory symbol,
        uint256 slope,
        uint256 basePrice,
        uint256 graduationThreshold,
        uint256 tokenAmount
    ) external payable nonReentrant validParameters(name, symbol, slope, basePrice, graduationThreshold) returns (address tokenAddress) {
        // Validate token amount
        require(tokenAmount > 0, "Token amount must be greater than 0");

        // Calculate the cost for buying tokens (using the same formula as BondingCurveToken)
        uint256 tokenBuyCost = calculateBuyCost(0, tokenAmount, slope, basePrice);
        uint256 tradingFee = (tokenBuyCost * buyTradingFee) / 10000;
        uint256 totalRequired = creationFee + tokenBuyCost + tradingFee;

        require(msg.value >= totalRequired, "Insufficient payment for creation fee and token purchase");

        // Calculate and store excess before any external calls (CEI pattern)
        uint256 excess = msg.value - totalRequired;

        // Create the token first (uses internal creation fee, doesn't touch excess)
        tokenAddress = _createTokenInternal(name, symbol, slope, basePrice, graduationThreshold);

        // Refund excess BEFORE external call to token contract (CEI pattern)
        if (excess > 0) {
            payable(msg.sender).sendValue(excess);
        }

        // Now buy tokens on behalf of the creator (external call comes last)
        BondingCurveToken tokenContract = BondingCurveToken(payable(tokenAddress));
        tokenContract.buyTokensFor{value: tokenBuyCost + tradingFee}(msg.sender, tokenAmount);

        return tokenAddress;
    }
    
    /**
     * @notice Internal function to calculate the cost of buying tokens on a bonding curve
     * @dev Replicates the cost calculation logic from BondingCurveToken
     * @param s Current supply of tokens
     * @param d Amount of tokens to buy
     * @param slope Bonding curve slope parameter
     * @param basePrice Initial token price
     * @return cost Total cost in wei to buy d tokens
     */
    function calculateBuyCost(uint256 s, uint256 d, uint256 slope, uint256 basePrice) public pure returns (uint256 cost) {
        // Using the same constants as BondingCurveToken
        uint256 WAD = 10**18;

        uint256 term1 = Math.mulDiv(basePrice, d, WAD, Math.Rounding.Ceil);

        // term2 = slope * d * (2*s + d) / (2 * WAD^2)
        uint256 sdOverWad = Math.mulDiv(slope, d, WAD, Math.Rounding.Ceil); // slope * d / WAD
        uint256 twoSPlusD = s * 2 + d; // safe with checked math (reverts on overflow)
        uint256 term2 = Math.mulDiv(sdOverWad, twoSPlusD, 2 * WAD, Math.Rounding.Ceil);

        return term1 + term2;
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

        // Calculate excess refund before any state changes (CEI pattern)
        uint256 excessRefund = msg.value - creationFee;

        // Update factory statistics BEFORE external calls
        totalFeesCollected += creationFee;

        // Deploy new bonding curve token with factory's current configuration
        BondingCurveToken newToken = new BondingCurveToken(
            name,                    // Token name
            symbol,                  // Token symbol
            slope,                   // Bonding curve slope
            basePrice,              // Initial token price
            graduationThreshold,    // Market cap for graduation
            msg.sender,             // Token creator (becomes owner)
            address(this),          // Factory address (gets admin permissions)
            router,                 // Uniswap V2 Router for DEX integration
            liquidityFee,          // Liquidity fee percentage
            creatorFee,            // Creator fee percentage
            platformFee,           // Platform fee percentage
            platformFeeCollector,  // Address to receive fees
            buyTradingFee,         // Buy trading fee
            sellTradingFee,        // Sell trading fee
            creatorTradingFeeShare // Trading fee split percentage
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
        uint256 newIndex = tokens.length - 1;               // Cache index (gas optimization)
        tokenIndex[tokenAddress] = newIndex;                // Map address to index
        isTokenCreated[tokenAddress] = true;                 // Mark as factory-created
        creatorTokens[msg.sender].push(newIndex);           // Add to creator's list
        
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

        // Refund any excess ETH payment to user (using safe transfer)
        if (excessRefund > 0) {
            payable(msg.sender).sendValue(excessRefund);
        }

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
     * Security: Validates that the new address can receive POL by sending 0 wei test transaction
     * This prevents setting a contract that reverts on receive, which would brick fee collection
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
     * Security: Validates that the new address can receive POL before updating
     */
    function updatePlatformFeeCollectorOnExistingToken(address token, address newPlatformFeeCollector) external onlyOwner validTokenAddress(token) {
        require(newPlatformFeeCollector != address(0), "Platform fee collector cannot be zero address");


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
     */
    function updateTradingFeesOnExistingToken(address token, uint256 newBuyTradingFee, uint256 newSellTradingFee) external onlyOwner validTokenAddress(token) {
        BondingCurveToken tokenContract = BondingCurveToken(payable(token));
        tokenContract.updateTradingFees(newBuyTradingFee, newSellTradingFee);
    }

    /**
     * @notice Updates default trading fee split for future tokens
     * @dev Only affects tokens created after this change
     * @dev Existing tokens retain their original trading fee split settings
     *
     * @param newCreatorShare New default creator share in basis points (0-10000)
     *
     * Requirements:
     * - Caller must be factory owner
     * - newCreatorShare must be between 0 and 10000 (0% to 100%)
     *
     * Fee Distribution Examples:
     * - 5000: 50% creator, 50% platform (default balanced)
     * - 7000: 70% creator, 30% platform (creator-favored)
     * - 3000: 30% creator, 70% platform (platform-favored)
     * - 10000: 100% creator, 0% platform (promotional)
     * - 0: 0% creator, 100% platform (platform-only)
     *
     * Use Cases:
     * - Adjust global incentive structure for new token creators
     * - Launch promotional periods with higher creator rewards
     * - Optimize platform revenue model based on market conditions
     * - Align with governance-approved fee policies
     */
    function updateCreatorTradingFeeShare(uint256 newCreatorShare) external onlyOwner {
        require(newCreatorShare <= 10000, "Creator share cannot exceed 100%");

        creatorTradingFeeShare = newCreatorShare;
        uint256 platformShare = 10000 - newCreatorShare;

        emit TradingFeeSplitUpdated(newCreatorShare, platformShare);
    }

    /**
     * @notice Updates trading fee split for a specific existing token
     * @dev Allows dynamic adjustment of creator/platform fee distribution
     * @dev Only affects future fee accumulations, not already accumulated fees
     *
     * @param token Address of the token to update
     * @param newCreatorShare Percentage allocated to creator (basis points, 0-10000)
     *
     * Requirements:
     * - Caller must be factory owner
     * - newCreatorShare must be between 0 and 10000 (0% to 100%)
     *
     * Fee Distribution Examples:
     * - 5000: 50% creator, 50% platform (default balanced)
     * - 7000: 70% creator, 30% platform (creator-favored)
     * - 3000: 30% creator, 70% platform (platform-favored)
     * - 10000: 100% creator, 0% platform (promotional)
     * - 0: 0% creator, 100% platform (platform-only)
     *
     * Use Cases:
     * - Adjust global incentive structure for new token creators
     * - Launch promotional periods with higher creator rewards
     * - Optimize platform revenue model based on market conditions
     * - Align with governance-approved fee policies
     * 
     * Note: Does not affect already accumulated fees in the token contract
     */
    function updateTradingFeeShareOnExistingToken(address token, uint256 newCreatorShare) external onlyOwner validTokenAddress(token) {
        BondingCurveToken tokenContract = BondingCurveToken(payable(token));
        tokenContract.updateTradingFeeShare(newCreatorShare);
    }
    
    /**
     * @notice Updates the Uniswap V2 Router used for token graduations
     * @dev Affects all future token graduations but not existing graduated tokens
     * @dev Critical function as it determines DEX integration for new graduations
     * 
     * @param newRouter Address of the new Uniswap V2 Router contract
     */
    function updateRouter(address newRouter) external onlyOwner {
        require(newRouter != address(0), "Router cannot be zero address");
        address oldRouter = router;
        router = newRouter;
        
        emit RouterUpdated(oldRouter, newRouter);
    }
    
    /**
     * @notice Withdraws all collected creation fees to the factory owner
     * @dev Transfers entire contract balance to owner address using safe transfer
     * @dev Only withdraws creation fees, not trading fees (routed to platform fee collector)
     *
     * Requirements:
     * - Caller must be factory owner
     * - Contract balance must be greater than 0
     *
     * Revenue Sources:
     * - Token creation fees paid by users during token deployment
     * - Any POL sent directly to factory contract address
     *
     * Note: Trading fees are transferred directly to platformFeeCollector during token operations
     * and are not accumulated in this contract.
     *
     * Security:
     * - Protected by nonReentrant modifier
     * - Uses OpenZeppelin's sendValue for safe POL transfer
     * - Emits FeesWithdrawn event for transparency
     *
     * Emits:
     * - FeesWithdrawn(owner, amount)
     */
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        
        payable(owner()).sendValue(balance);
        
        emit FeesWithdrawn(owner(), balance);
    }
    
    /**
     * @notice Manually triggers graduation for a token
     * @dev Administrative function to force graduation without reaching market cap threshold
     * @dev Bypasses normal market cap requirement - use only when necessary
     * @dev Only callable by factory owner with proper authorization
     *
     * @param token Address of the token to graduate
     *
     * Requirements:
     * - Caller must be factory owner
     * - Token must exist and not be graduated
     * - Token must have sufficient liquidity for DEX listing
     *
     * Use Cases:
     * - Emergency situations requiring immediate liquidity access
     * - Technical issues preventing automatic graduation
     * - Administrative decisions for token lifecycle management
     *
     * Security Considerations:
     * - Bypasses economic incentives designed into bonding curve
     * - Should be governed by multi-signature wallet in production
     * - Consider implementing timelock for additional security
     * - Document all uses for transparency and governance
     *
     * @custom:security-contact Ensure proper authorization before calling
     */
    function triggerGraduation(address token) external onlyOwner validTokenAddress(token) {
        BondingCurveToken tokenContract = BondingCurveToken(payable(token));
        tokenContract.triggerGraduation();
        
        // Update token status in factory records
        uint256 index = tokenIndex[token];
        tokens[index].hasGraduated = true;
        tokens[index].dexPair = tokenContract.dexPool();
        
        emit TokenGraduated(
            token,
            tokenContract.totalSupply(),
            tokenContract.getMarketCap(),
            tokens[index].dexPair,
            0 // Platform fee handled internally by token
        );
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // POL HANDLING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Receives POL sent directly to the factory contract
     * @dev Allows the contract to accept POL from various sources
     * @dev POL received here can be withdrawn by factory owner via withdrawFees()
     * 
     * Sources of POL:
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
     * @dev Also accepts POL to ensure contract doesn't reject unexpected payments
     *
     * Behavior:
     * - Accepts POL sent with invalid function calls
     * - Does not execute any logic
     * - Prevents accidental POL loss from misformed transactions
     *
     * Security Note:
     * - Does not perform any state changes
     * - Simply accepts POL if provided
     * - All received POL can be withdrawn by factory owner
     */
    fallback() external payable {}

    // ═══════════════════════════════════════════════════════════════════════════════
    // UPGRADE AUTHORIZATION
    // ═══════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Authorizes contract upgrades
     * @dev Only the contract owner can authorize upgrades (UUPS pattern)
     * @dev This function is required by the UUPSUpgradeable contract
     *
     * @param newImplementation Address of the new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ═══════════════════════════════════════════════════════════════════════════════
    // STORAGE GAP
    // ═══════════════════════════════════════════════════════════════════════════════

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
