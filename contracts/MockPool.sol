// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFlashLoanReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

contract MockPool {
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external {
        // Transfer the tokens to the receiver
        IERC20(asset).transfer(receiverAddress, amount);
        
        // Calculate premium (0.09%)
        uint256 premium = amount * 9 / 10000;
        
        // Call executeOperation on the receiver
        IFlashLoanReceiver receiver = IFlashLoanReceiver(receiverAddress);
        bool success = receiver.executeOperation(
            asset,
            amount,
            premium,
            msg.sender,
            params
        );
        require(success, "MockPool: Flash loan callback failed");
        
        // Get back the amount + premium
        require(
            IERC20(asset).transferFrom(receiverAddress, address(this), amount + premium),
            "MockPool: Repayment failed"
        );
    }
}