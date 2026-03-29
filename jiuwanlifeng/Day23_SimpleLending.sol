// SPDX-License-Identifier: MIT
// 代码开源协议声明：遵循MIT协议，大家可以随便用，但出了问题别找我。

pragma solidity ^0.8.0;
// 这个合约需要用Solidity 0.8.0及以上版本编译（但不能是0.9.0）。

/**
 * @title SimpleLending
 * @dev A basic DeFi lending and borrowing platform
 */
// 这是代码注释，给开发者看的。说明这个合约叫“简单借贷”，是一个基础的DeFi借贷平台。

contract SimpleLending {
// 定义一个合约，名字叫“SimpleLending”。花括号里面就是合约的所有内容。

    // Token balances for each user
    // 注释：每个用户的存款余额

    mapping(address => uint256) public depositBalances;
    // 创建一个映射（就像一个账本）：地址 → 存款余额
    // 记录每个用户存了多少钱。public表示所有人都可以查。

    // Borrowed amounts for each user
    // 注释：每个用户的借款余额

    mapping(address => uint256) public borrowBalances;
    // 创建一个映射：地址 → 借款余额
    // 记录每个用户借了多少钱（包含利息）。

    // Collateral provided by each user
    // 注释：每个用户提供的抵押品

    mapping(address => uint256) public collateralBalances;
    // 创建一个映射：地址 → 抵押品余额
    // 记录每个用户抵押了多少钱（抵押品是用来担保借款的）。

    // Interest rate in basis points (1/100 of a percent)
    // 500 basis points = 5% interest
    // 注释：利率使用“基点”为单位（1个基点 = 0.01%）
    // 500个基点 = 5%的利率

    uint256 public interestRateBasisPoints = 500;
    // 定义利率变量，初始值是500（也就是5%）。public表示公开可查。

    // Collateral factor in basis points (e.g., 7500 = 75%)
    // Determines how much you can borrow against your collateral
    // 注释：抵押因子，用基点表示（比如7500 = 75%）
    // 决定了你能用抵押品借多少钱

    uint256 public collateralFactorBasisPoints = 7500;
    // 定义抵押因子变量，初始值是7500（也就是75%）。
    // 意思是你抵押了100块钱，最多能借75块钱。

    // Timestamp of last interest accrual
    // 注释：上次计算利息的时间戳

    mapping(address => uint256) public lastInterestAccrualTimestamp;
    // 创建一个映射：地址 → 上次计算利息的时间
    // 记录每个用户最后一次更新利息是什么时候。

    // Events
    // 注释：下面是事件定义。事件就像广播，记录了合约里发生的重要事情，前端可以监听。

    event Deposit(address indexed user, uint256 amount);
    // 存款事件：谁，存了多少钱。indexed表示可以按这个地址搜索事件。

    event Withdraw(address indexed user, uint256 amount);
    // 取款事件：谁，取了多少钱。

    event Borrow(address indexed user, uint256 amount);
    // 借款事件：谁，借了多少钱。

    event Repay(address indexed user, uint256 amount);
    // 还款事件：谁，还了多少钱。

    event CollateralDeposited(address indexed user, uint256 amount);
    // 抵押存款事件：谁，抵押了多少钱。

    event CollateralWithdrawn(address indexed user, uint256 amount);
    // 取回抵押品事件：谁，取回了多少抵押品。

    function deposit() external payable {
        // 存款函数。external表示只能从外部调用（不能从合约内部调用）。
        // payable表示调用这个函数时可以附带ETH。

        require(msg.value > 0, "Must deposit a positive amount");
        // 第一道检查：你付的钱必须大于0。如果是0，报错：“必须存正数金额”。

        depositBalances[msg.sender] += msg.value;
        // 把你的存款余额增加你付的钱数。

        emit Deposit(msg.sender, msg.value);
        // 发出存款事件，记录谁存了多少钱。
    }

    function withdraw(uint256 amount) external {
        // 取款函数。传入要取多少钱。

        require(amount > 0, "Must withdraw a positive amount");
        // 检查：取款金额必须大于0。

        require(depositBalances[msg.sender] >= amount, "Insufficient balance");
        // 检查：你的存款余额必须大于等于要取的钱。不够的话报错：“余额不足”。

        depositBalances[msg.sender] -= amount;
        // 从你的存款余额里减去取走的钱。

        payable(msg.sender).transfer(amount);
        // 把ETH转账给你。payable(msg.sender)把你的地址转成可收款类型，然后用transfer转账。

        emit Withdraw(msg.sender, amount);
        // 发出取款事件。
    }

    function depositCollateral() external payable {
        // 抵押存款函数。可以把ETH作为抵押品存进来。

        require(msg.value > 0, "Must deposit a positive amount as collateral");
        // 检查：抵押的金额必须大于0。

        collateralBalances[msg.sender] += msg.value;
        // 把你的抵押品余额增加你付的钱。

        emit CollateralDeposited(msg.sender, msg.value);
        // 发出抵押存款事件。
    }

    function withdrawCollateral(uint256 amount) external {
        // 取回抵押品函数。传入要取回多少抵押品。

        require(amount > 0, "Must withdraw a positive amount");
        // 检查：取回金额必须大于0。

        require(collateralBalances[msg.sender] >= amount, "Insufficient collateral");
        // 检查：你的抵押品余额必须大于等于要取回的钱。

        uint256 borrowedAmount = calculateInterestAccrued(msg.sender);
        // 计算你当前欠了多少钱（包含利息），存到borrowedAmount变量里。

        uint256 requiredCollateral = (borrowedAmount * 10000) / collateralFactorBasisPoints;
        // 计算为了维持借款，你至少需要保留多少抵押品。
        // 公式：所需抵押品 = 借款金额 × 10000 ÷ 抵押因子
        // 例如：借了75块，抵押因子75%，那么所需抵押品 = 75 × 10000 ÷ 7500 = 100块

        require(
            collateralBalances[msg.sender] - amount >= requiredCollateral,
            "Withdrawal would break collateral ratio"
        );
        // 检查：取回抵押品后，剩下的抵押品是否还足够。
        // 如果不够，报错：“取回会破坏抵押比例”。

        collateralBalances[msg.sender] -= amount;
        // 从你的抵押品余额里减去取回的钱。

        payable(msg.sender).transfer(amount);
        // 把ETH转账给你。

        emit CollateralWithdrawn(msg.sender, amount);
        // 发出取回抵押品事件。
    }

    function borrow(uint256 amount) external {
        // 借款函数。传入要借多少钱。

        require(amount > 0, "Must borrow a positive amount");
        // 检查：借款金额必须大于0。

        require(address(this).balance >= amount, "Not enough liquidity in the pool");
        // 检查：合约里总余额（资金池）必须够借给你。address(this).balance是合约里所有ETH。
        // 不够的话报错：“资金池流动性不足”。

        uint256 maxBorrowAmount = (collateralBalances[msg.sender] * collateralFactorBasisPoints) / 10000;
        // 计算你最多能借多少钱。
        // 公式：最大借款 = 抵押品 × 抵押因子 ÷ 10000
        // 例如：抵押了100块，抵押因子75%，最多能借75块。

        uint256 currentDebt = calculateInterestAccrued(msg.sender);
        // 计算你当前欠了多少钱（包含利息）。

        require(currentDebt + amount <= maxBorrowAmount, "Exceeds allowed borrow amount");
        // 检查：当前债务 + 这次借款 不能超过 最大借款额。
        // 超过的话报错：“超过了允许的借款金额”。

        borrowBalances[msg.sender] = currentDebt + amount;
        // 更新你的借款余额 = 当前债务 + 这次借款。

        lastInterestAccrualTimestamp[msg.sender] = block.timestamp;
        // 更新上次计算利息的时间为当前时间。

        payable(msg.sender).transfer(amount);
        // 把借的钱转账给你。

        emit Borrow(msg.sender, amount);
        // 发出借款事件。
    }

    function repay() external payable {
        // 还款函数。调用时附上要还的钱。

        require(msg.value > 0, "Must repay a positive amount");
        // 检查：还的钱必须大于0。

        uint256 currentDebt = calculateInterestAccrued(msg.sender);
        // 计算你当前欠了多少钱（包含利息）。

        require(currentDebt > 0, "No debt to repay");
        // 检查：你确实有债务，否则报错：“没有债务需要还”。

        uint256 amountToRepay = msg.value;
        // 记录你要还多少钱（就是附带的ETH金额）。

        if (amountToRepay > currentDebt) {
            // 如果你还的钱超过了债务总额
            amountToRepay = currentDebt;
            // 实际只需要还债务总额
            payable(msg.sender).transfer(msg.value - currentDebt);
            // 把多余的钱退给你
        }

        borrowBalances[msg.sender] = currentDebt - amountToRepay;
        // 更新你的借款余额 = 当前债务 - 还掉的钱。

        lastInterestAccrualTimestamp[msg.sender] = block.timestamp;
        // 更新上次计算利息的时间为当前时间。

        emit Repay(msg.sender, amountToRepay);
        // 发出还款事件。
    }

    function calculateInterestAccrued(address user) public view returns (uint256) {
        // 计算某个用户当前欠了多少钱（包含利息）。
        // public：公开可调用。view：只读不修改状态。returns (uint256)：返回一个整数。

        if (borrowBalances[user] == 0) {
            // 如果借款余额是0
            return 0;
            // 直接返回0，没欠钱
        }

        uint256 timeElapsed = block.timestamp - lastInterestAccrualTimestamp[user];
        // 计算从上次计算利息到现在过去了多少秒。

        uint256 interest = (borrowBalances[user] * interestRateBasisPoints * timeElapsed) / (10000 * 365 days);
        // 计算这段时间产生的利息。
        // 公式：利息 = 借款本金 × 利率(基点) × 时间(秒) ÷ (10000 × 一年的秒数)
        // 365 days = 365天 × 24小时 × 60分钟 × 60秒

        return borrowBalances[user] + interest;
        // 返回本金 + 利息 = 当前总债务
    }

    function getMaxBorrowAmount(address user) external view returns (uint256) {
        // 获取某个用户最多能借多少钱。external view：只读外部函数。

        return (collateralBalances[user] * collateralFactorBasisPoints) / 10000;
        // 返回：抵押品 × 抵押因子 ÷ 10000
    }

    function getTotalLiquidity() external view returns (uint256) {
        // 获取资金池里总共有多少ETH。external view：只读外部函数。

        return address(this).balance;
        // 返回合约里所有的ETH余额
    }
}
// 