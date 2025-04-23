// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title BBCToken
 * @notice A clean ERC20 implementation with pause and slippage controls.
 * Designed for DeFi deployment and integration with liquidity pools and other protocols.
 */
contract BBCToken is ERC20, ERC20Pausable, Ownable {
    /// @notice Maximum allowed slippage in basis points (e.g. 500 = 5%)
    uint256 public maxSlippageBps = 500;

    /// @notice Optional mapping of external price feeds (e.g. for slippage guard compatibility)
    mapping(address => address) public priceFeeds;

    /// @notice Emitted when max slippage is updated
    event SlippageUpdated(uint256 newSlippage);

    /**
     * @notice Initializes the token with an initial owner and total supply.
     * @param initialOwner The address that will receive the initial supply and ownership
     * @param initialSupply The total supply to mint in wei (use `parseEther`)
     */
    constructor(address initialOwner, uint256 initialSupply)
        ERC20("BBC Token", "BBC")
        Ownable(initialOwner)
    {
        _mint(initialOwner, initialSupply);
    }

    /**
     * @notice Associates a price feed (e.g. Chainlink) to a token.
     * @param token The address of the external token (e.g. WETH)
     * @param feed The Chainlink-compatible AggregatorV3 feed for the token
     */
    function setPriceFeed(address token, address feed) external onlyOwner {
        priceFeeds[token] = feed;
    }

    /**
     * @notice Pause all token transfers (onlyOwner)
     */
    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    /**
     * @notice Unpause token transfers (onlyOwner)
     */
    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    /**
     * @notice Update slippage tolerance in basis points (1-999)
     * @dev Used by arbitrage or slippage protection logic elsewhere
     * @param bps New max slippage, must be between 1 and 999 BPS (0.01% to 9.99%)
     */
    function setMaxSlippage(uint256 bps) external onlyOwner {
        require(bps >= 1 && bps < 100, "BBCToken: Slippage must be between 0.01% and 10%");
        maxSlippageBps = bps;
        emit SlippageUpdated(bps);
    }

    /**
     * @dev Called during all transfers, minting, and burning. Includes pause check.
     */
    function _update(address from, address to, uint256 value)
        internal
        virtual
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }
}
