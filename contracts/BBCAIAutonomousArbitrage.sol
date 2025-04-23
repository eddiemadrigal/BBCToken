// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IFlashLoanProvider {
    function flashLoanSimple(
        address receiver,
        address asset,
        uint256 amount,
        bytes calldata data,
        uint16 referralCode
    ) external;
}

interface IDexRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IFlashLoanReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

/**
 * @title BBCAIAutonomousArbitrage
 * @notice AI-triggered arbitrage executor with oracle verification, anti-frontrunning and gas efficiency protection.
 */
contract BBCAIAutonomousArbitrage is ReentrancyGuard, IFlashLoanReceiver {
    IERC20 public immutable BBC;
    AggregatorV3Interface public immutable priceFeed;
    IDexRouter public dexA;
    IDexRouter public dexB;
    IFlashLoanProvider public flashLoanProvider;
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    event ArbitrageExecuted(
        address indexed initiator,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOut,
        uint256 profit,
        uint256 premium
    );

    constructor(
        address _bbc,
        address _priceFeed,
        address _dexA,
        address _dexB,
        address _flashLoanProvider
    ) {
        require(_bbc != address(0), "Invalid BBC");
        require(_priceFeed != address(0), "Invalid feed");
        require(_dexA != address(0), "Invalid DEX A");
        require(_dexB != address(0), "Invalid DEX B");
        require(_flashLoanProvider != address(0), "Invalid loan provider");

        BBC = IERC20(_bbc);
        priceFeed = AggregatorV3Interface(_priceFeed);
        dexA = IDexRouter(_dexA);
        dexB = IDexRouter(_dexB);
        flashLoanProvider = IFlashLoanProvider(_flashLoanProvider);
        owner = msg.sender;
    }

    /**
     * @notice Called off-chain by AI bot when arbitrage is detected and verified
     * @param tokenIn token to borrow
     * @param amount amount of tokenIn to borrow
     * @param tradePath forward swap path
     * @param reversePath reverse swap path
     * @param minProfit minimum profit expected (in tokenIn units)
     * @param maxGas max gas allowed (in wei)
     * @param deadline deadline to avoid frontrunning
     */
    function triggerArbitrage(
        address tokenIn,
        uint256 amount,
        address[] calldata tradePath,
        address[] calldata reversePath,
        uint256 minProfit,
        uint256 maxGas,
        uint256 deadline
    ) external onlyOwner {
        require(tradePath.length >= 2 && reversePath.length >= 2, "Invalid path");
        require(block.timestamp <= deadline, "Deadline exceeded");
        require(gasleft() <= maxGas, "Too much gas used already");

        bytes memory data = abi.encode(tradePath, reversePath, minProfit, deadline, maxGas);
        flashLoanProvider.flashLoanSimple(
            address(this),
            tokenIn,
            amount,
            data,
            0 // referral code
        );
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address,
        bytes calldata data
    ) external override returns (bool) {
        require(msg.sender == address(flashLoanProvider), "Unauthorized");

        (address[] memory tradePath, address[] memory reversePath, uint256 minProfit, uint256 deadline, uint256 maxGas) =
            abi.decode(data, (address[], address[], uint256, uint256, uint256));

        require(block.timestamp <= deadline, "Expired arbitrage");
        require(gasleft() <= maxGas, "Gas exceeded");

        // Oracle price sanity check
        (, int256 chainlinkPrice,,,) = priceFeed.latestRoundData();
        require(chainlinkPrice > 0, "Invalid oracle price");

        // Execute forward swap
        IERC20(asset).approve(address(dexA), amount);
        uint256[] memory out1 = dexA.swapExactTokensForTokens(
            amount,
            1,
            tradePath,
            address(this),
            deadline
        );

        uint256 intermediateAmount = out1[out1.length - 1];

        // Execute reverse swap
        IERC20(tradePath[tradePath.length - 1]).approve(address(dexB), intermediateAmount);
        uint256[] memory out2 = dexB.swapExactTokensForTokens(
            intermediateAmount,
            1,
            reversePath,
            address(this),
            deadline
        );

        uint256 finalAmount = out2[out2.length - 1];
        uint256 repayment = amount + premium;

        require(finalAmount >= repayment + minProfit, "Unprofitable");

        IERC20(asset).approve(msg.sender, repayment);

        emit ArbitrageExecuted(tx.origin, asset, amount, finalAmount, finalAmount - repayment, premium);
        return true;
    }

    function rescueToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner, amount);
    }
}
