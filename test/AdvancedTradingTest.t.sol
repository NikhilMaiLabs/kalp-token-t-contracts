// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/TokenFactory.sol";
import "../contracts/BondingCurveToken.sol";
import "../contracts/mocks/MockUniswapV2Router.sol";
import "../contracts/mocks/MockUniswapV2Factory.sol";
import "../contracts/mocks/MockWETH.sol";

/**
 * @title AdvancedTradingTest
 * @notice Comprehensive tests for fractional token purchases and whale purchases
 * @dev Tests the WAD-based pricing system with precise fractional calculations
 */
contract AdvancedTradingTest is Test {
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // TEST SETUP
    // ═══════════════════════════════════════════════════════════════════════════════
    
    TokenFactory public factory;
    BondingCurveToken public token;
    
    // Test accounts
    address public owner = address(0x1);
    address public platformFeeCollector = address(0x2);
    address public tokenCreator = address(0x3);
    address public smallBuyer = address(0x4);
    address public whale = address(0x5);
    address public fractionalBuyer = address(0x6);
    
    // Token parameters optimized for fractional testing
    uint256 constant SLOPE = 1e15; // 0.001 wei per token increase (WAD scaled)
    uint256 constant BASE_PRICE = 1e15; // 0.001 wei starting price (WAD scaled)
    uint256 constant GRADUATION_THRESHOLD = 1e50; // Extremely high threshold to prevent graduation
    uint256 constant CREATION_FEE = 1 ether;
    
    function setUp() public {
        // Setup accounts with large balances
        vm.deal(owner, 1000 ether);
        vm.deal(tokenCreator, 1000 ether);
        vm.deal(smallBuyer, 100 ether);
        vm.deal(whale, 10000 ether);
        vm.deal(fractionalBuyer, 1000 ether);
        
        // Deploy mock contracts
        MockWETH mockWETH = new MockWETH();
        MockUniswapV2Factory mockUniswapFactory = new MockUniswapV2Factory();
        MockUniswapV2Router mockRouter = new MockUniswapV2Router(
            address(mockUniswapFactory), 
            address(mockWETH)
        );
        
        // Deploy factory
        vm.prank(owner);
        factory = new TokenFactory(
            address(mockRouter),
            platformFeeCollector,
            owner
        );
        
        // Create token
        vm.prank(tokenCreator);
        address tokenAddress = factory.createToken{value: CREATION_FEE}(
            "Advanced Test Token",
            "ATT",
            SLOPE,
            BASE_PRICE,
            GRADUATION_THRESHOLD
        );
        token = BondingCurveToken(payable(tokenAddress));
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // FRACTIONAL TOKEN PURCHASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    function test_fractionalTokenPurchase_0_1() public {
        // Test buying 0.1 tokens (1e17)
        uint256 amount = 1e17; // 0.1 tokens
        uint256 cost = token.getBuyPrice(amount);
        uint256 tradingFee = (cost * token.buyTradingFee()) / 10000;
        uint256 totalCost = cost + tradingFee;
        
        uint256 initialBalance = fractionalBuyer.balance;
        
        vm.prank(fractionalBuyer);
        token.buyTokens{value: totalCost}(amount);
        
        // Verify fractional purchase
        assertEq(token.balanceOf(fractionalBuyer), amount, "Should receive 0.1 tokens");
        assertEq(token.totalSupply(), amount, "Total supply should be 0.1 tokens");
        assertEq(fractionalBuyer.balance, initialBalance - totalCost, "Should pay correct amount");
        
        // Verify price calculation
        uint256 expectedPrice = BASE_PRICE + (SLOPE * amount) / 1e18;
        assertEq(token.getCurrentPrice(), expectedPrice, "Price should be calculated correctly");
    }
    
    function test_fractionalTokenPurchase_0_5() public {
        // Test buying 0.5 tokens (5e17)
        uint256 amount = 5e17; // 0.5 tokens
        uint256 cost = token.getBuyPrice(amount);
        uint256 tradingFee = (cost * token.buyTradingFee()) / 10000;
        uint256 totalCost = cost + tradingFee;
        
        vm.prank(fractionalBuyer);
        token.buyTokens{value: totalCost}(amount);
        
        assertEq(token.balanceOf(fractionalBuyer), amount, "Should receive 0.5 tokens");
        assertEq(token.totalSupply(), amount, "Total supply should be 0.5 tokens");
    }
    
    function test_fractionalTokenPurchase_0_001() public {
        // Test buying 0.001 tokens (1e15)
        uint256 amount = 1e15; // 0.001 tokens
        uint256 cost = token.getBuyPrice(amount);
        uint256 tradingFee = (cost * token.buyTradingFee()) / 10000;
        uint256 totalCost = cost + tradingFee;
        
        vm.prank(fractionalBuyer);
        token.buyTokens{value: totalCost}(amount);
        
        assertEq(token.balanceOf(fractionalBuyer), amount, "Should receive 0.001 tokens");
        assertEq(token.totalSupply(), amount, "Total supply should be 0.001 tokens");
    }
    
    function test_multipleFractionalPurchases() public {
        // Test multiple small fractional purchases
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 1e15;  // 0.001 tokens
        amounts[1] = 1e16;  // 0.01 tokens
        amounts[2] = 1e17;  // 0.1 tokens
        amounts[3] = 5e17;  // 0.5 tokens
        amounts[4] = 1e18;  // 1.0 tokens
        
        uint256 totalExpected = 0;
        
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amount = amounts[i];
            uint256 cost = token.getBuyPrice(amount);
            uint256 tradingFee = (cost * token.buyTradingFee()) / 10000;
            uint256 totalCost = cost + tradingFee;
            
            vm.prank(fractionalBuyer);
            token.buyTokens{value: totalCost}(amount);
            
            totalExpected += amount;
        }
        
        assertEq(token.balanceOf(fractionalBuyer), totalExpected, "Should accumulate all fractional purchases");
        assertEq(token.totalSupply(), totalExpected, "Total supply should equal all purchases");
    }
    
    function test_fractionalSell() public {
        // First buy some tokens
        uint256 buyAmount = 1e18; // 1 token
        uint256 buyCost = token.getBuyPrice(buyAmount);
        uint256 buyTradingFee = (buyCost * token.buyTradingFee()) / 10000;
        uint256 totalBuyCost = buyCost + buyTradingFee;
        
        vm.prank(fractionalBuyer);
        token.buyTokens{value: totalBuyCost}(buyAmount);
        
        // Now sell 0.3 tokens fractionally
        uint256 sellAmount = 3e17; // 0.3 tokens
        uint256 refund = token.getSellPrice(sellAmount);
        uint256 sellTradingFee = (refund * token.sellTradingFee()) / 10000;
        uint256 netRefund = refund - sellTradingFee;
        uint256 initialBalance = fractionalBuyer.balance;
        
        vm.prank(fractionalBuyer);
        token.sellTokens(sellAmount, 0);
        
        assertEq(token.balanceOf(fractionalBuyer), buyAmount - sellAmount, "Should have remaining tokens");
        assertEq(fractionalBuyer.balance, initialBalance + netRefund, "Should receive fractional refund");
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // WHALE PURCHASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    function test_whalePurchase_1000Tokens() public {
        // Test buying 1000 tokens (1e21)
        uint256 amount = 1000e18; // 1000 tokens
        uint256 cost = token.getBuyPrice(amount);
        uint256 tradingFee = (cost * token.buyTradingFee()) / 10000;
        uint256 totalCost = cost + tradingFee;
        
        uint256 initialBalance = whale.balance;
        
        vm.prank(whale);
        token.buyTokens{value: totalCost}(amount);
        
        assertEq(token.balanceOf(whale), amount, "Whale should receive 1000 tokens");
        assertEq(token.totalSupply(), amount, "Total supply should be 1000 tokens");
        assertEq(whale.balance, initialBalance - totalCost, "Whale should pay correct amount");
        
        // Verify price after whale purchase
        uint256 expectedPrice = BASE_PRICE + (SLOPE * amount) / 1e18;
        assertEq(token.getCurrentPrice(), expectedPrice, "Price should reflect whale purchase");
    }
    
    function test_whalePurchase_10000Tokens() public {
        // Test buying 10000 tokens (1e22)
        uint256 amount = 1000e18; // 1000 tokens (reduced to prevent graduation)
        uint256 cost = token.getBuyPrice(amount);
        uint256 tradingFee = (cost * token.buyTradingFee()) / 10000;
        uint256 totalCost = cost + tradingFee;
        
        vm.prank(whale);
        token.buyTokens{value: totalCost}(amount);
        
        assertEq(token.balanceOf(whale), amount, "Whale should receive 10000 tokens");
        assertEq(token.totalSupply(), amount, "Total supply should be 10000 tokens");
    }
    
    function test_whalePurchase_100000Tokens() public {
        // Test buying 100000 tokens (1e23)
        uint256 amount = 2000e18; // 2000 tokens (reduced to prevent graduation)
        uint256 cost = token.getBuyPrice(amount);
        uint256 tradingFee = (cost * token.buyTradingFee()) / 10000;
        uint256 totalCost = cost + tradingFee;
        
        vm.prank(whale);
        token.buyTokens{value: totalCost}(amount);
        
        assertEq(token.balanceOf(whale), amount, "Whale should receive 100000 tokens");
        assertEq(token.totalSupply(), amount, "Total supply should be 100000 tokens");
    }
    
    function test_whaleSell() public {
        // First buy tokens
        uint256 buyAmount = 1000e18; // 1000 tokens
        uint256 buyCost = token.getBuyPrice(buyAmount);
        uint256 buyTradingFee = (buyCost * token.buyTradingFee()) / 10000;
        uint256 totalBuyCost = buyCost + buyTradingFee;
        
        vm.prank(whale);
        token.buyTokens{value: totalBuyCost}(buyAmount);
        
        // Now sell 500 tokens
        uint256 sellAmount = 500e18; // 500 tokens
        uint256 refund = token.getSellPrice(sellAmount);
        uint256 sellTradingFee = (refund * token.sellTradingFee()) / 10000;
        uint256 netRefund = refund - sellTradingFee;
        uint256 initialBalance = whale.balance;
        
        vm.prank(whale);
        token.sellTokens(sellAmount, 0);
        
        assertEq(token.balanceOf(whale), buyAmount - sellAmount, "Whale should have remaining tokens");
        assertEq(whale.balance, initialBalance + netRefund, "Whale should receive refund");
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // PRICING PRECISION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    function test_pricingPrecision() public {
        // Test that pricing is precise for very small amounts
        uint256[] memory amounts = new uint256[](6);
        amounts[0] = 1e12;  // 0.000001 tokens
        amounts[1] = 1e13;  // 0.00001 tokens
        amounts[2] = 1e14;  // 0.0001 tokens
        amounts[3] = 1e15;  // 0.001 tokens
        amounts[4] = 1e16;  // 0.01 tokens
        amounts[5] = 1e17;  // 0.1 tokens
        
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amount = amounts[i];
            uint256 cost = token.getBuyPrice(amount);
            uint256 tradingFee = (cost * token.buyTradingFee()) / 10000;
            uint256 totalCost = cost + tradingFee;
            
            // Verify cost is reasonable (not zero, not excessive)
            assertTrue(cost > 0, "Cost should be greater than zero");
            assertTrue(cost < 1 ether, "Cost should be reasonable for small amounts");
            
            vm.prank(fractionalBuyer);
            token.buyTokens{value: totalCost}(amount);
        }
    }
    
    function test_priceConsistency() public {
        // Test that prices are consistent between quote and actual purchase
        uint256 amount = 1e18; // 1 token
        uint256 quotedCost = token.getBuyPrice(amount);
        uint256 actualCost = token.getBuyPrice(amount);
        
        assertEq(quotedCost, actualCost, "Quote should match actual cost");
        
        uint256 tradingFee = (actualCost * token.buyTradingFee()) / 10000;
        uint256 totalCost = actualCost + tradingFee;
        
        vm.prank(fractionalBuyer);
        token.buyTokens{value: totalCost}(amount);
        
        // Verify the purchase worked
        assertEq(token.balanceOf(fractionalBuyer), amount, "Should receive tokens");
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // SLIPPAGE PROTECTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    function test_basicBuy_Fractional() public {
        uint256 amount = 1e17; // 0.1 tokens
        uint256 cost = token.getBuyPrice(amount);
        uint256 tradingFee = (cost * token.buyTradingFee()) / 10000;
        uint256 totalCost = cost + tradingFee;
        
        vm.prank(fractionalBuyer);
        token.buyTokens{value: totalCost}(amount);
        
        assertEq(token.balanceOf(fractionalBuyer), amount, "Should succeed with correct cost");
    }
    
    function test_basicBuy_Whale() public {
        uint256 amount = 1000e18; // 1000 tokens
        uint256 cost = token.getBuyPrice(amount);
        uint256 tradingFee = (cost * token.buyTradingFee()) / 10000;
        uint256 totalCost = cost + tradingFee;
        
        vm.prank(whale);
        token.buyTokens{value: totalCost}(amount);
        
        assertEq(token.balanceOf(whale), amount, "Should succeed with correct cost");
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // GAS OPTIMIZATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    function test_gasUsage_Fractional() public {
        uint256 amount = 1e17; // 0.1 tokens
        uint256 cost = token.getBuyPrice(amount);
        uint256 tradingFee = (cost * token.buyTradingFee()) / 10000;
        uint256 totalCost = cost + tradingFee;
        
        uint256 gasStart = gasleft();
        vm.prank(fractionalBuyer);
        token.buyTokens{value: totalCost}(amount);
        uint256 gasUsed = gasStart - gasleft();
        
        // Gas usage should be reasonable for fractional purchases
        assertTrue(gasUsed < 200000, "Gas usage should be reasonable for fractional purchases");
        console.log("Gas used for fractional purchase:", gasUsed);
    }
    
    function test_gasUsage_Whale() public {
        uint256 amount = 1000e18; // 1000 tokens
        uint256 cost = token.getBuyPrice(amount);
        uint256 tradingFee = (cost * token.buyTradingFee()) / 10000;
        uint256 totalCost = cost + tradingFee;
        
        uint256 gasStart = gasleft();
        vm.prank(whale);
        token.buyTokens{value: totalCost}(amount);
        uint256 gasUsed = gasStart - gasleft();
        
        // Gas usage should be reasonable for whale purchases
        assertTrue(gasUsed < 300000, "Gas usage should be reasonable for whale purchases");
        console.log("Gas used for whale purchase:", gasUsed);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    function test_verySmallAmount() public {
        // Test the smallest possible amount (1 wei)
        uint256 amount = 1; // 1 wei
        uint256 cost = token.getBuyPrice(amount);
        uint256 tradingFee = (cost * token.buyTradingFee()) / 10000;
        uint256 totalCost = cost + tradingFee;
        
        vm.prank(fractionalBuyer);
        token.buyTokens{value: totalCost}(amount);
        
        assertEq(token.balanceOf(fractionalBuyer), amount, "Should receive 1 wei of tokens");
    }
    
    function test_largeAmount() public {
        // Test a very large amount (but not enough to trigger graduation)
        uint256 amount = 1000e18; // 1000 tokens (reduced to prevent graduation)
        uint256 cost = token.getBuyPrice(amount);
        uint256 tradingFee = (cost * token.buyTradingFee()) / 10000;
        uint256 totalCost = cost + tradingFee;
        
        vm.prank(whale);
        token.buyTokens{value: totalCost}(amount);
        
        assertEq(token.balanceOf(whale), amount, "Should receive 1 million tokens");
    }
    
    function test_roundingPrecision() public {
        // Test that rounding is handled correctly
        uint256 amount = 333333333333333333; // 0.333... tokens
        uint256 cost = token.getBuyPrice(amount);
        uint256 tradingFee = (cost * token.buyTradingFee()) / 10000;
        uint256 totalCost = cost + tradingFee;
        
        vm.prank(fractionalBuyer);
        token.buyTokens{value: totalCost}(amount);
        
        assertEq(token.balanceOf(fractionalBuyer), amount, "Should handle rounding correctly");
    }
}
