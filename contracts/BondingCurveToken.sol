// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./utils/Blacklist.sol";

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    
    function getAmountsOut(uint amountIn, address[] calldata path)
        external view returns (uint[] memory amounts);
}

/**
 * @title BondingCurveToken
 * @author Kalp Team
 * @notice A bonding curve token that uses linear pricing and graduates to native POL trading on Uniswap V2
 * @dev This contract implements an ERC20 token with the following features:
 * 
 * BONDING CURVE MECHANICS:
 * - Uses linear bonding curve: price = basePrice + slope * totalSupply
 * - Users buy/sell with native POL directly - no wrapping needed
 * - Price increases linearly with each token minted
 * - All POL raised is held in the contract until graduation
 * 
 * GRADUATION SYSTEM:
 * - Token "graduates" when market cap reaches the graduation threshold
 * - Creates a myToken/POL trading pair on Uniswap V2
 * - Uses standard V2 liquidity pools with automatic market making
 * - After graduation, users trade myToken/POL through the V2 AMM
 * - Simpler and more gas-efficient than V3 concentrated liquidity
 */
contract BondingCurveToken is ERC20, Ownable, ReentrancyGuard, Pausable, BlackList {
    using Address for address payable;
    
    // Fixed-point scale (same as ERC20 decimals)
    uint256 public constant WAD = 1e18;
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // BONDING CURVE PARAMETERS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /// @notice The slope of the linear bonding curve (price increase per token in wei)
    /// @dev Used in formula: price = basePrice + slope * totalSupply
    /// @dev Higher slope means steeper price increases
    uint256 public slope;
    
    /// @notice The starting price for the first token (in wei)
    /// @dev This is the minimum price a token can ever have
    uint256 public basePrice;
    
    /// @notice The market cap threshold that triggers graduation to DEX (in wei)
    /// @dev When getMarketCap() >= graduationThreshold, the token graduates
    /// @dev Market cap = totalSupply * getCurrentPrice()
    uint256 public graduationThreshold;
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // TOKEN STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /// @notice Whether the token has graduated to DEX trading
    /// @dev Once true, buy/sell functions are disabled and only DEX trading is available
    bool public hasGraduated;
    
    /// @notice The Uniswap V3 pool address created during graduation
    /// @dev Only set after graduation, used for DEX trading
    address public dexPool;
    
    /// @notice The address of the token creator
    /// @dev Also serves as the initial owner of the contract
    address public creator;
    
    /// @notice Total POL raised from token sales (excluding trading fees)
    /// @dev Used for graduation fee calculations and liquidity provision
    uint256 public totalRaised;
    
    /// @notice The factory contract that deployed this token
    /// @dev Has special permissions to update fees and trigger graduation
    address public factory;
    
    /// @notice Address that receives all trading fees and platform fees
    /// @dev Can be updated by the factory contract
    address public platformFeeCollector;
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // DEX INTEGRATION
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /// @notice The Uniswap V2 Router contract used for liquidity provision
    /// @dev Set during deployment and cannot be changed
    IUniswapV2Router02 public immutable router;
    
    /// @notice The Uniswap V2 factory contract
    /// @dev Used for creating new pairs during graduation
    IUniswapV2Factory public immutable uniswapV2Factory;
    
    /// @notice The amount of liquidity tokens received when adding liquidity
    /// @dev Only set after graduation, represents the V2 LP tokens owned by this contract
    uint256 public liquidityTokensAmount;
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // FEE CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /// @notice Percentage of graduation fees allocated to liquidity (in basis points)
    /// @dev Applied only during graduation, typically 8000 (80%)
    /// @dev These fees come from totalRaised POL
    uint256 public immutable LIQUIDITY_FEE;
    
    /// @notice Percentage of graduation fees allocated to token creator (in basis points)
    /// @dev Applied only during graduation, typically 0 (0%)
    /// @dev These fees come from totalRaised POL
    uint256 public immutable CREATOR_FEE;
    
    /// @notice Percentage of graduation fees allocated to platform (in basis points)
    /// @dev Applied only during graduation, typically 2000 (20%)
    /// @dev These fees come from totalRaised POL
    uint256 public immutable PLATFORM_FEE;
    
    /// @notice Trading fee applied to buy operations (in basis points)
    /// @dev Applied on every buyTokens() call, max 1000 (10%)
    /// @dev Fee is calculated as: (cost * buyTradingFee) / 10000
    uint256 public buyTradingFee;
    
    /// @notice Trading fee applied to sell operations (in basis points)
    /// @dev Applied on every sellTokens() call, max 1000 (10%)
    /// @dev Fee is calculated as: (refund * sellTradingFee) / 10000
    uint256 public sellTradingFee;
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /// @notice Emitted when tokens are purchased via the bonding curve
    /// @param buyer Address that purchased the tokens
    /// @param amount Number of tokens purchased
    /// @param cost Total POL cost (excluding trading fees)
    /// @param newSupply New total supply after the purchase
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 cost, uint256 newSupply);
    
    /// @notice Emitted when tokens are sold back to the bonding curve
    /// @param seller Address that sold the tokens
    /// @param amount Number of tokens sold
    /// @param refund Total POL refund (excluding trading fees)
    /// @param newSupply New total supply after the sale
    event TokensSold(address indexed seller, uint256 amount, uint256 refund, uint256 newSupply);
    
    /// @notice Emitted when the token graduates to DEX trading
    /// @param supply Total token supply at graduation
    /// @param marketCap Market cap that triggered graduation
    /// @param dexPair Address of the created Uniswap V2 pair
    /// @param liquidityAmount Amount of liquidity tokens received
    event GraduationTriggered(uint256 supply, uint256 marketCap, address dexPair, uint256 liquidityAmount);
    
    /// @notice Emitted when liquidity is added to Uniswap V2 during graduation
    /// @param tokenAmount Number of tokens added to liquidity
    /// @param polAmount Amount of POL added to liquidity
    /// @param liquidityTokens Amount of liquidity tokens received
    event LiquidityAdded(uint256 tokenAmount, uint256 polAmount, uint256 liquidityTokens);
    
    /// @notice Emitted when trading fees are updated by the factory
    /// @param buyFee New buy trading fee in basis points
    /// @param sellFee New sell trading fee in basis points
    event TradingFeesUpdated(uint256 buyFee, uint256 sellFee);
    
    /// @notice Emitted when the instantaneous price has changed due to supply update
    event PriceUpdated(uint256 newPrice, uint256 newSupply);
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    error ZeroAmount();
    error InsufficientPayment(uint256 required, uint256 sent);
    error SlippageExceeded(uint256 quoted, uint256 limit);
    error ProceedsBelowMin(uint256 quoted, uint256 minOut);
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /// @notice Restricts access to factory contract only
    /// @dev Used for administrative functions like fee updates and graduation
    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory can call this function");
        _;
    }
    
    /// @notice Restricts access to functions that should only work before graduation
    /// @dev Used for buy/sell functions that become unavailable after DEX listing
    modifier notGraduated() {
        require(!hasGraduated, "Token has already graduated");
        _;
    }
    
    /// @notice Restricts access to functions that should only work after graduation
    /// @dev Currently not used but available for future features
    modifier onlyGraduated() {
        require(hasGraduated, "Token has not graduated yet");
        _;
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Initializes a new bonding curve token
     * @dev This constructor sets up all the bonding curve parameters and fee structures
     * 
     * @param name The name of the ERC20 token (e.g., "My Token")
     * @param symbol The symbol of the ERC20 token (e.g., "MTK")
     * @param _slope The price increase per token in wei (affects price steepness)
     * @param _basePrice The starting price of the first token in wei
     * @param _graduationThreshold The market cap in wei that triggers graduation to DEX
     * @param _creator The address of the token creator (becomes owner)
     * @param _factory The address of the factory contract (gets admin permissions)
     * @param _router The address of the Uniswap V2 Router for DEX integration
     * @param _liquidityFee Percentage of graduation fees for liquidity (basis points)
     * @param _creatorFee Percentage of graduation fees for creator (basis points)
     * @param _platformFee Percentage of graduation fees for platform (basis points)
     * @param _platformFeeCollector Address that receives trading and platform fees
     * @param _buyTradingFee Trading fee for buy operations (basis points, max 1000)
     * @param _sellTradingFee Trading fee for sell operations (basis points, max 1000)
     * 
     * Requirements:
     * - All fee percentages must sum to exactly 10000 (100%)
     * - Trading fees cannot exceed 1000 (10%)
     * - All addresses must be non-zero
     * - All curve parameters must be greater than 0
     */
    constructor(
        string memory name,
        string memory symbol,
        uint256 _slope,
        uint256 _basePrice,
        uint256 _graduationThreshold,
        address _creator,
        address _factory,
        address _router,
        uint256 _liquidityFee,
        uint256 _creatorFee,
        uint256 _platformFee,
        address _platformFeeCollector,
        uint256 _buyTradingFee,
        uint256 _sellTradingFee
    ) ERC20(name, symbol) Ownable(_creator) {
        // Validate bonding curve parameters
        require(_slope > 0, "Slope must be greater than 0");
        require(_basePrice > 0, "Base price must be greater than 0");
        require(_graduationThreshold > 0, "Graduation threshold must be greater than 0");
        
        // Validate addresses
        require(_creator != address(0), "Creator cannot be zero address");
        require(_factory != address(0), "Factory cannot be zero address");
        require(_router != address(0), "Router cannot be zero address");
        require(_platformFeeCollector != address(0), "Platform fee collector cannot be zero address");
        
        // Validate fee structures
        require(_liquidityFee + _creatorFee + _platformFee == 10000, "Fees must sum to 10000 (100%)");
        require(_buyTradingFee <= 1000, "Buy trading fee cannot exceed 10%");
        require(_sellTradingFee <= 1000, "Sell trading fee cannot exceed 10%");
        
        // Initialize bonding curve parameters
        slope = _slope;
        basePrice = _basePrice;
        graduationThreshold = _graduationThreshold;
        
        // Set addresses
        creator = _creator;
        factory = _factory;
        platformFeeCollector = _platformFeeCollector;
        
        // Set immutable graduation fee percentages (cannot be changed later)
        LIQUIDITY_FEE = _liquidityFee;
        CREATOR_FEE = _creatorFee;
        PLATFORM_FEE = _platformFee;
        
        // Set trading fees (can be updated by factory later)
        buyTradingFee = _buyTradingFee;
        sellTradingFee = _sellTradingFee;
        
        // Initialize DEX integration with Uniswap V2 on Polygon
        router = IUniswapV2Router02(_router);
        uniswapV2Factory = IUniswapV2Factory(router.factory());
        
        // Transfer ownership to creator (they can pause, manage blacklist, etc.)
        _transferOwnership(_creator);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // BONDING CURVE PRICING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Gets the current price per token based on total supply
     * @dev Uses linear bonding curve formula: price = basePrice + slope * totalSupply / WAD
     * @dev This is the instantaneous price for the next token to be minted
     * 
     * @return currentPrice The current price per token in wei
     * 
     * Example:
     * - basePrice = 1000 wei, slope = 100e18, totalSupply = 50e18
     * - currentPrice = 1000 + (100e18 * 50e18) / 1e18 = 1000 + 100 * 50 = 6000 wei
     */
    function getCurrentPrice() public view returns (uint256 currentPrice) {
        uint256 s = totalSupply();
        // Round down for display/consistency; buys round up cost separately
        return basePrice + Math.mulDiv(slope, s, WAD, Math.Rounding.Floor);
    }
    
    /**
     * @notice Calculates the total cost to buy a specific amount of tokens
     * @dev Uses exact integral pricing with WAD math for precision
     * @dev Formula: cost = (p0 * d)/WAD + slope * d * (2*s + d) / (2 * WAD^2), rounded up
     * 
     * @param amount Number of tokens to buy (must be > 0), (18 decimals)
     * @return totalCost Total cost in wei (excluding trading fees)
     */
    function getBuyPrice(uint256 amount) public view returns (uint256 totalCost) {
        if (amount == 0) return 0;
        return _buyCost(totalSupply(), amount);
    }
    
    /**
     * @notice Calculates the total refund for selling a specific amount of tokens
     * @dev Uses exact integral pricing with WAD math for precision
     * @dev Formula: proceeds = (p0 * d)/WAD + slope * d * (2*s - d) / (2 * WAD^2), rounded down
     * 
     * @param amount Number of tokens to sell (must be > 0 and <= totalSupply)
     * @return totalRefund Total refund in wei (before trading fees)
     */
    function getSellPrice(uint256 amount) public view returns (uint256 totalRefund) {
        if (amount == 0) return 0;
        require(amount <= totalSupply(), "Cannot sell more than total supply");
        return _sellProceeds(totalSupply(), amount);
    }
    
    // ========= Internal math =========
    
    /// @dev Price at supply `s` with rounding down
    function _priceAtSupply(uint256 s) internal view returns (uint256) {
        return basePrice + Math.mulDiv(slope, s, WAD, Math.Rounding.Floor);
    }
    
    /// @dev Cost to buy `d` when current supply is `s`
    /// cost = (p0 * d)/WAD + slope * d * (2*s + d) / (2 * WAD^2), rounded up
    function _buyCost(uint256 s, uint256 d) internal view returns (uint256) {
        // term1 = (p0 * d)/WAD
        uint256 term1 = Math.mulDiv(basePrice, d, WAD, Math.Rounding.Ceil);
        
        // term2 = slope * d * (2*s + d) / (2 * WAD^2)
        uint256 sdOverWad = Math.mulDiv(slope, d, WAD, Math.Rounding.Ceil); // slope * d / WAD
        uint256 twoSPlusD = s * 2 + d; // safe with checked math (reverts on overflow)
        uint256 term2 = Math.mulDiv(sdOverWad, twoSPlusD, 2 * WAD, Math.Rounding.Ceil);
        
        return term1 + term2;
    }
    
    /// @dev Proceeds from selling `d` when current supply is `s`
    /// proceeds = (p0 * d)/WAD + slope * d * (2*s - d) / (2 * WAD^2), rounded down
    function _sellProceeds(uint256 s, uint256 d) internal view returns (uint256) {
        // term1 = (p0 * d)/WAD
        uint256 term1 = Math.mulDiv(basePrice, d, WAD, Math.Rounding.Floor);
        
        // term2 = slope * d * (2*s - d) / (2 * WAD^2)
        uint256 sdOverWad = Math.mulDiv(slope, d, WAD, Math.Rounding.Floor); // slope * d / WAD
        uint256 twoSMinusD = s * 2 - d; // requires d <= 2*s; always true if d <= s
        uint256 term2 = Math.mulDiv(sdOverWad, twoSMinusD, 2 * WAD, Math.Rounding.Floor);
        
        return term1 + term2;
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // MARKET CAP AND GRADUATION TRACKING
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Calculates the current market cap of the token
     * @dev Market cap = totalSupply * getCurrentPrice()
     * @dev This determines when the token is ready for graduation
     * 
     * @return marketCap Current market cap in wei
     * 
     * Example:
     * - totalSupply = 1000 tokens, currentPrice = 5000 wei
     * - marketCap = 1000 * 5000 = 5,000,000 wei
     */
    function getMarketCap() public view returns (uint256 marketCap) {
        uint256 supply = totalSupply();
        uint256 price = getCurrentPrice();
        
        // Check for overflow before multiplication
        if (supply > 0 && price > type(uint256).max / supply) {
            revert("Market cap calculation would overflow");
        }
        
        return supply * price;
    }
    
    /**
     * @notice Gets the graduation progress and remaining amount needed
     * @dev Returns progress as basis points (10000 = 100%) and remaining wei needed
     * @dev Used by frontends to show progress bars and graduation status
     * 
     * @return progress Progress percentage in basis points (0-10000)
     * @return remaining Remaining market cap needed for graduation in wei
     * 
     * Example:
     * - currentMarketCap = 3,000,000 wei, graduationThreshold = 10,000,000 wei
     * - progress = (3,000,000 * 10000) / 10,000,000 = 3000 (30%)
     * - remaining = 10,000,000 - 3,000,000 = 7,000,000 wei
     */
    function getGraduationProgress() public view returns (uint256 progress, uint256 remaining) {
        uint256 currentMarketCap = getMarketCap();
        
        // If already at or above threshold, return 100% complete
        if (currentMarketCap >= graduationThreshold) {
            return (10000, 0); // 100% complete, no remaining amount
        }
        
        // Calculate remaining amount needed for graduation
        remaining = graduationThreshold - currentMarketCap;
        
        // Calculate progress as basis points (10000 = 100%)
        progress = (currentMarketCap * 10000) / graduationThreshold;
        
        return (progress, remaining);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // TOKEN TRADING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Buy exactly `amount` tokens
     * @dev This function handles the complete buy process including trading fees
     * @dev Only available before graduation - after graduation, use DEX
     * 
     * @param amount Token amount (18 decimals)
     * 
     * Requirements:
     * - Token must not be graduated yet
     * - Contract must not be paused
     * - Amount must be greater than 0
     * - Must send enough POL to cover cost + trading fee
     * 
     * Emits:
     * - TokensPurchased event with purchase details
     * - PriceUpdated event with new price and supply
     * - Potentially GraduationTriggered if threshold is reached
     */
    function buyTokens(uint256 amount) external payable nonReentrant whenNotPaused notGraduated {
        if (amount == 0) revert ZeroAmount();
        
        uint256 s = totalSupply();
        uint256 cost = _buyCost(s, amount); // rounds up
        
        // Calculate trading fee on the base cost
        uint256 tradingFee = (cost * buyTradingFee) / 10000;
        
        // Total cost including trading fee
        uint256 totalCost = cost + tradingFee;
        
        // Ensure user sent enough POL for total cost
        if (msg.value < totalCost) revert InsufficientPayment(totalCost, msg.value);
        
        // Mint tokens to the buyer
        _mint(msg.sender, amount);
        
        // Update totalRaised with only the bonding curve cost
        // (Trading fees don't count towards graduation calculations)
        totalRaised += cost;
        
        // Transfer trading fee directly to platform fee collector
        if (tradingFee > 0) {
            payable(platformFeeCollector).transfer(tradingFee);
        }
        
        // Emit events for tracking
        emit TokensPurchased(msg.sender, amount, cost, s + amount);
        emit PriceUpdated(_priceAtSupply(s + amount), s + amount);
        
        // Refund any excess POL sent by the user
        uint256 refund = msg.value - totalCost;
        if (refund > 0) payable(msg.sender).sendValue(refund);
        
        // Check if the purchase triggers graduation to DEX
        _checkGraduation();
    }
    
    /**
     * @notice Sell exactly `amount` tokens, reverting if proceeds fall below `minProceeds`
     * @dev This function handles the complete sell process including trading fees
     * @dev Only available before graduation - after graduation, use DEX
     * 
     * @param amount Token amount (18 decimals)
     * @param minProceeds Minimum acceptable POL proceeds to protect against slippage
     * 
     * Requirements:
     * - Token must not be graduated yet
     * - Contract must not be paused
     * - Amount must be greater than 0
     * - Seller must have enough token balance
     * - Contract must have enough POL balance for refund
     * 
     * Emits:
     * - TokensSold event with sale details
     * - PriceUpdated event with new price and supply
     */
    function sellTokens(uint256 amount, uint256 minProceeds) external nonReentrant whenNotPaused notGraduated {
        if (amount == 0) revert ZeroAmount();
        require(balanceOf(msg.sender) >= amount, "Insufficient token balance");
        
        uint256 s = totalSupply();
        uint256 proceeds = _sellProceeds(s, amount); // rounds down
        if (proceeds < minProceeds) revert ProceedsBelowMin(proceeds, minProceeds);
        
        // Calculate trading fee on the proceeds amount
        uint256 tradingFee = (proceeds * sellTradingFee) / 10000;
        
        // Net proceeds to seller after trading fee deduction
        uint256 netProceeds = proceeds - tradingFee;
        
        // Ensure contract has enough POL for the full proceeds
        require(address(this).balance >= proceeds, "Insufficient contract balance");
        
        // Burn tokens from the seller (reduces total supply)
        _burn(msg.sender, amount);
        
        // Update totalRaised by the full proceeds amount
        // (This maintains bonding curve integrity)
        totalRaised -= proceeds;
        
        // Transfer trading fee to platform fee collector
        if (tradingFee > 0) {
            payable(platformFeeCollector).transfer(tradingFee);
        }
        
        // Emit events for tracking
        emit TokensSold(msg.sender, amount, proceeds, s - amount);
        emit PriceUpdated(_priceAtSupply(s - amount), s - amount);
        
        // Transfer net proceeds to the seller
        payable(msg.sender).sendValue(netProceeds);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // GRADUATION SYSTEM
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Internal function to check if graduation conditions are met
     * @dev Called after every buy operation to check if graduation threshold is reached
     * @dev Automatically triggers graduation if conditions are met
     * 
     * Graduation Conditions:
     * - Market cap >= graduation threshold
     * - Token has not graduated yet
     */
    function _checkGraduation() internal {
        if (getMarketCap() >= graduationThreshold && !hasGraduated) {
            _graduate();
        }
    }
    
    /**
     * @notice Internal function that executes the graduation process
     * @dev This is the most critical function - it transitions from bonding curve to DEX
     * @dev Once called, the token can never return to bonding curve trading
     * 
     * Graduation Process (Native POL UX):
     * 1. Calculate amounts and create pair first
     * 2. Mint additional tokens equal to current supply for liquidity
     * 3. Calculate liquidity amounts (LIQUIDITY_FEE % of totalRaised)
     * 4. Try to add liquidity to V2 pair using addLiquidityETH
     * 5. Only mark as graduated if Uniswap operations succeed
     * 6. Distribute remaining fees to creator and platform in native POL
     * 
     * Technical Implementation:
     * - V2 pair works directly with native ETH/POL (no wrapping needed)
     * - Simpler than V3 - no ticks, ranges, or NFT positions
     * - Standard AMM with constant product formula
     * - LP tokens represent proportional ownership
     * 
     * Token Supply Impact:
     * - Before graduation: X tokens in circulation
     * - After graduation: 2X tokens total (X circulating + X in LP)
     * - This creates a 2:1 split where LP holds 50% of total supply
     * 
     */
    function _graduate() internal {
        // Calculate amounts for liquidity provision
        uint256 currentSupply = totalSupply();
        
        // Mint equal amount of tokens for liquidity (doubles total supply)
        uint256 liquidityTokenAmount = currentSupply;
        
        // Calculate POL for liquidity (typically 80% of totalRaised)
        uint256 liquidityPolAmount = (totalRaised * LIQUIDITY_FEE) / 10000;
        
        // Create or get the myToken/POL pair on Uniswap V2
        address pair = uniswapV2Factory.getPair(address(this), router.WETH());
        if (pair == address(0)) {
            pair = uniswapV2Factory.createPair(address(this), router.WETH());
        }
        
        // Mint additional tokens for the liquidity pool
        _mint(address(this), liquidityTokenAmount);
        
        // Approve router to spend our tokens
        _approve(address(this), address(router), liquidityTokenAmount);
        
        // Calculate dynamic slippage protection (5% max slippage)
        uint256 maxSlippage = 500; // 5% in basis points
        uint256 tokenMin = liquidityTokenAmount * (10000 - maxSlippage) / 10000;
        uint256 ethMin = liquidityPolAmount * (10000 - maxSlippage) / 10000;
        
        // Set deadline with validation
        uint256 deadline = block.timestamp + 300; // 5 minutes
        require(deadline > block.timestamp, "Deadline must be in the future");
        
        // Try Uniswap operation with proper error handling and dynamic slippage
        try router.addLiquidityETH{value: liquidityPolAmount}(
            address(this),                    // token
            liquidityTokenAmount,             // amountTokenDesired
            tokenMin,                         // amountTokenMin (dynamic slippage)
            ethMin,                           // amountETHMin (dynamic slippage)
            address(this),                    // to (this contract receives LP tokens)
            deadline                          // deadline (5 minutes)
        ) returns (uint amountToken, uint amountETH, uint liquidity) {
            // Only mark as graduated if Uniswap operations succeed
            hasGraduated = true;
            dexPool = pair;
            
            // Store the amount of liquidity tokens we received
            liquidityTokensAmount = liquidity;
            
            // Distribute remaining fees to creator and platform
            _distributeFees();
            
            // Emit events for tracking the successful myToken/POL pair creation
            emit GraduationTriggered(currentSupply, getMarketCap(), dexPool, liquidityTokensAmount);
            emit LiquidityAdded(amountToken, amountETH, liquidity);
        } catch {
            // Revert state changes if Uniswap operation fails
            _burn(address(this), liquidityTokenAmount);
            revert("Graduation failed: Uniswap operation unsuccessful");
        }
    }
    
    /**
     * @notice Internal function to distribute graduation fees
     * @dev Called during graduation to distribute remaining POL after liquidity provision
     * @dev Only distributes POL that remains after liquidity has been added
     * 
     * Fee Distribution:
     * 1. Calculate remaining POL balance after liquidity provision
     * 2. Distribute creator fee (typically 0%)
     * 3. Distribute platform fee (typically 20%)
     * 4. Any remaining POL stays in contract (should be minimal due to fee structure)
     * 
     * Example with totalRaised = 100 POL:
     * - Liquidity gets 80 POL (LIQUIDITY_FEE = 8000 basis points)
     * - After liquidity, remaining = ~20 POL
     * - Creator gets 0 POL (CREATOR_FEE = 0 basis points)
     * - Platform gets 20 POL (PLATFORM_FEE = 2000 basis points)
     */
    function _distributeFees() internal {
        // Get remaining POL balance after liquidity provision
        uint256 remainingPol = address(this).balance;
        
        // Calculate and distribute creator fee
        uint256 creatorFee = (remainingPol * CREATOR_FEE) / 10000;
        if (creatorFee > 0) {
            payable(creator).transfer(creatorFee);
        }
        
        // Calculate and distribute platform fee
        uint256 platformFee = (remainingPol * PLATFORM_FEE) / 10000;
        if (platformFee > 0) {
            payable(platformFeeCollector).transfer(platformFee);
        }
        
        // Note: Any remaining POL (due to rounding) stays in the contract
        // This should be minimal due to the fee structure design
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // ADMINISTRATIVE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Updates the platform fee collector address
     * @dev Only callable by the factory contract
     * @dev This address receives all trading fees and platform graduation fees
     * 
     * @param newPlatformFeeCollector The new platform fee collector address
     * 
     * Requirements:
     * - Caller must be the factory contract
     * - New address cannot be zero address
     * 
     * Use Cases:
     * - Factory owner wants to change fee collection address
     * - Upgrade to a new fee management contract
     * - Change from EOA to multisig for better security
     */
    function updatePlatformFeeCollector(address newPlatformFeeCollector) external onlyFactory {
        require(newPlatformFeeCollector != address(0), "Platform fee collector cannot be zero address");
        platformFeeCollector = newPlatformFeeCollector;
    }
    
    /**
     * @notice Updates the trading fees for buy and sell operations
     * @dev Only callable by the factory contract
     * @dev Allows dynamic adjustment of trading fees after deployment
     * 
     * @param newBuyTradingFee New buy trading fee in basis points (max 1000 = 10%)
     * @param newSellTradingFee New sell trading fee in basis points (max 1000 = 10%)
     * 
     */
    function updateTradingFees(uint256 newBuyTradingFee, uint256 newSellTradingFee) external onlyFactory {
        require(newBuyTradingFee <= 1000, "Buy trading fee cannot exceed 10%");
        require(newSellTradingFee <= 1000, "Sell trading fee cannot exceed 10%");
        
        buyTradingFee = newBuyTradingFee;
        sellTradingFee = newSellTradingFee;
        
        emit TradingFeesUpdated(newBuyTradingFee, newSellTradingFee);
    }
    
    /**
     * @notice Manually triggers graduation (factory only)
     * @dev Emergency function to force graduation without reaching market cap threshold
     * @dev Should be used sparingly and only for valid reasons
     * 
     * 
     * Use Cases:
     * - Emergency situations requiring immediate graduation
     * - Testing purposes in development environments
     * - Special events or milestones
     * 
     * WARNING: This bypasses the market cap requirement and should be used cautiously
     */
    function triggerGraduation() external onlyFactory notGraduated {
        _graduate();
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // OWNER CONTROL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Pauses all token transfers and trading
     * @dev Only callable by the token owner (creator)
     * @dev Emergency function to stop all token activity
     * 
     * Effects:
     * - Disables buyTokens() and sellTokens()
     * - Disables all token transfers
     * - Graduation can still occur if conditions are met
     * 
     * Use Cases:
     * - Emergency situations (security threats, bugs discovered)
     * - Maintenance periods
     * - Regulatory compliance requirements
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpauses token transfers and trading
     * @dev Only callable by the token owner (creator)
     * @dev Restores normal token functionality
     * 
     * Effects:
     * - Re-enables buyTokens() and sellTokens()
     * - Re-enables all token transfers
     * - Returns to normal operation
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // INFORMATION GETTER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Gets comprehensive token information in a single call
     * @dev Convenient function for frontends to get all key token data
     * @dev Gas-efficient alternative to multiple separate calls
     * 
     * @return currentPrice Current price per token in wei
     * @return currentSupply Current total supply of tokens
     * @return marketCap Current market capitalization in wei
     * @return graduationProgress Graduation progress in basis points (0-10000)
     * @return remainingForGraduation Remaining market cap needed for graduation in wei
     * @return graduated Whether the token has graduated to DEX
     * @return pairAddress V2 pair address (zero if not graduated)
     * 
     */
    function getTokenInfo() external view returns (
        uint256 currentPrice,
        uint256 currentSupply,
        uint256 marketCap,
        uint256 graduationProgress,
        uint256 remainingForGraduation,
        bool graduated,
        address pairAddress
    ) {
        currentPrice = getCurrentPrice();
        currentSupply = totalSupply();
        marketCap = getMarketCap();
        (graduationProgress, remainingForGraduation) = getGraduationProgress();
        graduated = hasGraduated;
        pairAddress = dexPool;
    }
    
    /**
     * @notice Gets current trading fee rates
     * @dev Returns buy and sell trading fees in basis points
     * 
     * @return buyFee Current buy trading fee in basis points
     * @return sellFee Current sell trading fee in basis points
     */
    function getTradingFees() external view returns (uint256 buyFee, uint256 sellFee) {
        return (buyTradingFee, sellTradingFee);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // BLACKLIST FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Blocks an account from all token operations
     * @dev Only callable by the token owner (creator)
     * @dev Blocked accounts cannot buy, sell, or transfer tokens
     * 
     * @param _account The address to block
     * 
     * Effects:
     * - Account cannot call buyTokens() or sellTokens()
     * - Account cannot send or receive token transfers
     * - Account can still view balances and contract state
     * 
     * Use Cases:
     * - Compliance with regulatory requirements
     * - Preventing malicious actors from participating
     * - Anti-money laundering measures
     * - Sanctions compliance
     */
    function blockAccount(address _account) public onlyOwner {
        _blockAccount(_account);
    }

    /**
     * @notice Unblocks a previously blocked account
     * @dev Only callable by the token owner (creator)
     * @dev Restores normal functionality for the account
     * 
     * @param _account The address to unblock
     * 
     * Effects:
     * - Account can call buyTokens() and sellTokens() again
     * - Account can send and receive token transfers again
     * - Returns account to normal operation
     */
    function unblockAccount(address _account) public onlyOwner {
        _unblockAccount(_account);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // ERC20 OVERRIDES AND SAFETY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Internal function that handles all token transfers
     * @dev Overrides OpenZeppelin's _update to add blacklist and pause checks
     * @dev Called for all minting, burning, and transfer operations
     * 
     * @param from Address sending tokens (zero for minting)
     * @param to Address receiving tokens (zero for burning)
     * @param amount Number of tokens being transferred
     * 
     * Security Checks:
     * 1. Contract must not be paused (whenNotPaused modifier)
     * 2. Recipient must not be blacklisted
     * 3. Sender must not be blacklisted (if not minting)
     * 
     * This ensures that:
     * - Blacklisted accounts cannot send or receive tokens
     * - All transfers are blocked when contract is paused
     * - Bonding curve operations (mint/burn) respect blacklist rules
     */
    function _update(address from, address to, uint256 amount) internal override whenNotPaused {
        // Check if recipient is blacklisted (applies to all transfers including mints)
        require(!isAccountBlocked(to), "BlackList: Recipient account is blocked");
        
        // Check if sender is blacklisted (applies to transfers and burns, but not mints)
        require(!isAccountBlocked(from), "BlackList: Sender account is blocked");

        // Call parent implementation to handle the actual transfer
        super._update(from, to, amount);
    }
    
    /**
     * @notice Receives POL sent directly to the contract
     * @dev Prevents accidental POL sends; require using buyTokens()
     * @dev Only allows POL for specific operations like liquidity provision
     */
    receive() external payable {
        // Prevent accidental POL sends; require using buyTokens()
        revert("Direct POL not accepted");
    }
    
    /**
     * @notice Fallback function for handling unexpected calls
     * @dev Called when contract is called with data that doesn't match any function
     * @dev Also accepts POL to ensure contract doesn't reject unexpected payments
     * 
     * Security Note:
     * - Does not execute any logic
     * - Simply accepts POL if sent
     * - Prevents accidental POL loss from misformed calls
     */
    fallback() external payable {}
}
