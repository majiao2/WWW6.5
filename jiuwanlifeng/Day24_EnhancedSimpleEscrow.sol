// SPDX-License-Identifier: MIT
// 代码开源协议：MIT协议，大家随便用，但出问题别找我。

pragma solidity ^0.8.20;
// 这个合约需要用Solidity 0.8.20及以上版本编译。

/// @title EnhancedSimpleEscrow - 具有超时、取消和事件的安全托管合约
// 合约标题注释：这是一个增强版托管合约，支持超时、取消功能，还有事件记录。

contract EnhancedSimpleEscrow {
// 定义一个合约叫"增强版简单托管"。

    enum EscrowState { AWAITING_PAYMENT, AWAITING_DELIVERY, COMPLETE, DISPUTED, CANCELLED }
    // 定义托管状态的枚举（就像五个选项）：
    // 0: AWAITING_PAYMENT 等待付款（买家还没打钱）
    // 1: AWAITING_DELIVERY 等待发货/确认（钱已到账，等卖家发货）
    // 2: COMPLETE 完成交易（钱已转给卖家）
    // 3: DISPUTED 争议中（买卖双方吵架了）
    // 4: CANCELLED 已取消（交易取消，钱退给买家）

    address public immutable buyer;
    // 买家地址。immutable表示合约部署后就不能改，省gas费。
    // 谁部署这个合约，谁就是买家。

    address public immutable seller;
    // 卖家地址。部署合约时指定，之后不能改。

    address public immutable arbiter;
    // 仲裁者地址（第三方调解人）。部署时指定，之后不能改。

    uint256 public amount;
    // 托管金额。买家存了多少钱。

    EscrowState public state;
    // 当前托管状态（上面那五种状态之一）。

    uint256 public depositTime;
    // 存款时间戳。记录买家什么时候打的钱。

    uint256 public deliveryTimeout; // 存款后的持续时间（以秒为单位）
    // 发货超时时间（秒）。比如设置7天，超过7天没确认收货，买家可以取消。

    event PaymentDeposited(address indexed buyer, uint256 amount);
    // 付款存入事件：谁（买家）存了多少钱。

    event DeliveryConfirmed(address indexed buyer, address indexed seller, uint256 amount);
    // 确认收货事件：买家确认收到货，钱转给卖家。

    event DisputeRaised(address indexed initiator);
    // 发起争议事件：谁（买家或卖家）发起了争议。

    event DisputeResolved(address indexed arbiter, address recipient, uint256 amount);
    // 争议解决事件：仲裁者把钱给了谁，给了多少。

    event EscrowCancelled(address indexed initiator);
    // 取消托管事件：谁取消的。

    event DeliveryTimeoutReached(address indexed buyer);
    // 超时事件：买家超时没确认，触发退款。

    constructor(address _seller, address _arbiter, uint256 _deliveryTimeout) {
        // 构造函数，部署时运行一次。设置初始参数。

        require(_deliveryTimeout > 0, "Delivery timeout must be greater than zero");
        // 检查：超时时间必须大于0秒。不能是0，否则立刻就能退款。

        buyer = msg.sender;
        // 买家就是部署这个合约的人（msg.sender）。

        seller = _seller;
        // 卖家是传入的地址。

        arbiter = _arbiter;
        // 仲裁者是传入的地址。

        state = EscrowState.AWAITING_PAYMENT;
        // 初始状态：等待付款。

        deliveryTimeout = _deliveryTimeout;
        // 设置超时时间（比如7天 = 604800秒）。
    }

    receive() external payable {
        // receive是特殊函数，当有人直接向合约地址转账时会触发。

        revert("Direct payments not allowed");
        // 拒绝直接转账，报错：“不允许直接付款”。
        // 想付钱必须调用deposit()函数。
    }

    function deposit() external payable {
        // 存款函数。买家调用这个函数来付钱。payable表示可以附带ETH。

        require(msg.sender == buyer, "Only buyer can deposit");
        // 检查：只有买家才能调用。别人不能替买家付钱。

        require(state == EscrowState.AWAITING_PAYMENT, "Already paid");
        // 检查：当前状态必须是"等待付款"。如果已经付过了，不能再付。

        require(msg.value > 0, "Amount must be greater than zero");
        // 检查：付的钱必须大于0。

        amount = msg.value;
        // 记录托管金额（就是买家付的钱）。

        state = EscrowState.AWAITING_DELIVERY;
        // 状态改成"等待发货/确认"。

        depositTime = block.timestamp;
        // 记录存款时间（当前区块的时间戳）。

        emit PaymentDeposited(buyer, amount);
        // 发出付款事件。
    }

    function confirmDelivery() external {
        // 确认收货函数。买家确认收到货后调用。

        require(msg.sender == buyer, "Only buyer can confirm");
        // 检查：只有买家才能确认收货。

        require(state == EscrowState.AWAITING_DELIVERY, "Not in delivery state");
        // 检查：当前状态必须是"等待发货/确认"。

        state = EscrowState.COMPLETE;
        // 状态改成"完成"。

        payable(seller).transfer(amount);
        // 把托管金额（amount）转账给卖家。

        emit DeliveryConfirmed(buyer, seller, amount);
        // 发出确认收货事件。
    }

    function raiseDispute() external {
        // 发起争议函数。买卖双方吵架时调用。

        require(msg.sender == buyer || msg.sender == seller, "Not authorized");
        // 检查：只有买家或卖家才能发起争议。其他人不行。

        require(state == EscrowState.AWAITING_DELIVERY, "Can't dispute now");
        // 检查：当前状态必须是"等待发货/确认"。钱已经存了但还没确认收货，才能争议。

        state = EscrowState.DISPUTED;
        // 状态改成"争议中"。

        emit DisputeRaised(msg.sender);
        // 发出争议事件，记录是谁发起的。
    }

    function resolveDispute(bool _releaseToSeller) external {
        // 解决争议函数。仲裁者调用，决定钱给谁。

        require(msg.sender == arbiter, "Only arbiter can resolve");
        // 检查：只有仲裁者才能解决争议。

        require(state == EscrowState.DISPUTED, "No dispute to resolve");
        // 检查：当前状态必须是"争议中"。没争议不能解决。

        state = EscrowState.COMPLETE;
        // 状态改成"完成"。

        if (_releaseToSeller) {
            // 如果_releaseToSeller是true，把钱给卖家
            payable(seller).transfer(amount);
            emit DisputeResolved(arbiter, seller, amount);
            // 发出争议解决事件：仲裁者决定把钱给卖家。
        } else {
            // 如果_releaseToSeller是false，把钱退给买家
            payable(buyer).transfer(amount);
            emit DisputeResolved(arbiter, buyer, amount);
            // 发出争议解决事件：仲裁者决定把钱给买家。
        }
    }

    function cancelAfterTimeout() external {
        // 超时取消函数。如果卖家一直不发货，买家超时后可以取消。

        require(msg.sender == buyer, "Only buyer can trigger timeout cancellation");
        // 检查：只有买家才能触发超时取消。

        require(state == EscrowState.AWAITING_DELIVERY, "Cannot cancel in current state");
        // 检查：当前状态必须是"等待发货/确认"。

        require(block.timestamp >= depositTime + deliveryTimeout, "Timeout not reached");
        // 检查：当前时间 >= 存款时间 + 超时时间
        // 比如存款时间是第1天，超时7天，那么第8天之后才能取消。
        // 如果还没到时间，不能取消。

        state = EscrowState.CANCELLED;
        // 状态改成"已取消"。

        payable(buyer).transfer(address(this).balance);
        // 把合约里所有的钱（就是托管金额）退给买家。

        emit EscrowCancelled(buyer);
        // 发出取消事件。

        emit DeliveryTimeoutReached(buyer);
        // 发出超时事件。
    }

    function cancelMutual() external {
        // 双方协商取消函数。买卖双方商量好了一起取消。

        require(msg.sender == buyer || msg.sender == seller, "Not authorized");
        // 检查：只有买家或卖家才能调用。

        require(
            state == EscrowState.AWAITING_DELIVERY || state == EscrowState.AWAITING_PAYMENT,
            "Cannot cancel now"
        );
        // 检查：当前状态必须是"等待付款"或"等待发货"。
        // 如果已经完成、争议中或已取消，就不能再取消。

        EscrowState previousState = state;
        // 记录之前的状态（因为下面要改了）。

        state = EscrowState.CANCELLED;
        // 状态改成"已取消"。

        if (previousState == EscrowState.AWAITING_DELIVERY) {
            // 如果之前是"等待发货"状态（说明买家已经付过钱了）
            payable(buyer).transfer(address(this).balance);
            // 把合约里的钱退给买家
        }
        // 如果之前是"等待付款"状态，还没人付钱，就不用退款

        emit EscrowCancelled(msg.sender);
        // 发出取消事件。
    }

    function getTimeLeft() external view returns (uint256) {
        // 查看剩余时间的函数。返回距离超时还有多少秒。

        if (state != EscrowState.AWAITING_DELIVERY) return 0;
        // 如果不是"等待发货"状态，返回0（因为超时机制只在等待发货时有效）。

        if (block.timestamp >= depositTime + deliveryTimeout) return 0;
        // 如果已经超时了，返回0。

        return (depositTime + deliveryTimeout) - block.timestamp;
        // 返回：还剩多少秒 = (存款时间+超时时间) - 当前时间
    }
}
// 合约结束