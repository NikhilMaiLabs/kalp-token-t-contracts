// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/TokenFactory.sol";
import "../contracts/BondingCurveToken.sol";
import "../contracts/mocks/MockUniswapV2Router.sol";
import "../contracts/mocks/MockUniswapV2Factory.sol";
import "../contracts/mocks/MockWETH.sol";

/**
 * @title TokenTradingTest
 * @notice Focused tests for token trading, bonding curve mathematics, and critical edge cases
 * @dev Optimized for performance - tests essential functionality efficiently
 */
contract TokenTradingTest is Test {
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // TEST SETUP
    // ═══════════════════════════════════════════════════════════════════════════════
    
    TokenFactory public factory;
    BondingCurveToken public token;
    
    // Test accounts
    address public owner = address(0x1);
    address public platformFeeCollector = address(0x2);
    address public tokenCreator = address(0x3);
    address public buyer = address(0x4);
    address public seller = address(0x5);
    
    // Token parameters
    uint256 constant SLOPE = 1000; // 1000 wei per token increase
    uint256 constant BASE_PRICE = 2000; // 2000 wei starting price
    uint256 constant GRADUATION_THRESHOLD = 100 ether;
    uint256 constant CREATION_FEE = 1 ether;
    
    function setUp() public {
        // Setup accounts
        vm.deal(owner, 100 ether);
        vm.deal(tokenCreator, 100 ether);
        vm.deal(buyer, 100 ether);
        vm.deal(seller, 100 ether);
        
        // Deploy mock contracts
        MockWETH mockWETH = new MockWETH();
        MockUniswapV2Factory mockUniswapFactory = new MockUniswapV2Factory();
        MockUniswapV2Router mockRouter = new MockUniswapV2Router(
            address(mockUniswapFactory), 
            address(mockWETH)
        );
        
        // Deploy factory with mock router
        vm.prank(owner);
        factory = new TokenFactory(address(mockRouter), platformFeeCollector, owner);
        
        // Create test token
        vm.prank(tokenCreator);
        address tokenAddress = factory.createToken{value: CREATION_FEE}(
            "Test Token", "TEST", SLOPE, BASE_PRICE, GRADUATION_THRESHOLD
        );
        
        token = BondingCurveToken(payable(tokenAddress));
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // BONDING CURVE MATH TESTS (Essential)
    // ═══════════════════════════════════════════════════════════════════════════════
    
    function test_initialPrice() public view {
        assertEq(token.getCurrentPrice(), BASE_PRICE, "Initial price should equal base price");
    }
    
    function test_priceIncreasesWithSupply() public {
        // Buy 5 tokens
        uint256 cost = token.getBuyPrice(5);
        vm.prank(buyer);
        token.buyTokens{value: cost}(5);
        
        // Price should increase
        uint256 newPrice = token.getCurrentPrice();
        uint256 expectedPrice = BASE_PRICE + (SLOPE * 5);
        assertEq(newPrice, expectedPrice, "Price should increase by slope * supply");
    }
    
    function test_buyPriceSingleToken() public view {
        uint256 cost = token.getBuyPrice(1);
        assertEq(cost, BASE_PRICE, "First token cost should equal base price");
    }
    
    function test_buyPriceMultipleTokens() public view {
        uint256 amount = 3;
        uint256 cost = token.getBuyPrice(amount);
        
        // Formula: basePrice * amount + slope * 0 * amount + slope * amount * (amount-1) / 2
        uint256 expected = BASE_PRICE * amount + SLOPE * amount * (amount - 1) / 2;
        assertEq(cost, expected, "Multi-token cost should follow integration formula");
    }
    
    function test_marketCapCalculation() public {
        // Buy tokens
        uint256 tokensToBuy = 10;
        uint256 cost = token.getBuyPrice(tokensToBuy);
        vm.prank(buyer);
        token.buyTokens{value: cost}(tokensToBuy);
        
        uint256 marketCap = token.getMarketCap();
        uint256 expected = token.totalSupply() * token.getCurrentPrice();
        assertEq(marketCap, expected, "Market cap should equal supply * price");
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // BUY FUNCTIONALITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    function test_buyTokensSuccess() public {
        uint256 tokensToBuy = 5;
        uint256 cost = token.getBuyPrice(tokensToBuy);
        
        vm.prank(buyer);
        token.buyTokens{value: cost}(tokensToBuy);
        
        assertEq(token.balanceOf(buyer), tokensToBuy, "Buyer should receive tokens");
        assertEq(token.totalSupply(), tokensToBuy, "Supply should increase");
        assertEq(token.totalRaised(), cost, "Total raised should equal cost");
    }
    
    function test_buyTokensExcessRefunded() public {
        uint256 tokensToBuy = 3;
        uint256 cost = token.getBuyPrice(tokensToBuy);
        uint256 excess = 1 ether;
        uint256 initialBalance = buyer.balance;
        
        vm.prank(buyer);
        token.buyTokens{value: cost + excess}(tokensToBuy);
        
        uint256 expectedBalance = initialBalance - cost;
        assertEq(buyer.balance, expectedBalance, "Excess should be refunded");
    }
    
    function test_buyTokensWithFee() public {
        // Set 5% buy fee
        vm.prank(address(factory));
        token.updateTradingFees(500, 0);
        
        uint256 tokensToBuy = 5;
        uint256 cost = token.getBuyPrice(tokensToBuy);
        uint256 fee = (cost * 500) / 10000;
        uint256 initialPlatformBalance = platformFeeCollector.balance;
        
        vm.prank(buyer);
        token.buyTokens{value: cost + fee}(tokensToBuy);
        
        assertEq(token.balanceOf(buyer), tokensToBuy, "Buyer should receive tokens");
        assertEq(
            platformFeeCollector.balance, 
            initialPlatformBalance + fee, 
            "Platform should receive fee"
        );
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // SELL FUNCTIONALITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    function test_sellTokensSuccess() public {
        // Buy tokens first
        uint256 tokensToBuy = 10;
        uint256 buyCost = token.getBuyPrice(tokensToBuy);
        vm.prank(buyer);
        token.buyTokens{value: buyCost}(tokensToBuy);
        
        // Sell half
        uint256 tokensToSell = 5;
        uint256 refund = token.getSellPrice(tokensToSell);
        uint256 initialBalance = buyer.balance;
        
        vm.prank(buyer);
        token.sellTokens(tokensToSell);
        
        assertEq(token.balanceOf(buyer), tokensToBuy - tokensToSell, "Tokens should be burned");
        assertEq(buyer.balance, initialBalance + refund, "Should receive refund");
        assertEq(token.totalSupply(), tokensToBuy - tokensToSell, "Supply should decrease");
    }
    
    function test_sellTokensWithFee() public {
        // Set 3% sell fee
        vm.prank(address(factory));
        token.updateTradingFees(0, 300);
        
        // Buy tokens first
        uint256 tokensToBuy = 8;
        uint256 buyCost = token.getBuyPrice(tokensToBuy);
        vm.prank(buyer);
        token.buyTokens{value: buyCost}(tokensToBuy);
        
        // Sell tokens
        uint256 tokensToSell = 4;
        uint256 refund = token.getSellPrice(tokensToSell);
        uint256 fee = (refund * 300) / 10000;
        uint256 netRefund = refund - fee;
        uint256 initialBalance = buyer.balance;
        uint256 initialPlatformBalance = platformFeeCollector.balance;
        
        vm.prank(buyer);
        token.sellTokens(tokensToSell);
        
        assertEq(buyer.balance, initialBalance + netRefund, "Should receive net refund");
        assertEq(
            platformFeeCollector.balance,
            initialPlatformBalance + fee,
            "Platform should receive sell fee"
        );
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // CRITICAL EDGE CASES
    // ═══════════════════════════════════════════════════════════════════════════════
    
    function test_buyZeroTokensReverts() public {
        vm.prank(buyer);
        vm.expectRevert("Amount must be greater than 0");
        token.buyTokens{value: 1 ether}(0);
    }
    
    function test_buyInsufficientPaymentReverts() public {
        uint256 cost = token.getBuyPrice(5);
        vm.prank(buyer);
        vm.expectRevert("Insufficient POL sent");
        token.buyTokens{value: cost - 1}(5);
    }
    
    function test_sellZeroTokensReverts() public {
        vm.prank(buyer);
        vm.expectRevert("Amount must be greater than 0");
        token.sellTokens(0);
    }
    
    function test_sellMoreThanBalanceReverts() public {
        // Buy 5 tokens
        uint256 cost = token.getBuyPrice(5);
        vm.prank(buyer);
        token.buyTokens{value: cost}(5);
        
        // Try to sell 6 tokens
        vm.prank(buyer);
        vm.expectRevert("Insufficient token balance");
        token.sellTokens(6);
    }
    
    function test_buyWhenPausedReverts() public {
        vm.prank(tokenCreator);
        token.pause();
        
        uint256 cost = token.getBuyPrice(5);
        vm.prank(buyer);
        vm.expectRevert();
        token.buyTokens{value: cost}(5);
    }
    
    function test_sellWhenPausedReverts() public {
        // Buy tokens first
        uint256 cost = token.getBuyPrice(5);
        vm.prank(buyer);
        token.buyTokens{value: cost}(5);
        
        // Pause and try to sell
        vm.prank(tokenCreator);
        token.pause();
        
        vm.prank(buyer);
        vm.expectRevert();
        token.sellTokens(5);
    }
    
    function test_buyBlacklistedReverts() public {
        vm.prank(tokenCreator);
        token.blockAccount(buyer);
        
        uint256 cost = token.getBuyPrice(5);
        vm.prank(buyer);
        vm.expectRevert("BlackList: Recipient account is blocked");
        token.buyTokens{value: cost}(5);
    }
    
    function test_sellBlacklistedReverts() public {
        // Buy tokens first
        uint256 cost = token.getBuyPrice(5);
        vm.prank(buyer);
        token.buyTokens{value: cost}(5);
        
        // Blacklist and try to sell
        vm.prank(tokenCreator);
        token.blockAccount(buyer);
        
        vm.prank(buyer);
        vm.expectRevert("BlackList: Sender account is blocked");
        token.sellTokens(5);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // GRADUATION MECHANICS (Simplified)
    // ═══════════════════════════════════════════════════════════════════════════════
    
    function test_graduationProgress() public view {
        (uint256 progress, uint256 remaining) = token.getGraduationProgress();
        
        assertTrue(progress < 10000, "Progress should be less than 100%");
        assertEq(remaining, GRADUATION_THRESHOLD, "Remaining should equal full threshold initially");
    }
    
    function test_manualGraduation() public {
        // Force graduation
        vm.prank(address(factory));
        token.triggerGraduation();
        
        assertTrue(token.hasGraduated(), "Token should be graduated");
    }
    
    function test_tradingDisabledAfterGraduation() public {
        // Graduate token
        vm.prank(address(factory));
        token.triggerGraduation();
        
        uint256 cost = token.getBuyPrice(5);
        vm.prank(buyer);
        vm.expectRevert("Token has already graduated");
        token.buyTokens{value: cost}(5);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // INFO FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    function test_getTokenInfo() public {
        // Buy some tokens to change state
        uint256 tokensToBuy = 7;
        uint256 cost = token.getBuyPrice(tokensToBuy);
        vm.prank(buyer);
        token.buyTokens{value: cost}(tokensToBuy);
        
        (
            uint256 currentPrice,
            uint256 currentSupply,
            uint256 marketCap,
            uint256 graduationProgress,
            uint256 remainingForGraduation,
            bool graduated,
            address pairAddress
        ) = token.getTokenInfo();
        
        assertEq(currentPrice, token.getCurrentPrice(), "Price should match");
        assertEq(currentSupply, token.totalSupply(), "Supply should match");
        assertEq(marketCap, token.getMarketCap(), "Market cap should match");
        assertEq(graduated, false, "Should not be graduated");
        assertEq(pairAddress, address(0), "No pair initially");
        assertTrue(remainingForGraduation > 0, "Should have remaining amount");
        assertTrue(graduationProgress >= 0, "Should have valid graduation progress");
    }
    
    function test_getTradingFees() public view {
        (uint256 buyFee, uint256 sellFee) = token.getTradingFees();
        assertEq(buyFee, 0, "Initial buy fee should be 0");
        assertEq(sellFee, 0, "Initial sell fee should be 0");
    }
}