// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockRouter {
    mapping(address => uint256) public swapResults;
    
    function setSwapResult(address token, uint256 amount) external {
        swapResults[token] = amount;
    }
        
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "MockRouter: Deadline expired");

        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];

        // Transfer tokenIn from caller to this contract
        require(
            IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn),
            "MockRouter: Transfer from failed"
        );

        // Get or calculate amount out
        uint256 amountOut = swapResults[tokenOut];
        require(amountOut >= amountOutMin, "MockRouter: Insufficient output amount");

        // Transfer tokenOut to recipient
        require(
            IERC20(tokenOut).transfer(to, amountOut),
            "MockRouter: Transfer to failed"
        );

        // Return amounts
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint i = 1; i < path.length-1; i++) {
            amounts[i] = amountIn; // Simplified
        }
        amounts[path.length-1] = amountOut;

        return amounts;
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "MockRouter: Deadline expired");

        address tokenOut = path[path.length - 1];
        uint256 amountOut = swapResults[tokenOut];
        require(amountOut >= amountOutMin, "MockRouter: Insufficient output amount");

        // Simulate sending tokenOut to `to`
        require(
            IERC20(tokenOut).transfer(to, amountOut),
            "MockRouter: Transfer to failed"
        );

        // Return mock output amounts
        amounts = new uint256[](path.length);
        amounts[0] = msg.value;
        for (uint i = 1; i < path.length - 1; i++) {
            amounts[i] = msg.value;
        }
        amounts[path.length - 1] = amountOut;

        return amounts;
    }

    function getSwapResult(address token) external view returns (uint256) {
        return swapResults[token];
    }
}