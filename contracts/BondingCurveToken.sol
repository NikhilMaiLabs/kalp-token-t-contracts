// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

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
 * @dev ERC20 token with linear bonding curve pricing and automatic graduation to DEX
 */
contract BondingCurveToken is ERC20, Ownable, ReentrancyGuard, Pausable {
    // Bonding curve parameters
    uint256 public slope;           // Price increase per token (in wei)
    uint256 public basePrice;       // Initial token price (in wei)
    uint256 public graduationThreshold; // Market cap for graduation (in wei)
    
    // State variables
    bool public hasGraduated;       // Graduation status
    address public dexPair;         // DEX pair after graduation
    address public creator;         // Token creator address
    uint256 public totalRaised;     // Total ETH raised
    address public factory;         // Factory contract address
    
    // DEX integration
    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable WETH;
    
    // Fee distribution percentages (in basis points, 10000 = 100%)
    uint256 public immutable LIQUIDITY_FEE;  // 80%
    uint256 public immutable CREATOR_FEE;    // 0%
    uint256 public immutable PLATFORM_FEE;   // 20%
    
    // Events
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 cost, uint256 newSupply);
    event TokensSold(address indexed seller, uint256 amount, uint256 refund, uint256 newSupply);
    event GraduationTriggered(uint256 supply, uint256 marketCap, address dexPair, uint256 liquidityAdded);
    event LiquidityAdded(uint256 tokenAmount, uint256 ethAmount, uint256 liquidity);
    
    // Modifiers
    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory can call this function");
        _;
    }
    
    modifier notGraduated() {
        require(!hasGraduated, "Token has already graduated");
        _;
    }
    
    modifier onlyGraduated() {
        require(hasGraduated, "Token has not graduated yet");
        _;
    }
    
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
        uint256 _platformFee
    ) ERC20(name, symbol) Ownable(_creator) {
        require(_slope > 0, "Slope must be greater than 0");
        require(_basePrice > 0, "Base price must be greater than 0");
        require(_graduationThreshold > 0, "Graduation threshold must be greater than 0");
        require(_creator != address(0), "Creator cannot be zero address");
        require(_factory != address(0), "Factory cannot be zero address");
        require(_uniswapV2Router != address(0), "Router cannot be zero address");
        require(_liquidityFee + _creatorFee + _platformFee == 10000, "Fees must sum to 10000 (100%)");
        
        slope = _slope;
        basePrice = _basePrice;
        graduationThreshold = _graduationThreshold;
        creator = _creator;
        factory = _factory;
        LIQUIDITY_FEE = _liquidityFee;
        CREATOR_FEE = _creatorFee;
        PLATFORM_FEE = _platformFee;
        
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        WETH = uniswapV2Router.WETH();
        
        // Transfer ownership to creator
        _transferOwnership(_creator);
    }
    
    /**
     * @dev Get current token price based on supply
     * @return Current price per token in wei
     */
    function getCurrentPrice() public view returns (uint256) {
        return basePrice + (slope * totalSupply());
    }
    
    /**
     * @dev Calculate cost to buy specified amount of tokens
     * @param amount Number of tokens to buy
     * @return Total cost in wei
     */
    function getBuyPrice(uint256 amount) public view returns (uint256) {
        require(amount > 0, "Amount must be greater than 0");
        
        uint256 currentSupply = totalSupply();
        
        // For linear bonding curve: price = basePrice + slope * supply
        // Cost = integral from currentSupply to currentSupply + amount
        // Cost = basePrice * amount + slope * currentSupply * amount + slope * amount * (amount - 1) / 2
        uint256 cost = basePrice * amount + 
                      slope * currentSupply * amount + 
                      slope * amount * (amount - 1) / 2;
        
        return cost;
    }
    
    /**
     * @dev Calculate refund for selling specified amount of tokens
     * @param amount Number of tokens to sell
     * @return Total refund in wei
     */
    function getSellPrice(uint256 amount) public view returns (uint256) {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= totalSupply(), "Cannot sell more than total supply");
        
        uint256 currentSupply = totalSupply();
        uint256 newSupply = currentSupply - amount;
        
        // Calculate refund using integration from newSupply to currentSupply
        uint256 refund = basePrice * amount + 
                        slope * newSupply * amount + 
                        slope * amount * (amount - 1) / 2;
        
        return refund;
    }
    
    /**
     * @dev Get current market cap
     * @return Market cap in wei
     */
    function getMarketCap() public view returns (uint256) {
        return totalSupply() * getCurrentPrice();
    }
    
    /**
     * @dev Get graduation progress
     * @return progress Progress percentage (0-10000, where 10000 = 100%)
     * @return remaining Remaining amount needed for graduation
     */
    function getGraduationProgress() public view returns (uint256 progress, uint256 remaining) {
        uint256 currentMarketCap = getMarketCap();
        
        if (currentMarketCap >= graduationThreshold) {
            return (10000, 0); // 100% complete
        }
        
        remaining = graduationThreshold - currentMarketCap;
        progress = (currentMarketCap * 10000) / graduationThreshold;
        
        return (progress, remaining);
    }
    
    /**
     * @dev Buy tokens with ETH
     * @param amount Number of tokens to buy
     */
    function buyTokens(uint256 amount) external payable nonReentrant whenNotPaused notGraduated {
        require(amount > 0, "Amount must be greater than 0");
        
        uint256 cost = getBuyPrice(amount);
        require(msg.value >= cost, "Insufficient ETH sent");
        
        // Mint tokens to buyer
        _mint(msg.sender, amount);
        
        // Update total raised
        totalRaised += cost;
        
        // Refund excess ETH
        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }
        
        emit TokensPurchased(msg.sender, amount, cost, totalSupply());
        
        // Check for graduation
        _checkGraduation();
    }
    
    /**
     * @dev Sell tokens for ETH (only before graduation)
     * @param amount Number of tokens to sell
     */
    function sellTokens(uint256 amount) external nonReentrant whenNotPaused notGraduated {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient token balance");
        
        uint256 refund = getSellPrice(amount);
        require(address(this).balance >= refund, "Insufficient contract balance");
        
        // Burn tokens from seller
        _burn(msg.sender, amount);
        
        // Update total raised
        totalRaised -= refund;
        
        // Transfer ETH to seller
        payable(msg.sender).transfer(refund);
        
        emit TokensSold(msg.sender, amount, refund, totalSupply());
    }
    
    /**
     * @dev Check if graduation conditions are met and trigger graduation
     */
    function _checkGraduation() internal {
        if (getMarketCap() >= graduationThreshold && !hasGraduated) {
            _graduate();
        }
    }
    
    /**
     * @dev Trigger graduation process
     */
    function _graduate() internal {
        hasGraduated = true;
        
        // Create Uniswap V2 pair
        IUniswapV2Factory factoryContract = IUniswapV2Factory(uniswapV2Router.factory());
        dexPair = factoryContract.createPair(address(this), WETH);
        
        // Calculate amounts for liquidity
        uint256 currentSupply = totalSupply();
        uint256 liquidityTokenAmount = currentSupply; // Mint equal amount for liquidity
        uint256 liquidityEthAmount = (totalRaised * LIQUIDITY_FEE) / 10000;
        
        // Mint additional tokens for liquidity
        _mint(address(this), liquidityTokenAmount);
        
        // Approve router to spend tokens
        _approve(address(this), address(uniswapV2Router), liquidityTokenAmount);
        
        // Add liquidity to Uniswap
        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = uniswapV2Router.addLiquidityETH{value: liquidityEthAmount}(
            address(this),
            liquidityTokenAmount,
            liquidityTokenAmount * 95 / 100, // 5% slippage tolerance
            liquidityEthAmount * 95 / 100,   // 5% slippage tolerance
            address(this),
            block.timestamp + 300 // 5 minute deadline
        );
        
        // Distribute fees
        _distributeFees();
        
        emit GraduationTriggered(currentSupply, getMarketCap(), dexPair, liquidity);
        emit LiquidityAdded(amountToken, amountETH, liquidity);
    }
    
    /**
     * @dev Distribute fees after graduation
     */
    function _distributeFees() internal {
        uint256 remainingEth = address(this).balance;
        
        // Distribute creator fee
        uint256 creatorFee = (remainingEth * CREATOR_FEE) / 10000;
        if (creatorFee > 0) {
            payable(creator).transfer(creatorFee);
        }
        
        // Distribute platform fee to factory
        uint256 platformFee = (remainingEth * PLATFORM_FEE) / 10000;
        if (platformFee > 0) {
            payable(factory).transfer(platformFee);
        }
    }
    
    /**
     * @dev Manual graduation trigger (factory only)
     */
    function triggerGraduation() external onlyFactory notGraduated {
        _graduate();
    }
    
    /**
     * @dev Pause token transfers (owner only)
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause token transfers (owner only)
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Override transfer to check graduation status
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._update(from, to, amount);
    }
    
    /**
     * @dev Get token information
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
     * @dev Receive ETH
     */
    receive() external payable {}
    
    /**
     * @dev Fallback function
     */
    fallback() external payable {}
}
