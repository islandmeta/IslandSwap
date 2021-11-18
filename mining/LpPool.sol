// SPDX-License-Identifier: WTL
pragma solidity 0.6.12;

import '../libraries/math/SafeMath.sol';
import '../libraries/token/ERC20/IERC20.sol';
import '../libraries/token/ERC20/SafeERC20.sol';
import '../libraries/access/Ownable.sol';


interface IislandToken is IERC20 {
    function mint(address to, uint256 amount) external returns (bool);
    function totalSupply() external override view returns (uint256);
}

interface IMigrator {
    function migrate(IERC20 token) external returns (IERC20);
}


contract LpPool is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accIslandPerShare;
    }

    // The island TOKEN!
    IislandToken public islToken;
    // Dev address.
    address public devaddr;
    // island tokens created per block.
    uint256 public islandPerBlock;
    // Bonus muliplier for early island makers.
    uint256 public BONUS_MULTIPLIER = 4;
    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigrator public migrator;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when island mining starts.
    uint256 public startBlock;

    // Control mining
    bool public paused = false;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        IislandToken _islToken,
        address _devaddr,
        uint256 _islandPerBlock,
        uint256 _startBlock
    ) public {
        islToken = _islToken;
        devaddr = _devaddr;
        islandPerBlock = _islandPerBlock;
        startBlock = _startBlock;


        totalAllocPoint = 0;

    }

    modifier notPause() {
        require(paused == false, "DogeswapPools: Mining has been suspended");
        _;
    }

    function setPause() public onlyOwner {
        paused = !paused;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function addPool(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accIslandPerShare: 0
        }));
    }

    function batchAddPools(
        uint256[] memory allocPoints,
        IERC20[] memory stakedTokens,
        bool _withUpdate
    ) public onlyOwner {
        require(stakedTokens.length == allocPoints.length,"IslandSwapPools: Invalid length of pools");
        for(uint i = 0; i < stakedTokens.length; i++) {
            addPool(allocPoints[i],stakedTokens[i], _withUpdate);
        }
    }

    // Update the given pool's island allocation point. Can only be called by the owner.
    function setPool(uint256 _pid,uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
        }
    }

    function batchSetPoolsByStakedToken(
        uint256[] memory _pids,
        uint256[] memory _allocPoints,
        bool _withUpdate
    ) public onlyOwner {
        require(_pids.length == _allocPoints.length, "IslandSwapPools: Invalid length of pools");
        for(uint i = 0; i < _pids.length; i++) {
            setPool(_pids[i],_allocPoints[i], _withUpdate);
        }
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(3);
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(points);
            poolInfo[0].allocPoint = points;
        }
    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigrator _migrator) public onlyOwner {
        migrator = _migrator;
    }



    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending islands on frontend.
    function pendingIsland(uint256 _pid, address _user) external view returns (uint256) {
        require(totalAllocPoint != 0, "totalAllocPoint is zero!");
        PoolInfo memory pool = poolInfo[_pid];
        if(pool.allocPoint<1){
            return 0;
        }
        UserInfo memory user = userInfo[_pid][_user];
        if(user.amount<1){
            return 0;
        }

        uint256 accIslandPerShare = pool.accIslandPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 islandReward = multiplier.mul(islandPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accIslandPerShare = accIslandPerShare.add(islandReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accIslandPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }


    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if(pool.allocPoint<1){
            return;
        }
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 islandReward = multiplier.mul(islandPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        islToken.mint(devaddr, islandReward.div(20));
        islToken.mint(address(this), islandReward.sub(islandReward.div(20)));
        pool.accIslandPerShare = pool.accIslandPerShare.add(islandReward.sub(islandReward.div(20)).mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to pool for island allocation.
    function deposit(uint256 _pid, uint256 _amount) public notPause{

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accIslandPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeIslandTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accIslandPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from pool.
    function withdraw(uint256 _pid, uint256 _amount) public notPause{

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accIslandPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeIslandTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accIslandPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }


    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public notPause{
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe island transfer function, just in case if rounding error causes pool to not have enough island
    function safeIslandTransfer(address _to, uint256 _amount) internal {
        uint256 islandBal = islToken.balanceOf(address(this));
        if (_amount > islandBal) {
            islToken.transfer(_to, islandBal);
        } else {
            islToken.transfer(_to, _amount);
        }
    }


    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        require(_devaddr!=address(0), "dev: Invalid address");
        devaddr = _devaddr;
    }

}
