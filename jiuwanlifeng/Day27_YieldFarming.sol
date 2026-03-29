// SPDX-License-Identifier: MIT
// 代码开源协议：MIT协议，大家可以随便用。

pragma solidity ^0.8.20;
// 这个合约需要用Solidity 0.8.20及以上版本编译。

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// 导入ERC20接口（代币标准接口）。用来操作代币的转账、余额查询等。

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
// 导入重入攻击防护。防止黑客在转账过程中反复调用合约函数偷钱。

import "@openzeppelin/contracts/utils/math/SafeCast.sol"; // 如果需要使用 SafeCast
// 导入SafeCast库，用于安全的类型转换（防止溢出）。虽然这行注释了但代码里用了，所以导入是必要的。

// 用于获取 ERC-20 元数据(小数位数)的接口
interface IERC20Metadata is IERC20 {
    // 定义一个扩展接口，继承自IERC20，增加获取代币元数据的功能。
    
    function decimals() external view returns (uint8);
    // 获取代币的小数位数。比如USDT是6位，ETH是18位。
    
    function name() external view returns (string memory);
    // 获取代币名称（比如"Tether USD"）。
    
    function symbol() external view returns (string memory);
    // 获取代币符号（比如"USDT"）。
}

/// @title 收益耕作平台
///     质押代币以随时间赚取奖励,可选紧急提取和管理员补充
// 合约注释：这是一个收益耕作平台，质押代币可以随时间赚取奖励，支持紧急提取和管理员补充奖励。

