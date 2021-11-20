// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "../libraries/token/ERC20/IERC20.sol";
import "../libraries/token/ERC20/SafeERC20.sol";
import "../libraries/math/SafeMath.sol";
import "../libraries/utils/Address.sol";

contract IslandLock {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    IERC20 public islToken;
    uint constant  public PERIOD = 10 days;
    uint constant  public CYCLE_TIMES = 30;
    uint public fixedQuantity;
    uint public startTime;
    uint public cycle;
    uint public hasReward;  // Rewards already withdrawn
    address public teamAddr;

    event WithDraw(address indexed operator, address indexed to, uint amount);

    constructor(
        address _teamAddr,
        address _islToken,
        uint _fixedQuantity,
        uint _startTime
    ) public {
        require(_teamAddr != address(0) && _islToken != address(0), "TimeLock: zero address");
        require(_fixedQuantity > 0, "TimeLock: fixedQuantity is zero");
        teamAddr = _teamAddr;
        islToken = IERC20(_islToken);
        fixedQuantity = _fixedQuantity;
        startTime = _startTime;
    }


    function getBalance() public view returns (uint) {
        return islToken.balanceOf(address(this));
    }

    function getReward() public view returns (uint) {

        if (cycle >= CYCLE_TIMES || block.timestamp <= startTime) {
            return 0;
        }
        uint pCycle = (block.timestamp.sub(startTime)).div(PERIOD);
        if (pCycle >= CYCLE_TIMES) {
            return islToken.balanceOf(address(this));
        }
        return pCycle.sub(cycle).mul(fixedQuantity);
    }

    function withDraw() external {
        uint reward = getReward();
        require(reward > 0, "TimeLock: no reward");
        uint pCycle = (block.timestamp.sub(startTime)).div(PERIOD);
        cycle = pCycle >= CYCLE_TIMES ? CYCLE_TIMES : pCycle;
        hasReward = hasReward.add(reward);
        islToken.safeTransfer(teamAddr, reward);
        emit WithDraw(msg.sender, teamAddr, reward);
    }

    function setTeamAddr(address _newTeamAddr) public {
        require(msg.sender == teamAddr, "Not beneficiary");
        teamAddr = _newTeamAddr;
    }
}