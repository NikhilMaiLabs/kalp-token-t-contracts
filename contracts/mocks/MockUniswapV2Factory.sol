// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./MockUniswapV2Pair.sol";

contract MockUniswapV2Factory {
    mapping(address => mapping(address => address)) public getPair;
    
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        pair = address(new MockUniswapV2Pair());
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair;
        return pair;
    }
}
