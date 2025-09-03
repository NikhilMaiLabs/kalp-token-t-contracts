// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./utils/Blacklist.sol";

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
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
}

/**
 * @title BondingCurveToken
 * @author Kalp Team
 * @notice A bonding curve token that uses a linear pricing model and automatically graduates to a DEX
 * @dev This contract implements an ERC20 token with the following features:
 * 
 * BONDING CURVE MECHANICS:
 * - Uses linear bonding curve: price = basePrice + slope * totalSupply
 * - Users can buy/sell tokens at any time before graduation
 * - Price increases linearly with each token minted
 * - All ETH raised is held in the contract until graduation
 * 
 * GRADUATION SYSTEM:
 * - Token "graduates" when market cap reaches the graduation threshold
 * - Upon graduation, liquidity is automatically added to Uniswap V2
 * - Fees are distributed to liquidity, creator, and platform
 * - After graduation, normal DEX trading begins
 * 
 * FEE STRUCTURE:
 * - Trading fees: Applied on every buy/sell transaction (configurable)
 * - Graduation fees: Applied only upon graduation (liquidity/creator/platform split)
 * - All fees are collected by the platform fee collector address
 * 
 * SECURITY FEATURES:
 * - Blacklist functionality to block malicious addresses
 * - Pausable transfers for emergency situations
 * - Reentrancy protection on all critical functions
 * - Access control for administrative functions
 * 
 * ACCESS CONTROL:
 * - Owner (Creator): Can pause/unpause, manage blacklist
 * - Factory: Can update fees, trigger graduation, update fee collector
 * - Users: Can buy/sell tokens, view information
 */
