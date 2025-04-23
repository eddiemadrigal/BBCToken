// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockERC20
 * @notice A test-friendly ERC20 with mint, burn, optional whitelist, and 18 decimals.
 */
contract MockERC20 is ERC20, Ownable {
    /// @notice Address-level transfer whitelist
    mapping(address => bool) public tokenWhitelist;

    /// @notice Enable or disable whitelist enforcement
    bool public enforceWhitelist = false;

    /**
     * @dev Initializes the mock token.
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param initialSupply Initial token supply minted to deployer
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply,
        address initialOwner
    ) ERC20(name_, symbol_) Ownable(initialOwner) {
        _mint(msg.sender, initialSupply);
    }

    /**
     * @notice Allows the owner to mint tokens to a given address.
     * @param to Recipient address
     * @param amount Token amount in wei
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Allows the owner to burn tokens from a given address.
     * @param from Address to burn from
     * @param amount Token amount in wei
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    /**
     * @notice Sets the whitelist status for a given address.
     * @param account Address to modify
     * @param status True to allow transfers, false to block
     */
    function setTokenWhitelist(address account, bool status) external onlyOwner {
        tokenWhitelist[account] = status;
    }

    /**
     * @notice Enables or disables whitelist enforcement.
     * @param status If true, only whitelisted addresses can receive tokens
     */
    function setEnforceWhitelist(bool status) external onlyOwner {
        enforceWhitelist = status;
    }

    /**
     * @notice Overrides ERC20's decimals to return 18.
     * @return Always returns 18.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev Internal transfer hook that optionally enforces whitelist.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        if (enforceWhitelist && to != address(0)) {
            require(tokenWhitelist[to], "MockERC20: recipient not whitelisted");
        }

        super._update(from, to, value);
    }
}
