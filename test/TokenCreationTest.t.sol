// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/TokenFactory.sol";
import "../contracts/BondingCurveToken.sol";

// Mock contracts for testing
contract MockUniswapV2Router {
    address public immutable factory;
    address public immutable WETH;
    
    constructor(address _factory, address _weth) {
        factory = _factory;
        WETH = _weth;
    }
    
    function addLiquidityETH(
        address /* token */,
        uint amountTokenDesired,
        uint /* amountTokenMin */,
        uint /* amountETHMin */,
        address /* to */,
        uint /* deadline */
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity) {
        return (amountTokenDesired, msg.value, 1000);
    }
}

contract MockUniswapV2Factory {
    mapping(address => mapping(address => address)) public getPair;
    
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        pair = address(new MockUniswapV2Pair());
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair;
        return pair;
    }
}

contract MockUniswapV2Pair {
    // Empty mock pair contract
}

contract MockWETH {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;
}

/**
 * @title TokenCreationTest
 * @notice Comprehensive tests for token creation functionality and edge cases
 * @dev Tests both successful scenarios and failure cases with proper validation
 */
contract TokenCreationTest is Test {
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // TEST SETUP AND FIXTURES
    // ═══════════════════════════════════════════════════════════════════════════════
    
    TokenFactory public factory;
    MockUniswapV2Router public mockRouter;
    MockUniswapV2Factory public mockUniswapFactory;
    MockWETH public mockWETH;
    
    // Test accounts
    address public owner = address(0x1);
    address public platformFeeCollector = address(0x2);
    address public tokenCreator = address(0x3);
    address public user1 = address(0x4);
    address public user2 = address(0x5);
    
    // Default token parameters for testing
    string constant DEFAULT_NAME = "Test Token";
    string constant DEFAULT_SYMBOL = "TEST";
    uint256 constant DEFAULT_SLOPE = 1000; // 1000 wei per token increase
    uint256 constant DEFAULT_BASE_PRICE = 1000; // 1000 wei starting price
    uint256 constant DEFAULT_GRADUATION_THRESHOLD = 1000 ether; // 1000 ETH market cap
    uint256 constant DEFAULT_CREATION_FEE = 1 ether; // 1 ETH creation fee
    
    // Events for testing
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
    
    function setUp() public {
        // Deploy mock contracts
        mockWETH = new MockWETH();
        mockUniswapFactory = new MockUniswapV2Factory();
        mockRouter = new MockUniswapV2Router(address(mockUniswapFactory), address(mockWETH));
        
        // Deploy factory with owner
        vm.prank(owner);
        factory = new TokenFactory(address(mockRouter), platformFeeCollector, owner);
        
        // Setup test accounts with ETH
        vm.deal(owner, 100 ether);
        vm.deal(tokenCreator, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // SUCCESSFUL TOKEN CREATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Test successful token creation with default parameters
     * @dev Verifies token deployment, event emission, and proper setup
     */
    function test_CreateToken_Success() public {
        vm.startPrank(tokenCreator);
        
        // Expect TokenCreated event (check indexed parameters and data)
        vm.expectEmit(false, true, false, true); // Skip token address check but check creator and data
        emit TokenCreated(
            address(0), // Token address will be different, so we skip checking it
            DEFAULT_NAME,
            DEFAULT_SYMBOL,
            DEFAULT_SLOPE,
            DEFAULT_BASE_PRICE,
            DEFAULT_GRADUATION_THRESHOLD,
            tokenCreator,
            DEFAULT_CREATION_FEE
        );
        
        // Create token with creation fee
        address tokenAddress = factory.createToken{value: DEFAULT_CREATION_FEE}(
            DEFAULT_NAME,
            DEFAULT_SYMBOL,
            DEFAULT_SLOPE,
            DEFAULT_BASE_PRICE,
            DEFAULT_GRADUATION_THRESHOLD
        );
        
        vm.stopPrank();
        
        // Verify token was created successfully
        assertTrue(tokenAddress != address(0), "Token address should not be zero");
        assertTrue(factory.isTokenCreated(tokenAddress), "Token should be marked as created");
        
        // Verify token count increased
        assertEq(factory.getTokenCount(), 1, "Token count should be 1");
        
        // Verify token info is stored correctly
        TokenFactory.TokenInfo memory tokenInfo = factory.getTokenInfo(tokenAddress);
        assertEq(tokenInfo.name, DEFAULT_NAME, "Name should match");
        assertEq(tokenInfo.symbol, DEFAULT_SYMBOL, "Symbol should match");
        assertEq(tokenInfo.slope, DEFAULT_SLOPE, "Slope should match");
        assertEq(tokenInfo.basePrice, DEFAULT_BASE_PRICE, "Base price should match");
        assertEq(tokenInfo.graduationThreshold, DEFAULT_GRADUATION_THRESHOLD, "Graduation threshold should match");
        assertEq(tokenInfo.creator, tokenCreator, "Creator should match");
        assertFalse(tokenInfo.hasGraduated, "Should not be graduated initially");
        assertEq(tokenInfo.dexPair, address(0), "DEX pair should be zero initially");
        
        // Verify creator tokens tracking
        address[] memory creatorTokens = factory.getCreatorTokens(tokenCreator);
        assertEq(creatorTokens.length, 1, "Creator should have 1 token");
        assertEq(creatorTokens[0], tokenAddress, "Creator's first token should match");
        
        // Verify factory collected creation fee
        assertEq(factory.totalFeesCollected(), DEFAULT_CREATION_FEE, "Factory should have collected creation fee");
    }
    
    /**
     * @notice Test token creation with custom graduation threshold
     * @dev Verifies that custom thresholds are properly set
     */
    function test_CreateToken_CustomGraduationThreshold() public {
        uint256 customThreshold = 5000 ether;
        
        vm.prank(tokenCreator);
        address tokenAddress = factory.createToken{value: DEFAULT_CREATION_FEE}(
            DEFAULT_NAME,
            DEFAULT_SYMBOL,
            DEFAULT_SLOPE,
            DEFAULT_BASE_PRICE,
            customThreshold
        );
        
        TokenFactory.TokenInfo memory tokenInfo = factory.getTokenInfo(tokenAddress);
        assertEq(tokenInfo.graduationThreshold, customThreshold, "Custom graduation threshold should be set");
    }
    
    /**
     * @notice Test multiple token creation by same creator
     * @dev Verifies proper tracking of multiple tokens per creator
     */
    function test_CreateToken_MultipleTokensBySameCreator() public {
        vm.startPrank(tokenCreator);
        
        // Create first token
        address token1 = factory.createToken{value: DEFAULT_CREATION_FEE}(
            "Token One",
            "TOK1",
            DEFAULT_SLOPE,
            DEFAULT_BASE_PRICE,
            DEFAULT_GRADUATION_THRESHOLD
        );
        
        // Create second token
        address token2 = factory.createToken{value: DEFAULT_CREATION_FEE}(
            "Token Two",
            "TOK2",
            DEFAULT_SLOPE * 2,
            DEFAULT_BASE_PRICE * 2,
            DEFAULT_GRADUATION_THRESHOLD * 2
        );
        
        vm.stopPrank();
        
        // Verify both tokens exist
        assertTrue(factory.isTokenCreated(token1), "First token should exist");
        assertTrue(factory.isTokenCreated(token2), "Second token should exist");
        assertEq(factory.getTokenCount(), 2, "Should have 2 tokens total");
        
        // Verify creator tracking
        address[] memory creatorTokens = factory.getCreatorTokens(tokenCreator);
        assertEq(creatorTokens.length, 2, "Creator should have 2 tokens");
        assertEq(creatorTokens[0], token1, "First token should match");
        assertEq(creatorTokens[1], token2, "Second token should match");
    }
    
    /**
     * @notice Test token creation with excess payment
     * @dev Verifies that excess ETH is properly refunded
     */
    function test_CreateToken_ExcessPaymentRefunded() public {
        uint256 excessPayment = DEFAULT_CREATION_FEE + 2 ether;
        uint256 initialBalance = tokenCreator.balance;
        
        vm.prank(tokenCreator);
        factory.createToken{value: excessPayment}(
            DEFAULT_NAME,
            DEFAULT_SYMBOL,
            DEFAULT_SLOPE,
            DEFAULT_BASE_PRICE,
            DEFAULT_GRADUATION_THRESHOLD
        );
        
        // Verify excess was refunded
        uint256 expectedBalance = initialBalance - DEFAULT_CREATION_FEE;
        assertEq(tokenCreator.balance, expectedBalance, "Excess payment should be refunded");
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // EDGE CASES AND VALIDATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Test token creation with empty name
     * @dev Should revert with appropriate error message
     */
    function test_CreateToken_EmptyName_Reverts() public {
        vm.prank(tokenCreator);
        vm.expectRevert("Name cannot be empty");
        factory.createToken{value: DEFAULT_CREATION_FEE}(
            "", // Empty name
            DEFAULT_SYMBOL,
            DEFAULT_SLOPE,
            DEFAULT_BASE_PRICE,
            DEFAULT_GRADUATION_THRESHOLD
        );
    }
    
    /**
     * @notice Test token creation with empty symbol
     * @dev Should revert with appropriate error message
     */
    function test_CreateToken_EmptySymbol_Reverts() public {
        vm.prank(tokenCreator);
        vm.expectRevert("Symbol cannot be empty");
        factory.createToken{value: DEFAULT_CREATION_FEE}(
            DEFAULT_NAME,
            "", // Empty symbol
            DEFAULT_SLOPE,
            DEFAULT_BASE_PRICE,
            DEFAULT_GRADUATION_THRESHOLD
        );
    }
    
    /**
     * @notice Test token creation with zero slope
     * @dev Should revert as slope must be greater than 0
     */
    function test_CreateToken_ZeroSlope_Reverts() public {
        vm.prank(tokenCreator);
        vm.expectRevert("Slope must be greater than 0");
        factory.createToken{value: DEFAULT_CREATION_FEE}(
            DEFAULT_NAME,
            DEFAULT_SYMBOL,
            0, // Zero slope
            DEFAULT_BASE_PRICE,
            DEFAULT_GRADUATION_THRESHOLD
        );
    }
    
    /**
     * @notice Test token creation with zero base price
     * @dev Should revert as base price must be greater than 0
     */
    function test_CreateToken_ZeroBasePrice_Reverts() public {
        vm.prank(tokenCreator);
        vm.expectRevert("Base price must be greater than 0");
        factory.createToken{value: DEFAULT_CREATION_FEE}(
            DEFAULT_NAME,
            DEFAULT_SYMBOL,
            DEFAULT_SLOPE,
            0, // Zero base price
            DEFAULT_GRADUATION_THRESHOLD
        );
    }
    
    /**
     * @notice Test token creation with zero graduation threshold
     * @dev Should revert as graduation threshold must be greater than 0
     */
    function test_CreateToken_ZeroGraduationThreshold_Reverts() public {
        vm.prank(tokenCreator);
        vm.expectRevert("Graduation threshold must be greater than 0");
        factory.createToken{value: DEFAULT_CREATION_FEE}(
            DEFAULT_NAME,
            DEFAULT_SYMBOL,
            DEFAULT_SLOPE,
            DEFAULT_BASE_PRICE,
            0 // Zero graduation threshold
        );
    }
    
    /**
     * @notice Test token creation with insufficient creation fee
     * @dev Should revert when payment is less than required creation fee
     */
    function test_CreateToken_InsufficientFee_Reverts() public {
        uint256 insufficientFee = DEFAULT_CREATION_FEE - 1 wei;
        
        vm.prank(tokenCreator);
        vm.expectRevert("Insufficient creation fee");
        factory.createToken{value: insufficientFee}(
            DEFAULT_NAME,
            DEFAULT_SYMBOL,
            DEFAULT_SLOPE,
            DEFAULT_BASE_PRICE,
            DEFAULT_GRADUATION_THRESHOLD
        );
    }
    
    /**
     * @notice Test token creation with no payment
     * @dev Should revert when no ETH is sent for creation fee
     */
    function test_CreateToken_NoPayment_Reverts() public {
        vm.prank(tokenCreator);
        vm.expectRevert("Insufficient creation fee");
        factory.createToken{value: 0}(
            DEFAULT_NAME,
            DEFAULT_SYMBOL,
            DEFAULT_SLOPE,
            DEFAULT_BASE_PRICE,
            DEFAULT_GRADUATION_THRESHOLD
        );
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // PARAMETER VALIDATION EDGE CASES
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Test token creation with extremely large parameters
     * @dev Verifies system handles large numbers appropriately
     */
    function test_CreateToken_ExtremelyLargeParameters() public {
        uint256 largeSlope = type(uint256).max / 1000; // Avoid overflow in calculations
        uint256 largeBasePrice = type(uint256).max / 1000;
        uint256 largeThreshold = type(uint256).max / 1000;
        
        vm.prank(tokenCreator);
        address tokenAddress = factory.createToken{value: DEFAULT_CREATION_FEE}(
            DEFAULT_NAME,
            DEFAULT_SYMBOL,
            largeSlope,
            largeBasePrice,
            largeThreshold
        );
        
        assertTrue(tokenAddress != address(0), "Token should be created with large parameters");
        
        TokenFactory.TokenInfo memory tokenInfo = factory.getTokenInfo(tokenAddress);
        assertEq(tokenInfo.slope, largeSlope, "Large slope should be stored correctly");
        assertEq(tokenInfo.basePrice, largeBasePrice, "Large base price should be stored correctly");
        assertEq(tokenInfo.graduationThreshold, largeThreshold, "Large graduation threshold should be stored correctly");
    }
    
    /**
     * @notice Test token creation with minimum valid parameters
     * @dev Verifies system accepts smallest possible valid values
     */
    function test_CreateToken_MinimumValidParameters() public {
        vm.prank(tokenCreator);
        address tokenAddress = factory.createToken{value: DEFAULT_CREATION_FEE}(
            "A", // Single character name
            "B", // Single character symbol
            1,   // Minimum slope
            1,   // Minimum base price
            1    // Minimum graduation threshold
        );
        
        assertTrue(tokenAddress != address(0), "Token should be created with minimum parameters");
        
        TokenFactory.TokenInfo memory tokenInfo = factory.getTokenInfo(tokenAddress);
        assertEq(tokenInfo.slope, 1, "Minimum slope should be stored");
        assertEq(tokenInfo.basePrice, 1, "Minimum base price should be stored");
        assertEq(tokenInfo.graduationThreshold, 1, "Minimum graduation threshold should be stored");
    }
    
    /**
     * @notice Test token creation with very long name and symbol
     * @dev Verifies system handles long strings appropriately
     */
    function test_CreateToken_VeryLongNameAndSymbol() public {
        string memory longName = "This is a very long token name that contains many characters and might test string handling limits in the smart contract system";
        string memory longSymbol = "VERYLONGSYMBOLNAME";
        
        vm.prank(tokenCreator);
        address tokenAddress = factory.createToken{value: DEFAULT_CREATION_FEE}(
            longName,
            longSymbol,
            DEFAULT_SLOPE,
            DEFAULT_BASE_PRICE,
            DEFAULT_GRADUATION_THRESHOLD
        );
        
        assertTrue(tokenAddress != address(0), "Token should be created with long name/symbol");
        
        TokenFactory.TokenInfo memory tokenInfo = factory.getTokenInfo(tokenAddress);
        assertEq(tokenInfo.name, longName, "Long name should be stored correctly");
        assertEq(tokenInfo.symbol, longSymbol, "Long symbol should be stored correctly");
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // TOKEN CONTRACT VALIDATION TESTS  
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Test that created token has correct initial state
     * @dev Verifies the deployed token contract is properly initialized
     */
    function test_CreatedToken_InitialState() public {
        vm.prank(tokenCreator);
        address tokenAddress = factory.createToken{value: DEFAULT_CREATION_FEE}(
            DEFAULT_NAME,
            DEFAULT_SYMBOL,
            DEFAULT_SLOPE,
            DEFAULT_BASE_PRICE,
            DEFAULT_GRADUATION_THRESHOLD
        );
        
        BondingCurveToken token = BondingCurveToken(payable(tokenAddress));
        
        // Verify ERC20 properties
        assertEq(token.name(), DEFAULT_NAME, "Token name should match");
        assertEq(token.symbol(), DEFAULT_SYMBOL, "Token symbol should match");
        assertEq(token.decimals(), 18, "Token should have 18 decimals");
        assertEq(token.totalSupply(), 0, "Initial supply should be 0");
        
        // Verify bonding curve parameters
        assertEq(token.slope(), DEFAULT_SLOPE, "Slope should match");
        assertEq(token.basePrice(), DEFAULT_BASE_PRICE, "Base price should match");
        assertEq(token.graduationThreshold(), DEFAULT_GRADUATION_THRESHOLD, "Graduation threshold should match");
        
        // Verify initial state
        assertFalse(token.hasGraduated(), "Should not be graduated initially");
        assertEq(token.totalRaised(), 0, "Total raised should be 0 initially");
        assertEq(token.creator(), tokenCreator, "Creator should be set correctly");
        assertEq(token.factory(), address(factory), "Factory should be set correctly");
        
        // Verify ownership
        assertEq(token.owner(), tokenCreator, "Token creator should be owner");
    }
    
    /**
     * @notice Test that created token has correct fee configuration
     * @dev Verifies fee settings are properly inherited from factory
     */
    function test_CreatedToken_FeeConfiguration() public {
        vm.prank(tokenCreator);
        address tokenAddress = factory.createToken{value: DEFAULT_CREATION_FEE}(
            DEFAULT_NAME,
            DEFAULT_SYMBOL,
            DEFAULT_SLOPE,
            DEFAULT_BASE_PRICE,
            DEFAULT_GRADUATION_THRESHOLD
        );
        
        BondingCurveToken token = BondingCurveToken(payable(tokenAddress));
        
        // Verify graduation fee structure (immutable values)
        assertEq(token.LIQUIDITY_FEE(), 8000, "Liquidity fee should be 80%");
        assertEq(token.CREATOR_FEE(), 0, "Creator fee should be 0%");
        assertEq(token.PLATFORM_FEE(), 2000, "Platform fee should be 20%");
        
        // Verify trading fees
        (uint256 buyFee, uint256 sellFee) = token.getTradingFees();
        assertEq(buyFee, 0, "Initial buy trading fee should be 0%");
        assertEq(sellFee, 0, "Initial sell trading fee should be 0%");
        
        // Verify fee collector
        assertEq(token.platformFeeCollector(), platformFeeCollector, "Platform fee collector should match");
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // FACTORY STATE VALIDATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Test that factory state is properly updated after token creation
     * @dev Verifies all factory tracking mechanisms work correctly
     */
    function test_Factory_StateUpdatedAfterCreation() public {
        uint256 initialCount = factory.getTokenCount();
        uint256 initialFeesCollected = factory.totalFeesCollected();
        
        vm.prank(tokenCreator);
        address tokenAddress = factory.createToken{value: DEFAULT_CREATION_FEE}(
            DEFAULT_NAME,
            DEFAULT_SYMBOL,
            DEFAULT_SLOPE,
            DEFAULT_BASE_PRICE,
            DEFAULT_GRADUATION_THRESHOLD
        );
        
        // Verify count increased
        assertEq(factory.getTokenCount(), initialCount + 1, "Token count should increase by 1");
        
        // Verify fees collected increased
        assertEq(factory.totalFeesCollected(), initialFeesCollected + DEFAULT_CREATION_FEE, "Total fees should increase");
        
        // Verify token is tracked as created
        assertTrue(factory.isTokenCreated(tokenAddress), "Token should be marked as created");
        
        // Verify token index is set correctly
        uint256 expectedIndex = initialCount; // 0-based indexing
        assertEq(factory.tokenIndex(tokenAddress), expectedIndex, "Token index should be set correctly");
    }
    
    /**
     * @notice Test querying non-existent token information
     * @dev Should revert when querying token not created by factory
     */
    function test_GetTokenInfo_NonExistentToken_Reverts() public {
        address fakeToken = address(0x999);
        
        vm.expectRevert("Token not created by this factory");
        factory.getTokenInfo(fakeToken);
    }
    
    /**
     * @notice Test querying creator tokens for address with no tokens
     * @dev Should return empty array for creators who haven't created tokens
     */
    function test_GetCreatorTokens_NoTokens() public view {
        address[] memory creatorTokens = factory.getCreatorTokens(user1);
        assertEq(creatorTokens.length, 0, "Should return empty array for creator with no tokens");
    }
}