contract BondingCurveToken is ERC20, Ownable, ReentrancyGuard, Pausable, BlackList {
    
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
    
    /// @notice The Uniswap V2 pair address created during graduation
    /// @dev Only set after graduation, used for DEX trading
    address public dexPair;
    
    /// @notice The address of the token creator
    /// @dev Also serves as the initial owner of the contract
    address public creator;
    
    /// @notice Total ETH raised from token sales (excluding trading fees)
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
    IUniswapV2Router02 public immutable uniswapV2Router;
    
    /// @notice The WETH token address from the Uniswap router
    /// @dev Used for creating trading pairs during graduation
    address public immutable WETH;
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // FEE CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /// @notice Percentage of graduation fees allocated to liquidity (in basis points)
    /// @dev Applied only during graduation, typically 8000 (80%)
    /// @dev These fees come from totalRaised ETH
    uint256 public immutable LIQUIDITY_FEE;
    
    /// @notice Percentage of graduation fees allocated to token creator (in basis points)
    /// @dev Applied only during graduation, typically 0 (0%)
    /// @dev These fees come from totalRaised ETH
    uint256 public immutable CREATOR_FEE;
    
    /// @notice Percentage of graduation fees allocated to platform (in basis points)
    /// @dev Applied only during graduation, typically 2000 (20%)
    /// @dev These fees come from totalRaised ETH
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
    /// @param cost Total ETH cost (excluding trading fees)
    /// @param newSupply New total supply after the purchase
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 cost, uint256 newSupply);
    
    /// @notice Emitted when tokens are sold back to the bonding curve
    /// @param seller Address that sold the tokens
    /// @param amount Number of tokens sold
    /// @param refund Total ETH refund (excluding trading fees)
    /// @param newSupply New total supply after the sale
    event TokensSold(address indexed seller, uint256 amount, uint256 refund, uint256 newSupply);
    
    /// @notice Emitted when the token graduates to DEX trading
    /// @param supply Total token supply at graduation
    /// @param marketCap Market cap that triggered graduation
    /// @param dexPair Address of the created Uniswap V2 pair
    /// @param liquidityAdded Amount of liquidity tokens received
    event GraduationTriggered(uint256 supply, uint256 marketCap, address dexPair, uint256 liquidityAdded);
    
    /// @notice Emitted when liquidity is added to Uniswap during graduation
    /// @param tokenAmount Number of tokens added to liquidity
    /// @param ethAmount Amount of ETH added to liquidity
    /// @param liquidity Amount of LP tokens received
    event LiquidityAdded(uint256 tokenAmount, uint256 ethAmount, uint256 liquidity);
    
    /// @notice Emitted when trading fees are updated by the factory
    /// @param buyFee New buy trading fee in basis points
    /// @param sellFee New sell trading fee in basis points
    event TradingFeesUpdated(uint256 buyFee, uint256 sellFee);
    
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
     * @param _uniswapV2Router The address of the Uniswap V2 router for DEX integration
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
        address _uniswapV2Router,
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
        require(_uniswapV2Router != address(0), "Router cannot be zero address");
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
        
        // Initialize DEX integration
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        WETH = uniswapV2Router.WETH();
        
        // Transfer ownership to creator (they can pause, manage blacklist, etc.)
        _transferOwnership(_creator);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // BONDING CURVE PRICING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Gets the current price per token based on total supply
     * @dev Uses linear bonding curve formula: price = basePrice + slope * totalSupply
     * @dev This is the instantaneous price for the next token to be minted
     * 
     * @return currentPrice The current price per token in wei
     * 
     * Example:
     * - basePrice = 1000 wei, slope = 100 wei, totalSupply = 50
     * - currentPrice = 1000 + (100 * 50) = 6000 wei
     */
    function getCurrentPrice() public view returns (uint256 currentPrice) {
        return basePrice + (slope * totalSupply());
    }
    
    /**
     * @notice Calculates the total cost to buy a specific amount of tokens
     * @dev Uses integration to find the area under the linear curve
     * @dev Formula: cost = basePrice * amount + slope * currentSupply * amount + slope * amount * (amount - 1) / 2
     * @dev The last term accounts for the price increase during the batch purchase
     * 
     * @param amount Number of tokens to buy (must be > 0)
     * @return totalCost Total cost in wei (excluding trading fees)
     * 
     * Mathematical explanation:
     * - For a linear curve, we integrate from currentSupply to currentSupply + amount
     * - The integral of (basePrice + slope * x) dx from a to b is:
     *   basePrice * (b - a) + slope * (b² - a²) / 2
     * - This simplifies to the formula used below
     * 
     * Example:
     * - Buying 10 tokens when supply = 100, basePrice = 1000, slope = 50
     * - cost = 1000*10 + 50*100*10 + 50*10*9/2 = 10000 + 50000 + 2250 = 62250 wei
     */
    function getBuyPrice(uint256 amount) public view returns (uint256 totalCost) {
        require(amount > 0, "Amount must be greater than 0");
        
        uint256 currentSupply = totalSupply();
        
        // Calculate the area under the linear bonding curve
        // This represents the total cost for buying 'amount' tokens
        totalCost = basePrice * amount + 
                   slope * currentSupply * amount + 
                   slope * amount * (amount - 1) / 2;
        
        return totalCost;
    }
    
    /**
     * @notice Calculates the total refund for selling a specific amount of tokens
     * @dev Uses integration to find the area under the linear curve (in reverse)
     * @dev The refund is calculated from the new supply level up to current supply
     * 
     * @param amount Number of tokens to sell (must be > 0 and <= totalSupply)
     * @return totalRefund Total refund in wei (before trading fees)
     * 
     * Mathematical explanation:
     * - When selling, we calculate the area from (currentSupply - amount) to currentSupply
     * - This uses the same integration formula as buying, but from the lower range
     * - newSupply = currentSupply - amount
     * - refund = integral from newSupply to currentSupply
     * 
     * Example:
     * - Selling 5 tokens when supply = 105, basePrice = 1000, slope = 50
     * - newSupply = 100, so we integrate from 100 to 105
     * - refund = 1000*5 + 50*100*5 + 50*5*4/2 = 5000 + 25000 + 500 = 30500 wei
     */
    function getSellPrice(uint256 amount) public view returns (uint256 totalRefund) {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= totalSupply(), "Cannot sell more than total supply");
        
        uint256 currentSupply = totalSupply();
        uint256 newSupply = currentSupply - amount;
        
        // Calculate the area under the curve from newSupply to currentSupply
        // This represents the refund for selling 'amount' tokens
        totalRefund = basePrice * amount + 
                     slope * newSupply * amount + 
                     slope * amount * (amount - 1) / 2;
        
        return totalRefund;
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
        return totalSupply() * getCurrentPrice();
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
     * @notice Buy tokens using ETH through the bonding curve
     * @dev This function handles the complete buy process including trading fees
     * @dev Only available before graduation - after graduation, use DEX
     * 
     * Process:
     * 1. Calculate bonding curve cost
     * 2. Calculate and collect trading fee
     * 3. Mint tokens to buyer
     * 4. Update totalRaised (excluding trading fee)
     * 5. Refund any excess ETH
     * 6. Check if graduation threshold is reached
     * 
     * @param amount Number of tokens to buy (must be > 0)
     * 
     * Requirements:
     * - Token must not be graduated yet
     * - Contract must not be paused
     * - Amount must be greater than 0
     * - Must send enough ETH to cover cost + trading fee
     * 
     * Emits:
     * - TokensPurchased event with purchase details
     * - Potentially GraduationTriggered if threshold is reached
     * 
     * Example:
     * - Buying 10 tokens with cost = 62250 wei, tradingFee = 1% = 622 wei
     * - Total required = 62250 + 622 = 62872 wei
     * - totalRaised increases by 62250 wei (bonding curve portion only)
     * - Trading fee goes directly to platform fee collector
     */
    function buyTokens(uint256 amount) external payable nonReentrant whenNotPaused notGraduated {
        require(amount > 0, "Amount must be greater than 0");
        
        // Calculate bonding curve cost (base cost without trading fee)
        uint256 cost = getBuyPrice(amount);
        
        // Calculate trading fee on the base cost
        uint256 tradingFee = (cost * buyTradingFee) / 10000;
        
        // Total cost including trading fee
        uint256 totalCost = cost + tradingFee;
        
        // Ensure user sent enough ETH
        require(msg.value >= totalCost, "Insufficient ETH sent");
        
        // Mint tokens to the buyer
        _mint(msg.sender, amount);
        
        // Update totalRaised with only the bonding curve cost
        // (Trading fees don't count towards graduation calculations)
        totalRaised += cost;
        
        // Transfer trading fee directly to platform fee collector
        if (tradingFee > 0) {
            payable(platformFeeCollector).transfer(tradingFee);
        }
        
        // Refund any excess ETH sent by the user
        if (msg.value > totalCost) {
            payable(msg.sender).transfer(msg.value - totalCost);
        }
        
        // Emit event for tracking (cost excludes trading fee)
        emit TokensPurchased(msg.sender, amount, cost, totalSupply());
        
        // Check if the purchase triggers graduation to DEX
        _checkGraduation();
    }
    
    /**
     * @notice Sell tokens back to the bonding curve for ETH
     * @dev This function handles the complete sell process including trading fees
     * @dev Only available before graduation - after graduation, use DEX
     * 
     * Process:
     * 1. Calculate bonding curve refund
     * 2. Calculate and collect trading fee from refund
     * 3. Burn tokens from seller
     * 4. Update totalRaised (decrease by full refund amount)
     * 5. Transfer net refund to seller (refund - trading fee)
     * 
     * @param amount Number of tokens to sell (must be > 0 and <= user balance)
     * 
     * Requirements:
     * - Token must not be graduated yet
     * - Contract must not be paused
     * - Amount must be greater than 0
     * - Seller must have enough token balance
     * - Contract must have enough ETH balance for refund
     * 
     * Emits:
     * - TokensSold event with sale details
     * 
     * Example:
     * - Selling 10 tokens with refund = 30500 wei, sellTradingFee = 2% = 610 wei
     * - Net refund to seller = 30500 - 610 = 29890 wei
     * - totalRaised decreases by 30500 wei (full refund amount)
     * - Trading fee goes to platform fee collector
     */
    function sellTokens(uint256 amount) external nonReentrant whenNotPaused notGraduated {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient token balance");
        
        // Calculate bonding curve refund (base refund without trading fee)
        uint256 refund = getSellPrice(amount);
        
        // Calculate trading fee on the refund amount
        uint256 tradingFee = (refund * sellTradingFee) / 10000;
        
        // Net refund to seller after trading fee deduction
        uint256 netRefund = refund - tradingFee;
        
        // Ensure contract has enough ETH for the full refund
        require(address(this).balance >= refund, "Insufficient contract balance");
        
        // Burn tokens from the seller (reduces total supply)
        _burn(msg.sender, amount);
        
        // Update totalRaised by the full refund amount
        // (This maintains bonding curve integrity)
        totalRaised -= refund;
        
        // Transfer trading fee to platform fee collector
        if (tradingFee > 0) {
            payable(platformFeeCollector).transfer(tradingFee);
        }
        
        // Transfer net refund to the seller
        payable(msg.sender).transfer(netRefund);
        
        // Emit event for tracking (refund excludes trading fee)
        emit TokensSold(msg.sender, amount, refund, totalSupply());
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
     * Graduation Process:
     * 1. Mark token as graduated (disables buy/sell functions)
     * 2. Create Uniswap V2 trading pair (TOKEN/WETH)
     * 3. Mint additional tokens equal to current supply for liquidity
     * 4. Calculate ETH amount for liquidity (LIQUIDITY_FEE % of totalRaised)
     * 5. Add liquidity to Uniswap V2 pair
     * 6. Distribute remaining fees to creator and platform
     * 
     * Token Supply Impact:
     * - Before graduation: X tokens in circulation
     * - After graduation: 2X tokens total (X circulating + X in LP)
     * - This creates a 2:1 split where LP holds 50% of total supply
     * 
     * Economic Impact:
     * - Sets initial DEX price based on bonding curve final price
     * - Creates immediate liquidity for DEX trading
     * - Enables normal ERC20 functionality
     */
    function _graduate() internal {
        // Mark token as graduated (no more bonding curve trading)
        hasGraduated = true;
        
        // Create Uniswap V2 pair for TOKEN/WETH trading
        IUniswapV2Factory factoryContract = IUniswapV2Factory(uniswapV2Router.factory());
        dexPair = factoryContract.createPair(address(this), WETH);
        
        // Calculate amounts for liquidity provision
        uint256 currentSupply = totalSupply();
        
        // Mint equal amount of tokens for liquidity (doubles total supply)
        uint256 liquidityTokenAmount = currentSupply;
        
        // Calculate ETH for liquidity (typically 80% of totalRaised)
        uint256 liquidityEthAmount = (totalRaised * LIQUIDITY_FEE) / 10000;
        
        // Mint additional tokens to this contract for liquidity
        _mint(address(this), liquidityTokenAmount);
        
        // Approve Uniswap router to spend our tokens
        _approve(address(this), address(uniswapV2Router), liquidityTokenAmount);
        
        // Add liquidity to Uniswap V2 with slippage protection
        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = uniswapV2Router.addLiquidityETH{
            value: liquidityEthAmount
        }(
            address(this),                    // Token address
            liquidityTokenAmount,             // Desired token amount
            liquidityTokenAmount * 95 / 100,  // Min token amount (5% slippage)
            liquidityEthAmount * 95 / 100,    // Min ETH amount (5% slippage)
            address(this),                    // LP tokens recipient (contract keeps them)
            block.timestamp + 300             // 5 minute deadline
        );
        
        // Distribute remaining fees to creator and platform
        _distributeFees();
        
        // Emit events for tracking
        emit GraduationTriggered(currentSupply, getMarketCap(), dexPair, liquidity);
        emit LiquidityAdded(amountToken, amountETH, liquidity);
    }
    
    /**
     * @notice Internal function to distribute graduation fees
     * @dev Called during graduation to distribute remaining ETH after liquidity provision
     * @dev Only distributes ETH that remains after liquidity has been added
     * 
     * Fee Distribution:
     * 1. Calculate remaining ETH balance after liquidity provision
     * 2. Distribute creator fee (typically 0%)
     * 3. Distribute platform fee (typically 20%)
     * 4. Any remaining ETH stays in contract (should be minimal due to fee structure)
     * 
     * Example with totalRaised = 100 ETH:
     * - Liquidity gets 80 ETH (LIQUIDITY_FEE = 8000 basis points)
     * - After liquidity, remaining = ~20 ETH
     * - Creator gets 0 ETH (CREATOR_FEE = 0 basis points)
     * - Platform gets 20 ETH (PLATFORM_FEE = 2000 basis points)
     */
    function _distributeFees() internal {
        // Get remaining ETH balance after liquidity provision
        uint256 remainingEth = address(this).balance;
        
        // Calculate and distribute creator fee
        uint256 creatorFee = (remainingEth * CREATOR_FEE) / 10000;
        if (creatorFee > 0) {
            payable(creator).transfer(creatorFee);
        }
        
        // Calculate and distribute platform fee
        uint256 platformFee = (remainingEth * PLATFORM_FEE) / 10000;
        if (platformFee > 0) {
            payable(platformFeeCollector).transfer(platformFee);
        }
        
        // Note: Any remaining ETH (due to rounding) stays in the contract
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
     * Requirements:
     * - Caller must be the factory contract
     * - Both fees must be <= 1000 basis points (10%)
     * 
     * Emits:
     * - TradingFeesUpdated event with new fee values
     * 
     * Use Cases:
     * - Adjust fees based on market conditions
     * - Promotional periods with reduced fees
     * - Anti-bot measures with temporary higher fees
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
     * Requirements:
     * - Caller must be the factory contract
     * - Token must not be graduated yet
     * 
     * Emits:
     * - GraduationTriggered event
     * - LiquidityAdded event
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
     * @return pairAddress DEX pair address (zero if not graduated)
     * 
     * Usage:
     * - Frontend dashboards
     * - Portfolio tracking
     * - Analytics platforms
     * - Trading interfaces
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
        pairAddress = dexPair;
    }
    
    /**
     * @notice Gets current trading fee rates
     * @dev Returns buy and sell trading fees in basis points
     * 
     * @return buyFee Current buy trading fee in basis points
     * @return sellFee Current sell trading fee in basis points
     * 
     * Example:
     * - Returns (100, 200) means 1% buy fee and 2% sell fee
     * - Returns (0, 0) means no trading fees
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
     * @notice Receives ETH sent directly to the contract
     * @dev Allows the contract to accept ETH for liquidity and fee operations
     * @dev ETH can be sent for various reasons:
     *   - Direct donations
     *   - Refunds from failed DEX operations
     *   - Gas stipend refunds
     * 
     * Note: This does NOT trigger token purchases
     * Use buyTokens() function to purchase tokens with ETH
     */
    receive() external payable {}
    
    /**
     * @notice Fallback function for handling unexpected calls
     * @dev Called when contract is called with data that doesn't match any function
     * @dev Also accepts ETH to ensure contract doesn't reject unexpected payments
     * 
     * Security Note:
     * - Does not execute any logic
     * - Simply accepts ETH if sent
     * - Prevents accidental ETH loss from misformed calls
     */
    fallback() external payable {}
}
