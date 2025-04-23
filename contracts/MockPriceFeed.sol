// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract MockPriceFeed is AggregatorV3Interface {
    int256 private price;
    uint8 private _decimals;

    constructor(int256 _initialPrice) {
        price = _initialPrice;
        _decimals = 8; // Chainlink commonly uses 8 decimals
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return "MockPriceFeed";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 _roundId) 
        external 
        view 
        override 
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) 
    {
        return (_roundId, price, block.timestamp, block.timestamp, _roundId);
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, price, block.timestamp, block.timestamp, 1);
    }

    function setPrice(int256 _newPrice) external {
        price = _newPrice;
    }
}
