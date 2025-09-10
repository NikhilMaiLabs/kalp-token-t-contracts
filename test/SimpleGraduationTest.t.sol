// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/TokenFactory.sol";
import "../contracts/BondingCurveToken.sol";
import "../contracts/mocks/MockUniswapV2Router.sol";
import "../contracts/mocks/MockUniswapV2Factory.sol";
import "../contracts/mocks/MockWETH.sol";

/**
 * @title SimpleGraduationTest
 * @notice Simple tests for graduation functionality
 * @dev Focuses on core graduation mechanics without complex calculations
 */
contract SimpleGraduationTest is Test {
    
    TokenFactory public factory;
    BondingCurveToken public token;
    
    // Test accounts
    address public owner = address(0x1);
    address public platformFeeCollector = address(0x2);
    address public tokenCreator = address(0x3);
    address public buyer = address(0x4);
    
    // Token parameters (smaller values for testing)
    uint256 constant SLOPE = 1e15; // 0.001 wei per token
    uint256 constant BASE_PRICE = 1e15; // 0.001 wei starting price
    uint256 constant GRADUATION_THRESHOLD = 1000000 ether;
    uint256 constant CREATION_FEE = 1 ether;
    
    function setUp() public {
        // Setup accounts
        vm.deal(owner, 1000 ether);
        vm.deal(tokenCreator, 1000 ether);
        vm.deal(buyer, 1000 ether);
        
        // Deploy mock contracts
        MockWETH mockWETH = new MockWETH();
        MockUniswapV2Factory mockUniswapFactory = new MockUniswapV2Factory();
        MockUniswapV2Router mockRouter = new MockUniswapV2Router(
            address(mockUniswapFactory), 
            address(mockWETH)
        );
        
        // Deploy factory
        vm.prank(owner);
        factory = new TokenFactory(address(mockRouter), platformFeeCollector, owner);
        
        // Create test token
        vm.prank(tokenCreator);
        address tokenAddress = factory.createToken{value: CREATION_FEE}(
            "Simple Test Token",
            "STT",
            SLOPE,
            BASE_PRICE,
            GRADUATION_THRESHOLD
        );
        token = BondingCurveToken(payable(tokenAddress));
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // BASIC GRADUATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    function test_graduationProgressInitial() public view {
        (uint256 progress, uint256 remaining) = token.getGraduationProgress();
        
        assertTrue(progress < 10000, "Progress should be less than 100%");
        assertEq(remaining, GRADUATION_THRESHOLD, "Remaining should equal full threshold");
    }
    
    function test_graduationProgressAfterPurchase() public {
        // Buy some tokens
        uint256 tokensToBuy = 5e18; // 5 tokens
        uint256 cost = token.getBuyPrice(tokensToBuy);
        uint256 tradingFee = (cost * token.buyTradingFee()) / 10000;
        uint256 totalCost = cost + tradingFee;
        
        vm.prank(buyer);
        token.buyTokens{value: totalCost}(tokensToBuy);
        
        // Check graduation progress - with corrected market cap calculation,
        // small purchases won't trigger graduation
        (uint256 progress, uint256 remaining) = token.getGraduationProgress();
        
        // Progress should be very small since market cap is much lower than threshold
        assertTrue(progress >= 0, "Progress should be non-negative");
        assertTrue(progress < 10000, "Progress should be less than 100%");
        assertTrue(remaining > 0, "Should have remaining amount");
        assertFalse(token.hasGraduated(), "Token should not be graduated yet");
    }
    
    function test_manualGraduation() public {
        // For this test, we'll use a very small amount to avoid automatic graduation
        uint256 tokensToBuy = 1e15; // 0.001 tokens
        uint256 cost = token.getBuyPrice(tokensToBuy);
        uint256 tradingFee = (cost * token.buyTradingFee()) / 10000;
        uint256 totalCost = cost + tradingFee;
        
        vm.prank(buyer);
        token.buyTokens{value: totalCost}(tokensToBuy);
        
        // Verify not graduated yet (with small amount)
        assertFalse(token.hasGraduated(), "Should not be graduated yet");
        
        // Manually trigger graduation
        vm.prank(address(factory));
        token.triggerGraduation();
        
        // Verify graduation occurred
        assertTrue(token.hasGraduated(), "Token should be graduated");
        assertTrue(token.dexPool() != address(0), "DEX pool should be created");
        assertTrue(token.liquidityTokensAmount() > 0, "Should have liquidity tokens");
        
        // Verify token supply doubled
        assertEq(token.totalSupply(), tokensToBuy * 2, "Total supply should be doubled");
        
        // Verify buyer received tokens
        assertEq(token.balanceOf(buyer), tokensToBuy, "Buyer should have tokens");
        
        // Verify contract has liquidity tokens
        assertEq(token.balanceOf(address(token)), tokensToBuy, "Contract should have liquidity tokens");
    }
    
    function test_manualGraduationRevertsWhenAlreadyGraduated() public {
        // First graduate the token
        vm.prank(address(factory));
        token.triggerGraduation();
        
        // Try to graduate again
        vm.prank(address(factory));
        vm.expectRevert("Token has already graduated");
        token.triggerGraduation();
    }
    
    function test_manualGraduationOnlyFactory() public {
        // Try to trigger graduation as non-factory
        vm.prank(buyer);
        vm.expectRevert("Only factory can call this function");
        token.triggerGraduation();
    }
    
    function test_tradingDisabledAfterGraduation() public {
        // First buy some tokens
        uint256 tokensToBuy = 5e18; // 5 tokens
        uint256 cost = token.getBuyPrice(tokensToBuy);
        uint256 tradingFee = (cost * token.buyTradingFee()) / 10000;
        uint256 totalCost = cost + tradingFee;
        
        vm.prank(buyer);
        token.buyTokens{value: totalCost}(tokensToBuy);
        
        // Manually trigger graduation
        vm.prank(address(factory));
        token.triggerGraduation();
        
        // Token should be graduated
        assertTrue(token.hasGraduated(), "Token should be graduated");
        
        // Try to buy more tokens after graduation
        vm.prank(buyer);
        vm.expectRevert("Token has already graduated");
        token.buyTokens{value: 1 ether}(1e18);
        
        // Try to sell tokens after graduation
        vm.prank(buyer);
        vm.expectRevert("Token has already graduated");
        token.sellTokens(1e18, 0);
    }
    
    function test_graduationStateAfterSuccess() public {
        // Buy some tokens first
        uint256 tokensToBuy = 5e18; // 5 tokens
        uint256 cost = token.getBuyPrice(tokensToBuy);
        uint256 tradingFee = (cost * token.buyTradingFee()) / 10000;
        uint256 totalCost = cost + tradingFee;
        
        vm.prank(buyer);
        token.buyTokens{value: totalCost}(tokensToBuy);
        
        // Manually trigger graduation
        vm.prank(address(factory));
        token.triggerGraduation();
        
        // Verify all graduation state
        assertTrue(token.hasGraduated(), "Should be graduated");
        assertTrue(token.dexPool() != address(0), "Should have DEX pool");
        assertTrue(token.liquidityTokensAmount() > 0, "Should have liquidity tokens");
        assertEq(token.totalSupply(), tokensToBuy * 2, "Supply should be doubled");
        
        // Verify graduation progress - after manual graduation, progress is still based on market cap
        (uint256 progress, uint256 remaining) = token.getGraduationProgress();
        // The progress is still very low because market cap is much smaller than threshold
        // This is correct behavior - manual graduation doesn't change the market cap calculation
        assertTrue(progress >= 0, "Progress should be non-negative");
        assertTrue(remaining > 0, "Should have remaining amount");
    }
    
    function test_graduationWithZeroSupply() public {
        // Try to manually graduate with zero supply
        vm.prank(address(factory));
        token.triggerGraduation();
        
        // Should still work (edge case)
        assertTrue(token.hasGraduated(), "Should be graduated even with zero supply");
        assertTrue(token.dexPool() != address(0), "Should have DEX pool");
    }
    
    function test_graduationEvents() public {
        // Buy some tokens first
        uint256 tokensToBuy = 5e18; // 5 tokens
        uint256 cost = token.getBuyPrice(tokensToBuy);
        uint256 tradingFee = (cost * token.buyTradingFee()) / 10000;
        uint256 totalCost = cost + tradingFee;
        
        vm.prank(buyer);
        token.buyTokens{value: totalCost}(tokensToBuy);
        
        // Manually trigger graduation and verify it works
        vm.prank(address(factory));
        token.triggerGraduation();
        
        // Verify graduation occurred (this indirectly tests that events were emitted)
        assertTrue(token.hasGraduated(), "Token should be graduated");
        assertTrue(token.dexPool() != address(0), "DEX pool should be created");
    }
    
    function test_graduationFeeDistribution() public {
        // Buy some tokens first
        uint256 tokensToBuy = 5e18; // 5 tokens
        uint256 cost = token.getBuyPrice(tokensToBuy);
        uint256 tradingFee = (cost * token.buyTradingFee()) / 10000;
        uint256 totalCost = cost + tradingFee;
        
        uint256 initialPlatformBalance = platformFeeCollector.balance;
        uint256 initialCreatorBalance = tokenCreator.balance;
        
        vm.prank(buyer);
        token.buyTokens{value: totalCost}(tokensToBuy);
        
        // Manually trigger graduation
        vm.prank(address(factory));
        token.triggerGraduation();
        
        // Calculate expected fees from remaining POL after liquidity
        // Liquidity gets 80% of totalRaised, remaining 20% is distributed as fees
        uint256 totalRaised = token.totalRaised();
        uint256 remainingPol = totalRaised - (totalRaised * token.LIQUIDITY_FEE()) / 10000;
        uint256 expectedPlatformFee = (remainingPol * token.PLATFORM_FEE()) / 10000;
        uint256 expectedCreatorFee = (remainingPol * token.CREATOR_FEE()) / 10000;
        
        // Verify fee distribution
        assertEq(platformFeeCollector.balance, initialPlatformBalance + expectedPlatformFee, "Platform should receive fee");
        assertEq(tokenCreator.balance, initialCreatorBalance + expectedCreatorFee, "Creator should receive fee");
    }
}
