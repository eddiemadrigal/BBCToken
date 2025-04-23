// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { BBCTokenWithArbitrage } from "./BBCTokenWithArbitrage.sol";
import { BBCRewardDistributor } from "./BBCRewardDistributor.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Router02 } from "./interfaces/IUniswapV2Router02.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title BBCGuard
 * @notice Guardian contract to autonomously or manually protect the BBC token ecosystem.
 * Includes buyback, circuit breaker, and whale slashing mechanics.
 */
contract BBCGuard is Ownable, Pausable {
    BBCTokenWithArbitrage public immutable bbc;
    BBCRewardDistributor public immutable distributor;
    AggregatorV3Interface public immutable priceFeed;
    IUniswapV2Router02 public router;
    address public treasury;

    uint256 public priceFloor = 10 * 1e6; // $0.10 in 8 decimals (Chainlink style)
    uint256 public minBuybackEth = 0.1 ether;

    event PriceFloorUpdated(uint256 newFloor);
    event BuybackTriggered(uint256 ethUsed, uint256 bbcBought);
    event WhaleSlashed(address indexed wallet, uint256 amountSlashed);
    event BBCPaused();
    event BBCUnpaused();

    constructor(
        address _owner,
        address _bbc,
        address payable _distributor,
        address _priceFeed,
        address _router,
        address _treasury
    ) Ownable(_owner) {
        require(_bbc != address(0), "Invalid BBC address");
        require(address(_distributor) != address(0), "Invalid distributor");
        require(_router != address(0), "Invalid router");
        require(_priceFeed != address(0), "Invalid feed");
        require(_treasury != address(0), "Invalid treasury");

        bbc = BBCTokenWithArbitrage(_bbc);
        distributor = BBCRewardDistributor(_distributor);
        priceFeed = AggregatorV3Interface(_priceFeed);
        router = IUniswapV2Router02(_router);
        treasury = _treasury;
}
    /**
     * @notice Check Chainlink price feed to determine if BBC is below floor
     */
    function isBelowFloor() public view returns (bool) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price) < priceFloor;
    }

    /**
     * @notice Buy back BBC with ETH held in the guard contract and burn it.
     */
    function buyBackIfNeeded() external whenNotPaused {
        require(isBelowFloor(), "BBC price above floor");
        require(msg.sender == tx.origin, "No contracts");
        
        uint256 ethBalance = address(this).balance;
        require(ethBalance >= minBuybackEth, "Insufficient ETH for buyback");

        // Setup swap path
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(bbc);

        // Track BBC balance before buyback for calculating amount bought
        uint256 bbcBurnAddressBalanceBefore = bbc.balanceOf(address(0xdead));

        // Execute buyback and burn
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: ethBalance
        }(
            0,                  // Accept any amount of tokens
            path,
            address(0xdead),    // Burn address
            block.timestamp + 300
        );

        // Calculate how many tokens were bought by checking the balance difference
        uint256 bbcBought = bbc.balanceOf(address(0xdead)) - bbcBurnAddressBalanceBefore;

        emit BuybackTriggered(ethBalance, bbcBought);
    }

    /**
     * @notice Slash a whale by force-transferring half their balance to the treasury.
     * Must have allowance set by user (or called from timelock).
     * Intended for governance use.
     */
    function slashWhale(address whale) external onlyOwner {
        uint256 balance = bbc.balanceOf(whale);
        require(balance > 0, "No tokens to slash");

        uint256 half = balance / 2;
        bbc.transferFrom(whale, treasury, half);
        emit WhaleSlashed(whale, half);
    }

    /**
     * @notice Emergency pause the BBC token and distributor.
     */
    function triggerCircuitBreaker() external onlyOwner {
        emit BBCPaused();
        bbc.pause();
        distributor.setDailyDistributionCap(0);        
    }

    /**
     * @notice Resume normal operation after price recovery.
     */
    function resumeMarket() external onlyOwner {
        emit BBCUnpaused();
        bbc.unpause();
        distributor.setDailyDistributionCap(49_000_000 ether);
    }

    /**
     * @notice Update the price floor in Chainlink decimals (1e8 = $1.00).
     */
    function setPriceFloor(uint256 newFloor) external onlyOwner {
        priceFloor = newFloor;
        emit PriceFloorUpdated(newFloor);
    }

    /**
     * @notice Allow owner to rescue any token in the contract.
     */
    function rescueToken(address token, address to) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(to, balance);
    }

    /**
     * @notice Allow receiving ETH from buyback funding.
     */
    receive() external payable {}
}