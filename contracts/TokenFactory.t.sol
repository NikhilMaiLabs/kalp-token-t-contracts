// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/TokenFactory.sol";
import "../contracts/BondingCurveToken.sol";

// Mock Uniswap V2 Router for testing
contract MockUniswapV2Router {
    address public immutable factory;
    address public immutable WETH;
    
    constructor(address _factory, address _weth) {
        factory = _factory;
        WETH = _weth;
    }
    
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity) {
        // Mock implementation - just return the input amounts
        amountToken = amountTokenDesired;
        amountETH = msg.value;
        liquidity = 1000; // Mock liquidity amount
    }
}

// Mock Uniswap V2 Factory for testing
contract MockUniswapV2Factory {
    mapping(address => mapping(address => address)) public getPair;
    
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        // Create a mock pair address
        pair = address(uint160(uint256(keccak256(abi.encodePacked(tokenA, tokenB, block.timestamp)))));
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair;
        return pair;
    }
}

/**
 * @title TokenFactoryTest
 * @dev Comprehensive test suite for TokenFactory and BondingCurveToken
 */
contract TokenFactoryTest is Test {
    TokenFactory public factory;
    MockUniswapV2Router public mockRouter;
    MockUniswapV2Factory public mockFactory;
    
    address public owner = address(0x1);
    address public creator = address(0x2);
    address public buyer = address(0x3);
    address public seller = address(0x4);
    
    // Test parameters
    string constant TOKEN_NAME = "Test Token";
    string constant TOKEN_SYMBOL = "TEST";
    uint256 constant SLOPE = 1e15; // 0.001 ether
    uint256 constant BASE_PRICE = 1e15; // 0.001 ether
    uint256 constant GRADUATION_THRESHOLD = 69 ether;
    uint256 constant CREATION_FEE = 0.01 ether;
    
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
    
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 cost, uint256 newSupply);
    event TokensSold(address indexed seller, uint256 amount, uint256 refund, uint256 newSupply);
    event GraduationTriggered(uint256 supply, uint256 marketCap, address dexPair, uint256 liquidityAdded);
    
    function setUp() public {
        // Deploy mock contracts
        mockFactory = new MockUniswapV2Factory();
        mockRouter = new MockUniswapV2Router(address(mockFactory), address(0x5)); // Mock WETH
        
        // Deploy factory
        vm.prank(owner);
        factory = new TokenFactory(address(mockRouter));
        
        // Fund test accounts
        vm.deal(creator, 10 ether);
        vm.deal(buyer, 10 ether);
        vm.deal(seller, 10 ether);
    }
    
    function testTokenCreation() public {
        vm.prank(creator);
        address tokenAddress = factory.createToken{value: CREATION_FEE}(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            SLOPE,
            BASE_PRICE
        );
        
        // Verify token was created
        assertTrue(tokenAddress != address(0));
        assertTrue(factory.isTokenCreated(tokenAddress));
        
        // Verify token properties
        BondingCurveToken token = BondingCurveToken(payable(tokenAddress));
        assertEq(token.name(), TOKEN_NAME);
        assertEq(token.symbol(), TOKEN_SYMBOL);
        assertEq(token.slope(), SLOPE);
        assertEq(token.basePrice(), BASE_PRICE);
        assertEq(token.graduationThreshold(), GRADUATION_THRESHOLD);
        assertEq(token.creator(), creator);
        assertEq(token.owner(), creator);
        
        // Verify factory tracking
        assertEq(factory.getTokenCount(), 1);
        assertEq(factory.getCreatorTokens(creator).length, 1);
        assertEq(factory.getCreatorTokens(creator)[0], tokenAddress);
    }
    
    function testTokenBuying() public {
        // Create token
        vm.prank(creator);
        address tokenAddress = factory.createToken{value: CREATION_FEE}(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            SLOPE,
            BASE_PRICE
        );
        
        BondingCurveToken token = BondingCurveToken(payable(tokenAddress));
        
        // Test buying tokens
        uint256 buyAmount = 100;
        uint256 expectedCost = token.getBuyPrice(buyAmount);
        
        // Ensure buyer has enough ETH
        vm.deal(buyer, expectedCost + 1 ether);
        
        vm.prank(buyer);
        token.buyTokens{value: expectedCost}(buyAmount);
        
        // Verify token balance
        assertEq(token.balanceOf(buyer), buyAmount);
        assertEq(token.totalSupply(), buyAmount);
        assertEq(token.totalRaised(), expectedCost);
    }
    
    function testErrorHandling() public {
        // Test insufficient creation fee
        vm.prank(creator);
        vm.expectRevert("Insufficient creation fee");
        factory.createToken{value: CREATION_FEE - 1}(
            TOKEN_NAME, TOKEN_SYMBOL, SLOPE, BASE_PRICE
        );
        
        // Test invalid parameters
        vm.prank(creator);
        vm.expectRevert("Name cannot be empty");
        factory.createToken{value: CREATION_FEE}(
            "", TOKEN_SYMBOL, SLOPE, BASE_PRICE
        );
        
        vm.prank(creator);
        vm.expectRevert("Slope must be greater than 0");
        factory.createToken{value: CREATION_FEE}(
            TOKEN_NAME, TOKEN_SYMBOL, 0, BASE_PRICE
        );
    }
    
    function testLinearBondingCurvePriceCalculation() public {
        // Create token with high graduation threshold to avoid auto-graduation
        vm.prank(creator);
        address tokenAddress = factory.createTokenWithCustomThreshold{value: CREATION_FEE}(
            TOKEN_NAME, TOKEN_SYMBOL, SLOPE, BASE_PRICE, 1000 ether
        );
        
        BondingCurveToken token = BondingCurveToken(payable(tokenAddress));
        
        // Test initial price (should be base price when no tokens are minted)
        assertEq(token.getCurrentPrice(), BASE_PRICE);
        assertEq(token.getMarketCap(), 0);
        
        // Test buy price calculation for different amounts
        uint256 amount1 = 100;
        uint256 amount2 = 200;
        uint256 amount3 = 500;
        
        uint256 price1 = token.getBuyPrice(amount1);
        uint256 price2 = token.getBuyPrice(amount2);
        uint256 price3 = token.getBuyPrice(amount3);
        
        // Verify prices increase with amount (due to slope)
        assertTrue(price2 > price1);
        assertTrue(price3 > price2);
        
        // Test mathematical formula: cost = basePrice * amount + slope * currentSupply * amount + slope * amount * (amount - 1) / 2
        uint256 expectedPrice1 = BASE_PRICE * amount1 + SLOPE * 0 * amount1 + SLOPE * amount1 * (amount1 - 1) / 2;
        assertEq(price1, expectedPrice1);
        
        // Buy some tokens and test price changes
        vm.deal(buyer, price1 + 1 ether);
        vm.prank(buyer);
        token.buyTokens{value: price1}(amount1);
        
        // Verify new current price (should be basePrice + slope * supply)
        uint256 newCurrentPrice = token.getCurrentPrice();
        assertEq(newCurrentPrice, BASE_PRICE + SLOPE * amount1);
        
        // Verify market cap
        uint256 marketCap = token.getMarketCap();
        assertEq(marketCap, amount1 * newCurrentPrice);
        
        // Test that buying more tokens now costs more (price increased)
        uint256 newPrice2 = token.getBuyPrice(amount2);
        assertTrue(newPrice2 > price2); // Should be higher than before
        
        // Buy more tokens
        vm.deal(buyer, newPrice2 + 1 ether);
        vm.prank(buyer);
        token.buyTokens{value: newPrice2}(amount2);
        
        // Verify final state
        assertEq(token.totalSupply(), amount1 + amount2);
        assertEq(token.balanceOf(buyer), amount1 + amount2);
        assertEq(token.totalRaised(), price1 + newPrice2);
    }
    
    function testBondingCurveSellPriceCalculation() public {
        // Create token with high graduation threshold to avoid auto-graduation
        vm.prank(creator);
        address tokenAddress = factory.createTokenWithCustomThreshold{value: CREATION_FEE}(
            TOKEN_NAME, TOKEN_SYMBOL, SLOPE, BASE_PRICE, 1000 ether
        );
        
        BondingCurveToken token = BondingCurveToken(payable(tokenAddress));
        
        // Buy tokens first
        uint256 buyAmount = 500;
        uint256 buyCost = token.getBuyPrice(buyAmount);
        
        vm.deal(buyer, buyCost + 1 ether);
        vm.prank(buyer);
        token.buyTokens{value: buyCost}(buyAmount);
        
        // Test sell price calculation
        uint256 sellAmount1 = 100;
        uint256 sellAmount2 = 200;
        uint256 sellAmount3 = 500;
        
        uint256 sellPrice1 = token.getSellPrice(sellAmount1);
        uint256 sellPrice2 = token.getSellPrice(sellAmount2);
        uint256 sellPrice3 = token.getSellPrice(sellAmount3);
        
        // Verify sell prices decrease with amount (due to slope)
        assertTrue(sellPrice2 > sellPrice1);
        assertTrue(sellPrice3 > sellPrice2);
        
        // Test mathematical formula for sell price
        uint256 currentSupply = token.totalSupply();
        uint256 newSupply = currentSupply - sellAmount1;
        uint256 expectedSellPrice1 = BASE_PRICE * sellAmount1 + SLOPE * newSupply * sellAmount1 + SLOPE * sellAmount1 * (sellAmount1 - 1) / 2;
        assertEq(sellPrice1, expectedSellPrice1);
        
        // Sell some tokens
        vm.prank(buyer);
        token.sellTokens(sellAmount1);
        
        // Verify new state
        assertEq(token.totalSupply(), currentSupply - sellAmount1);
        assertEq(token.balanceOf(buyer), buyAmount - sellAmount1);
        
        // Test that selling more tokens now gives less (price decreased)
        uint256 newSellPrice2 = token.getSellPrice(sellAmount2);
        assertTrue(newSellPrice2 < sellPrice2); // Should be lower than before
        
        // Sell more tokens
        vm.prank(buyer);
        token.sellTokens(sellAmount2);
        
        // Verify final state
        assertEq(token.totalSupply(), currentSupply - sellAmount1 - sellAmount2);
        assertEq(token.balanceOf(buyer), buyAmount - sellAmount1 - sellAmount2);
    }
    
    function testBondingCurvePriceProgression() public {
        // Create token with specific parameters for easier calculation
        uint256 testSlope = 1e12; // 0.000001 ETH per token
        uint256 testBasePrice = 1e12; // 0.000001 ETH
        
        vm.prank(creator);
        address tokenAddress = factory.createTokenWithCustomThreshold{value: CREATION_FEE}(
            "Price Test Token", "PTT", testSlope, testBasePrice, 100 ether
        );
        
        BondingCurveToken token = BondingCurveToken(payable(tokenAddress));
        
        // Test price progression with multiple buys
        uint256[] memory amounts = new uint256[](5);
        uint256[] memory costs = new uint256[](5);
        uint256[] memory prices = new uint256[](5);
        
        amounts[0] = 100;
        amounts[1] = 200;
        amounts[2] = 300;
        amounts[3] = 400;
        amounts[4] = 500;
        
        vm.deal(buyer, 10 ether);
        
        for (uint256 i = 0; i < amounts.length; i++) {
            costs[i] = token.getBuyPrice(amounts[i]);
            prices[i] = token.getCurrentPrice();
            
            vm.prank(buyer);
            token.buyTokens{value: costs[i]}(amounts[i]);
            
            // Verify price increases after each buy
            if (i > 0) {
                assertTrue(prices[i] > prices[i-1], "Price should increase after each buy");
            }
        }
        
        // Verify total supply and raised amount
        uint256 totalBought = 0;
        uint256 totalCost = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalBought += amounts[i];
            totalCost += costs[i];
        }
        
        assertEq(token.totalSupply(), totalBought);
        assertEq(token.totalRaised(), totalCost);
        assertEq(token.balanceOf(buyer), totalBought);
    }
    
    function testBondingCurveSellProgression() public {
        // Create token with high graduation threshold to avoid auto-graduation
        vm.prank(creator);
        address tokenAddress = factory.createTokenWithCustomThreshold{value: CREATION_FEE}(
            TOKEN_NAME, TOKEN_SYMBOL, SLOPE, BASE_PRICE, 1000 ether
        );
        
        BondingCurveToken token = BondingCurveToken(payable(tokenAddress));
        
        // Buy a moderate amount first
        uint256 initialBuy = 500;
        uint256 initialCost = token.getBuyPrice(initialBuy);
        
        vm.deal(buyer, initialCost + 1 ether);
        vm.prank(buyer);
        token.buyTokens{value: initialCost}(initialBuy);
        
        // Test sell progression with smaller amounts
        uint256 sellAmount1 = 50;
        uint256 sellAmount2 = 100;
        
        uint256 sellPrice1 = token.getSellPrice(sellAmount1);
        uint256 sellPrice2 = token.getSellPrice(sellAmount2);
        
        // Verify sell prices are reasonable
        assertTrue(sellPrice1 > 0);
        assertTrue(sellPrice2 > 0);
        
        // Sell some tokens
        vm.prank(buyer);
        token.sellTokens(sellAmount1);
        
        // Verify state after first sell
        assertEq(token.totalSupply(), initialBuy - sellAmount1);
        assertEq(token.balanceOf(buyer), initialBuy - sellAmount1);
        
        // Sell more tokens
        vm.prank(buyer);
        token.sellTokens(sellAmount2);
        
        // Verify final state
        assertEq(token.totalSupply(), initialBuy - sellAmount1 - sellAmount2);
        assertEq(token.balanceOf(buyer), initialBuy - sellAmount1 - sellAmount2);
    }
    
    function testBondingCurveEdgeCases() public {
        // Create token with high graduation threshold to avoid auto-graduation
        vm.prank(creator);
        address tokenAddress = factory.createTokenWithCustomThreshold{value: CREATION_FEE}(
            TOKEN_NAME, TOKEN_SYMBOL, SLOPE, BASE_PRICE, 1000 ether
        );
        
        BondingCurveToken token = BondingCurveToken(payable(tokenAddress));
        
        // Test buying 1 token
        uint256 singleTokenCost = token.getBuyPrice(1);
        vm.deal(buyer, singleTokenCost + 1 ether);
        vm.prank(buyer);
        token.buyTokens{value: singleTokenCost}(1);
        
        assertEq(token.totalSupply(), 1);
        assertEq(token.balanceOf(buyer), 1);
        assertEq(token.getCurrentPrice(), BASE_PRICE + SLOPE);
        
        // Test selling 1 token
        vm.prank(buyer);
        token.sellTokens(1);
        
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(buyer), 0);
        assertEq(token.getCurrentPrice(), BASE_PRICE);
        
        // Test buying 0 tokens (should revert)
        vm.prank(buyer);
        vm.expectRevert("Amount must be greater than 0");
        token.buyTokens{value: 0}(0);
        
        // Test selling 0 tokens (should revert)
        vm.prank(buyer);
        vm.expectRevert("Amount must be greater than 0");
        token.sellTokens(0);
        
        // Test selling more tokens than available (should revert)
        vm.deal(buyer, singleTokenCost + 1 ether);
        vm.prank(buyer);
        token.buyTokens{value: singleTokenCost}(1);
        
        vm.prank(buyer);
        vm.expectRevert("Insufficient token balance");
        token.sellTokens(2);
    }
    
    function testBondingCurveMathematicalAccuracy() public {
        // Create token with simple parameters for easy calculation
        uint256 simpleSlope = 1e12; // 0.000001 ETH per token
        uint256 simpleBasePrice = 1e12; // 0.000001 ETH
        
        vm.prank(creator);
        address tokenAddress = factory.createTokenWithCustomThreshold{value: CREATION_FEE}(
            "Math Test Token", "MTT", simpleSlope, simpleBasePrice, 100 ether
        );
        
        BondingCurveToken token = BondingCurveToken(payable(tokenAddress));
        
        // Test mathematical accuracy with known values
        uint256 amount = 100;
        
        // Expected cost calculation: basePrice * amount + slope * currentSupply * amount + slope * amount * (amount - 1) / 2
        uint256 expectedCost = simpleBasePrice * amount + simpleSlope * 0 * amount + simpleSlope * amount * (amount - 1) / 2;
        uint256 actualCost = token.getBuyPrice(amount);
        
        assertEq(actualCost, expectedCost);
        
        // Buy tokens and test sell price calculation
        vm.deal(buyer, actualCost + 1 ether);
        vm.prank(buyer);
        token.buyTokens{value: actualCost}(amount);
        
        // Test sell price calculation
        uint256 sellAmount = 50;
        uint256 newSupply = amount - sellAmount;
        
        // Expected sell price: basePrice * sellAmount + slope * newSupply * sellAmount + slope * sellAmount * (sellAmount - 1) / 2
        uint256 expectedSellPrice = simpleBasePrice * sellAmount + simpleSlope * newSupply * sellAmount + simpleSlope * sellAmount * (sellAmount - 1) / 2;
        uint256 actualSellPrice = token.getSellPrice(sellAmount);
        
        assertEq(actualSellPrice, expectedSellPrice);
    }
    
    function testBondingCurveGraduationBasics() public {
        // Create token with high graduation threshold for testing
        vm.prank(creator);
        address tokenAddress = factory.createTokenWithCustomThreshold{value: CREATION_FEE}(
            "Graduation Test Token", "GTT", SLOPE, BASE_PRICE, 1000 ether
        );
        
        BondingCurveToken token = BondingCurveToken(payable(tokenAddress));
        
        // Test initial graduation progress
        (uint256 initialProgress, uint256 initialRemaining) = token.getGraduationProgress();
        assertEq(initialProgress, 0);
        assertEq(initialRemaining, 1000 ether);
        assertFalse(token.hasGraduated());
        
        // Buy tokens to increase market cap
        uint256 buyAmount = 50;
        uint256 buyCost = token.getBuyPrice(buyAmount);
        
        vm.deal(buyer, buyCost + 1 ether);
        vm.prank(buyer);
        token.buyTokens{value: buyCost}(buyAmount);
        
        // Check graduation progress - should have some progress
        (uint256 progress, uint256 remaining) = token.getGraduationProgress();
        assertTrue(progress > 0);
        assertTrue(remaining < 1000 ether);
        
        // Verify market cap calculation
        uint256 marketCap = token.getMarketCap();
        assertTrue(marketCap > 0);
        assertFalse(token.hasGraduated()); // Should not have graduated yet
    }
    
    function testBondingCurveMarketCapCalculation() public {
        // Create token with high graduation threshold to avoid auto-graduation
        vm.prank(creator);
        address tokenAddress = factory.createTokenWithCustomThreshold{value: CREATION_FEE}(
            TOKEN_NAME, TOKEN_SYMBOL, SLOPE, BASE_PRICE, 1000 ether
        );
        
        BondingCurveToken token = BondingCurveToken(payable(tokenAddress));
        
        // Test initial market cap (should be 0)
        assertEq(token.getMarketCap(), 0);
        
        // Buy tokens and test market cap calculation
        uint256 buyAmount = 500;
        uint256 buyCost = token.getBuyPrice(buyAmount);
        
        vm.deal(buyer, buyCost + 1 ether);
        vm.prank(buyer);
        token.buyTokens{value: buyCost}(buyAmount);
        
        // Calculate expected market cap: totalSupply * currentPrice
        uint256 expectedMarketCap = token.totalSupply() * token.getCurrentPrice();
        uint256 actualMarketCap = token.getMarketCap();
        
        assertEq(actualMarketCap, expectedMarketCap);
        
        // Buy more tokens and verify market cap increases
        uint256 additionalAmount = 300;
        uint256 additionalCost = token.getBuyPrice(additionalAmount);
        
        vm.deal(buyer, additionalCost + 1 ether);
        vm.prank(buyer);
        token.buyTokens{value: additionalCost}(additionalAmount);
        
        uint256 newMarketCap = token.getMarketCap();
        assertTrue(newMarketCap > actualMarketCap);
        
        // Verify market cap calculation is still correct
        uint256 expectedNewMarketCap = token.totalSupply() * token.getCurrentPrice();
        assertEq(newMarketCap, expectedNewMarketCap);
    }
}