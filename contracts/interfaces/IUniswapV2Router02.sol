// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Partial interface of Uniswap V2 Router to support swapExactETHForTokens
interface IUniswapV2Router02 {
    function WETH() external pure returns (address);

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);
}