contract YieldFarming is ReentrancyGuard {
// 定义一个合约叫"收益耕作"，它继承自ReentrancyGuard（防重入保护）。

    using SafeCast for uint256;
    // 使用SafeCast库，为uint256类型添加安全的类型转换方法。

    IERC20 public stakingToken;
    // 质押代币。用户需要质押这个代币来赚取奖励。

    IERC20 public rewardToken;
    // 奖励代币。用户质押后获得的奖励是这个代币。

    uint256 public rewardRatePerSecond; // 每秒分配的奖励
    // 每秒分配的奖励数量（单位：奖励代币的最小单位）。
    // 注意：这个值可能需要根据质押代币的小数位数进行调整。

    address public owner;
    // 合约所有者（管理员）。

    uint8 public stakingTokenDecimals; // 存储质押代币的小数位数
    // 存储质押代币的小数位数，用于计算奖励。

    struct StakerInfo {
        // 定义一个结构体，记录每个质押者的信息。
        
        uint256 stakedAmount;
        // 质押数量（单位：质押代币的最小单位）。
        
        uint256 rewardDebt;
        // 已累积但未领取的奖励（单位：奖励代币的最小单位）。
        
        uint256 lastUpdate;
        // 上次更新奖励的时间戳。
    }

    mapping(address => StakerInfo) public stakers;
    // 创建一个映射：地址 → 质押者信息。
    // 记录每个用户的质押情况。

    event Staked(address indexed user, uint256 amount);
    // 质押事件：谁，质押了多少。

    event Unstaked(address indexed user, uint256 amount);
    // 取消质押事件：谁，取回了多少。

    event RewardClaimed(address indexed user, uint256 amount);
    // 领取奖励事件：谁，领了多少。

    event EmergencyWithdraw(address indexed user, uint256 amount);
    // 紧急提取事件：谁，紧急取回了多少（放弃奖励）。

    event RewardRefilled(address indexed owner, uint256 amount);
    // 奖励补充事件：管理员，补充了多少奖励到池子。

    modifier onlyOwner() {
        // 定义一个修饰符，只有管理员才能调用某些函数。

        require(msg.sender == owner, "Not the owner");
        // 检查：调用者必须是owner。

        _;
        // 执行原函数。
    }

    constructor(
        address _stakingToken,
        address _rewardToken,
        uint256 _rewardRatePerSecond
    ) {
        // 构造函数，部署时运行一次。设置三个核心参数。

        stakingToken = IERC20(_stakingToken);
        // 设置质押代币地址。

        rewardToken = IERC20(_rewardToken);
        // 设置奖励代币地址。

        rewardRatePerSecond = _rewardRatePerSecond;
        // 设置每秒奖励速率。

        owner = msg.sender;
        // 合约部署者成为管理员。

        // 尝试获取小数位数
        try IERC20Metadata(_stakingToken).decimals() returns (uint8 decimals) {
            // 尝试调用质押代币的decimals()函数获取小数位数
            stakingTokenDecimals = decimals;
            // 如果成功，存储这个小数位数
        } catch (bytes memory) {
            // 如果调用失败（比如代币不支持decimals函数）
            stakingTokenDecimals = 18; // 如果获取失败,默认为 18 位小数
            // 默认使用18位小数（以太坊标准）
        }
    }

    ///     质押代币以开始赚取奖励
    // 注释：质押代币开始赚取奖励

    function stake(uint256 amount) external nonReentrant {
        // 质押函数。传入要质押的数量。nonReentrant防止重入攻击。

        require(amount > 0, "Cannot stake 0");
        // 检查：质押数量必须大于0。

        updateRewards(msg.sender);
        // 更新调用者的奖励（先结算之前的奖励）。

        stakingToken.transferFrom(msg.sender, address(this), amount);
        // 从调用者钱包里转出amount个质押代币到合约地址。

        stakers[msg.sender].stakedAmount += amount;
        // 增加调用者的质押余额。

        emit Staked(msg.sender, amount);
        // 发出质押事件。
    }

    ///     取消质押代币并可选择领取奖励
    // 注释：取消质押代币，可以选择领取奖励（奖励会自动结算）

    function unstake(uint256 amount) external nonReentrant {
        // 取消质押函数。传入要取回的数量。nonReentrant防重入。

        require(amount > 0, "Cannot unstake 0");
        // 检查：取回数量必须大于0。

        require(stakers[msg.sender].stakedAmount >= amount, "Not enough staked");
        // 检查：质押余额足够。

        updateRewards(msg.sender);
        // 更新调用者的奖励（先结算之前的奖励）。

        stakers[msg.sender].stakedAmount -= amount;
        // 减少质押余额。

        stakingToken.transfer(msg.sender, amount);
        // 把质押代币转回给调用者。

        emit Unstaked(msg.sender, amount);
        // 发出取消质押事件。
    }

    ///     领取累积的奖励
    // 注释：领取累积的奖励

    function claimRewards() external nonReentrant {
        // 领取奖励函数。nonReentrant防重入。

        updateRewards(msg.sender);
        // 更新调用者的奖励（计算最新的奖励）。

        uint256 reward = stakers[msg.sender].rewardDebt;
        // 获取已累积的奖励金额。

        require(reward > 0, "No rewards to claim");
        // 检查：确实有奖励可以领。

        require(rewardToken.balanceOf(address(this)) >= reward, "Insufficient reward token balance");
        // 检查：合约里的奖励代币余额足够支付。

        stakers[msg.sender].rewardDebt = 0;
        // 将奖励债务清零（已经领走了）。

        rewardToken.transfer(msg.sender, reward);
        // 把奖励代币转给调用者。

        emit RewardClaimed(msg.sender, reward);
        // 发出领取奖励事件。
    }

    ///     紧急取消质押而不领取奖励
    // 注释：紧急取消质押，放弃奖励，只取回本金

    function emergencyWithdraw() external nonReentrant {
        // 紧急提取函数。放弃所有奖励，只取回质押的代币。nonReentrant防重入。

        uint256 amount = stakers[msg.sender].stakedAmount;
        // 获取调用者的质押数量。

        require(amount > 0, "Nothing staked");
        // 检查：确实有质押。

        stakers[msg.sender].stakedAmount = 0;
        // 质押余额清零。

        stakers[msg.sender].rewardDebt = 0;
        // 奖励债务清零（放弃奖励）。

        stakers[msg.sender].lastUpdate = block.timestamp;
        // 更新时间戳（避免之后错误计算）。

        stakingToken.transfer(msg.sender, amount);
        // 把质押代币转回给调用者。

        emit EmergencyWithdraw(msg.sender, amount);
        // 发出紧急提取事件。
    }

    ///     管理员可以补充奖励代币
    // 注释：管理员可以补充奖励代币到池子

    function refillRewards(uint256 amount) external onlyOwner {
        // 补充奖励函数。只有管理员能调用。

        rewardToken.transferFrom(msg.sender, address(this), amount);
        // 从管理员钱包转出奖励代币到合约。

        emit RewardRefilled(msg.sender, amount);
        // 发出奖励补充事件。
    }

    ///     更新质押者的奖励
    // 注释：更新某个用户的奖励（内部函数）

    function updateRewards(address user) internal {
        // 内部函数，用于更新用户的奖励。
        // internal表示只能被合约内部调用。

        StakerInfo storage staker = stakers[user];
        // 获取用户的质押信息（storage引用，可以直接修改）。

        if (staker.stakedAmount > 0) {
            // 如果用户有质押
            uint256 timeDiff = block.timestamp - staker.lastUpdate;
            // 计算距离上次更新过去了多少秒。

            uint256 rewardMultiplier = 10 ** stakingTokenDecimals;
            // 计算奖励乘数。例如质押代币是18位小数，乘数就是10^18。
            // 作用是将奖励计算调整到正确的精度。

            uint256 pendingReward = (timeDiff * rewardRatePerSecond * staker.stakedAmount) / rewardMultiplier;
            // 计算这段时间产生的奖励：
            // 公式 = (时间差 × 每秒奖励速率 × 质押数量) ÷ 精度调整
            // 例如：质押了1个18位小数的代币（1 * 10^18），每秒奖励100个奖励代币，
            // 过了1秒，奖励 = (1 × 100 × 10^18) ÷ 10^18 = 100个奖励代币

            staker.rewardDebt += pendingReward;
            // 把新产生的奖励加到奖励债务里。
        }

        staker.lastUpdate = block.timestamp;
        // 更新最后更新时间戳。
    }

    ///     查看待处理奖励而不领取
    // 注释：查看某个用户的待处理奖励（不会改变状态）

    function pendingRewards(address user) external view returns (uint256) {
        // 查看待领取奖励的函数。view表示只读不修改状态。

        StakerInfo memory staker = stakers[user];
        // 获取用户的质押信息（memory副本，只读）。

        uint256 pendingReward = staker.rewardDebt;
        // 初始奖励 = 已累积但未领取的奖励。

        if (staker.stakedAmount > 0) {
            // 如果用户有质押
            uint256 timeDiff = block.timestamp - staker.lastUpdate;
            // 计算距离上次更新过去了多少秒。

            uint256 rewardMultiplier = 10 ** stakingTokenDecimals;
            // 计算奖励乘数。

            pendingReward += (timeDiff * rewardRatePerSecond * staker.stakedAmount) / rewardMultiplier;
            // 加上这段时间新产生的奖励。
        }

        return pendingReward;
        // 返回总的待领取奖励。
    }

    ///     查看质押代币小数位数
    // 注释：查看质押代币的小数位数

    function getStakingTokenDecimals() external view returns (uint8) {
        // 获取质押代币小数位数的函数。

        return stakingTokenDecimals;
        // 返回存储的小数位数。
    }
}
// 合约结束