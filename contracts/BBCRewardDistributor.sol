// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

interface IUniswapV2Router {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external view returns (uint256[] memory amounts);
}

// BBCRewardDistributor.sol
contract BBCRewardDistributor is Ownable, AutomationCompatibleInterface, ReentrancyGuard {
    IERC20 public immutable BBC;

    uint256 public lastDistributionDay;
    uint256 public totalTokensSold;
    uint256 public dailyDistributionCap;

    address[] public recipients;
    mapping(address => bool) public isRecipient;
    uint256 public maxRecipients = 1000;
    mapping(address => bool) public authorizedDistributors;

    address public uniswapRouter;
    bool public automationEnabled = true;

    struct DistributionDetail {
        address recipient;
        uint256 amount;
    }

    event DistributionExecuted(
        uint256 indexed timestamp,
        uint256 totalDistributed,
        DistributionDetail[] details
    );
    event DailyRewardSent(address indexed recipient, uint256 amount, uint256 timestamp);
    event BuybackExecuted(uint256 ethSpent, uint256 bbcReceived, uint256 timestamp);
    event DailyCapUpdated(uint256 oldCap, uint256 newCap);
    event MaxRecipientsUpdated(uint256 oldMax, uint256 newMax);
    event AutomationToggled(bool enabled);
    event RecipientAdded(address indexed recipient);
    event RecipientRemoved(address indexed recipient);
    event DistributorAuthorized(address distributor, bool status);

    receive() external payable {}

    constructor(address _owner, address _BBC, uint256 _initialDistributionCap)
        Ownable(_owner)
    {
        require(_BBC != address(0), "Invalid token address");
        BBC = IERC20(_BBC);
        dailyDistributionCap = _initialDistributionCap > 0
            ? _initialDistributionCap
            : 49_000_000 * 1e18;
    }

    function withdrawTokens(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid address");
        uint256 bal = BBC.balanceOf(address(this));
        require(bal > 0, "No BBC to withdraw");
        uint256 w = amount == 0 ? bal : amount;
        require(w <= bal, "Insufficient balance");
        require(BBC.transfer(to, w), "Transfer failed");
    }

    function withdrawETH(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid address");
        uint256 bal = address(this).balance;
        require(bal > 0, "No ETH to withdraw");
        uint256 w = amount == 0 ? bal : amount;
        require(w <= bal, "Insufficient balance");
        (bool ok, ) = to.call{value: w}("");
        require(ok, "ETH transfer failed");
    }

    event BuyBackStart(uint256 amount, uint256 minOut);
    event SwapCalled(address to, uint256 amountOut);
    event SwapFailed(string message);

    function buyBackBBC(uint256 amount, uint256 amountOutMin, uint256 deadline) external onlyOwner {
        emit BuyBackStart(amount, amountOutMin);

        require(address(this).balance >= amount, "Insufficient ETH");

        // WETH address on the Ethereum mainnet
        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        // Assuming path is declared as an array of addresses with length 2
        address[] memory path = new address[](2);

        // Assigning values to the path array
        path[0] = WETH;
        path[1] = address(BBC); // Use the address of the BBC token

        IUniswapV2Router uniswapRouterInterface = IUniswapV2Router(uniswapRouter);

        try uniswapRouterInterface.swapExactETHForTokens{
            value: amount
        }(amountOutMin, path, address(this), deadline) returns (uint256[] memory amounts) {
            emit SwapCalled(address(this), amounts[1]);
        } catch (bytes memory error) {
            emit SwapFailed("Swap failed");
            revert("BuyBack failed");
        }
    }

    function setUniswapRouter(address _r) external onlyOwner {
        require(_r != address(0), "Invalid router");
        uniswapRouter = _r;
    }

    function addRecipient(address r) external onlyOwner {
        require(r != address(0), "Invalid address");
        require(!isRecipient[r], "Already a recipient");
        require(recipients.length < maxRecipients, "Max recipients reached");
        isRecipient[r] = true;
        recipients.push(r);
        emit RecipientAdded(r);
    }

    function addManyRecipients(address[] calldata newRecipients) external onlyOwner {
        require(recipients.length + newRecipients.length <= maxRecipients, "Would exceed max");
        require(newRecipients.length <= 100, "Batch too large");
        for (uint256 i = 0; i < newRecipients.length; i++) {
            address rec = newRecipients[i];
            if (rec != address(0) && !isRecipient[rec]) {
                isRecipient[rec] = true;
                recipients.push(rec);
                emit RecipientAdded(rec);
            }
        }
    }

    function removeRecipient(address r) external onlyOwner {
        require(isRecipient[r], "Not a recipient");
        isRecipient[r] = false;
        uint256 len = recipients.length;
        for (uint256 i = 0; i < len; i++) {
            if (recipients[i] == r) {
                recipients[i] = recipients[len - 1];
                recipients.pop();
                emit RecipientRemoved(r);
                break;
            }
        }
    }

    function setTotalTokensSold(uint256 _amount) external onlyOwner {
        totalTokensSold = _amount;
    }

    function setDailyDistributionCap(uint256 _newCap) external onlyOwner {
        require(_newCap > 0, "Cap must be positive");
        uint256 old = dailyDistributionCap;
        dailyDistributionCap = _newCap;
        emit DailyCapUpdated(old, _newCap);
    }

    function setMaxRecipients(uint256 _newMax) external onlyOwner {
        require(_newMax >= recipients.length, "Cannot be less than current recipients");
        uint256 old = maxRecipients;
        maxRecipients = _newMax;
        emit MaxRecipientsUpdated(old, _newMax);
    }

    function toggleAutomation(bool _enabled) external onlyOwner {
        automationEnabled = _enabled;
        emit AutomationToggled(_enabled);
    }

    function checkUpkeep(bytes calldata) external view override returns (
        bool upkeepNeeded,
        bytes memory
    ) {
        uint256 currentDay = block.timestamp / 1 days;
        uint256 timeToday = block.timestamp % 1 days;
        upkeepNeeded =
            automationEnabled &&
            currentDay > lastDistributionDay &&
            timeToday >= 20 hours &&
            BBC.balanceOf(address(this)) > 0 &&
            recipients.length > 0;
    }

    function performUpkeep(bytes calldata) external override {
        if (
            automationEnabled &&
            block.timestamp / 1 days > lastDistributionDay
        ) {
            distributeRewardsBatch(0, recipients.length);
        }
    }

    // Add authorization function
    function setDistributorAuthorization(address distributor, bool status) external onlyOwner {
        authorizedDistributors[distributor] = status;
        emit DistributorAuthorized(distributor, status);
    }

    // Modify the distributeRewardsBatch function to use new authorization
    function distributeRewardsBatch(uint256 offset, uint256 batchSize)
        public
        nonReentrant
    {
        require(msg.sender == owner() || authorizedDistributors[msg.sender], 
            "BBC: Unauthorized distributor");
        uint256 today = block.timestamp / 1 days;
        require(today > lastDistributionDay, "Already distributed today");
        require(offset < recipients.length, "Offset out of bounds");

        uint256 end = offset + batchSize;
        if (end > recipients.length) {
            end = recipients.length;
        }

        uint256 totalDistributedLocal = 0;
        uint256 contractBal = BBC.balanceOf(address(this));
        uint256 range = end - offset;

        DistributionDetail[] memory details = new DistributionDetail[](range);
        uint256 count;

        for (uint256 i = offset; i < end; i++) {
            address rec = recipients[i];
            if (!isRecipient[rec]) {
                continue;
            }
            uint256 bal = BBC.balanceOf(rec);
            uint256 reward = (bal * totalTokensSold) / (100_000_000 * 1e18);

            if (
                reward > 0 &&
                contractBal >= reward &&
                totalDistributedLocal + reward <= dailyDistributionCap
            ) {
                // Simply perform the transfer - the receive()/fallback() functions 
                // will handle any reentry attempts
                require(BBC.transfer(rec, reward), "Transfer failed");
                
                details[count] = DistributionDetail(rec, reward);
                count++;
                totalDistributedLocal += reward;
                contractBal -= reward;
                emit DailyRewardSent(rec, reward, block.timestamp);
            }
        }

        lastDistributionDay = today;

        if (count < range) {
            DistributionDetail[] memory trimmed = new DistributionDetail[](count);
            for (uint256 j = 0; j < count; j++) {
                trimmed[j] = details[j];
            }
            details = trimmed;
        }

        emit DistributionExecuted(
            block.timestamp,
            totalDistributedLocal,
            details
        );
    }

    function getRecipients(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory)
    {
        uint256 len = recipients.length;
        if (offset >= len) {
            return new address[](0); // Return an empty address array
        }
        uint256 end = offset + limit > len ? len : offset + limit;
        uint256 size = end - offset;
        address[] memory slice = new address[](size);
        for (uint256 i = 0; i < size; i++) {
            slice[i] = recipients[offset + i];
        }
        return slice;
    }
}