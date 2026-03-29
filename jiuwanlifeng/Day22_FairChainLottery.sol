// SPDX-License-Identifier: MIT
// 这行是代码的开源协议声明，意思是“这个代码是开源的，遵循MIT协议，你可以随便用，但别赖我”。

pragma solidity ^0.8.20;
// “我写的这个代码，需要用Solidity版本0.8.20或更高版本才能编译。^符号表示只要不跳到大版本0.9.0，小版本升级都行。”

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
// “我要从Chainlink官方合约里，导入一个‘VRF消费者基础合约’。这个合约能让我向Chainlink的节点要一个随机数。”
// 就像你从工具箱里拿了一个“可以要随机数的工具”。

import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
// “再导入一个‘VRF客户端工具包’，它帮我格式化请求随机数的表单，就像填快递单一样。”

contract FairChainLottery is VRFConsumerBaseV2Plus {
// “我定义一个合约叫‘公平链上彩票’。它‘继承’了上面那个VRF消费者合约，所以它天生就能要随机数。”
// is 表示“我是它的女儿，拥有它的一切功能”。

    enum LOTTERY_STATE { OPEN, CLOSED, CALCULATING }
    // “我定义了一个‘彩票状态’的选项，只有三种：开门营业(OPEN)、关门歇业(CLOSED)、正在算奖(CALCULATING)。”
    // 就像店铺的状态牌：营业中，休息中，盘点中。

    LOTTERY_STATE public lotteryState;
    // “我创建了一个公共变量叫‘彩票状态’，类型就是上面那个选项。大家都可以看现在是营业还是关门。”

    address payable[] public players;
    // “我创建了一个‘玩家列表’，里面存的是每个玩家的地址（并且是可收款的地址）。用数组形式，排队存。”
    // payable 意味着这个地址能接收ETH。

    address public recentWinner;
    // “我记录一下‘最近一次中奖者的地址’，方便大家查。”

    uint256 public entryFee;
    // “这是‘门票价格’。你要参与，得付这么多ETH。”

    // Chainlink VRF 配置
    // 下面几个是给随机数生成器用的配置，就像设置“随机数生成器的参数”。

    uint256 public subscriptionId;
    // “这是我的‘订阅ID’。我需要先在Chainlink网站订阅随机数服务，他们会给我一个号码，我填在这里。”

    bytes32 public keyHash;
    // “这是‘钥匙的哈希值’，相当于指定我用哪个节点给我出随机数。不同节点收费不同。”

    uint32 public callbackGasLimit = 100000;
    // “当随机数回来时，它会调用我合约里的一个函数。这个函数执行能用的‘Gas上限’，防止它运行到一半没油了。”

    uint16 public requestConfirmations = 3;
    // “请求随机数后，我需要等待几个区块确认。3个区块，确保网络稳定了再告诉我结果。”

    uint32 public numWords = 1;
    // “我要几个随机数？1个就够了，用来抽一个中奖者。”

    uint256 public latestRequestId;
    // “我记录一下‘最后一次请求随机数的ID’。每次要随机数，都会生成一个唯一的请求号。”

    constructor(
        address vrfCoordinator,
        uint256 _subscriptionId,
        bytes32 _keyHash,
        uint256 _entryFee
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        // 这是‘构造函数’，只在合约部署的时候运行一次。就像新店开张时，设置一下基本参数。
        
        subscriptionId = _subscriptionId;
        // “把外面传进来的订阅ID存到我自己的变量里。”

        keyHash = _keyHash;
        // “把外面传进来的钥匙哈希存起来。”

        entryFee = _entryFee;
        // “把外面传进来的门票价格存起来。”

        lotteryState = LOTTERY_STATE.CLOSED;
        // “刚开始，彩票状态设为‘关门’。需要管理员手动开门才能开始玩。”
    }

    function enter() public payable {
        // “这是一个公开函数，叫‘入场’。它前面有个payable，表示调用这个函数时可以付钱。”

        require(lotteryState == LOTTERY_STATE.OPEN, "Lottery not open");
        // “第一道检查：彩票状态必须是‘开门’状态。如果没开门，就报错：‘彩票没开’。”

        require(msg.value >= entryFee, "Not enough ETH");
        // “第二道检查：你付的钱必须大于等于门票价格。付少了，报错：‘ETH不够’。”

        players.push(payable(msg.sender));
        // “检查通过后，把你的地址（msg.sender）加到玩家列表的最后面。push就是往数组末尾加一个。”
        // payable(msg.sender) 是确保地址是可收款类型。
    }

    function startLottery() external onlyOwner {
        // “这是‘开门’函数。只有管理员（onlyOwner）才能调用。”

        require(lotteryState == LOTTERY_STATE.CLOSED, "Can't start yet");
        // “检查：当前状态必须是‘关门’。如果已经是‘开门’或者‘算奖中’，就不能再开。”

        lotteryState = LOTTERY_STATE.OPEN;
        // “把状态改成‘开门’，欢迎大家来买票。”
    }

    function endLottery() external onlyOwner {
        // “这是‘结束彩票并开奖’的函数。也只有管理员能调用。”

        require(lotteryState == LOTTERY_STATE.OPEN, "Lottery not open");
        // “检查：当前状态必须是‘开门’。如果已经结束或正在算，就不能再结束。”

        lotteryState = LOTTERY_STATE.CALCULATING;
        // “先把状态改成‘正在算奖’，防止有人再买票。”

        // 下面开始准备向Chainlink要随机数
        VRFV2PlusClient.RandomWordsRequest memory req = VRFV2PlusClient.RandomWordsRequest({
            // “我创建了一个‘随机数请求单’（req），就像填一个表格。”

            keyHash: keyHash,
            // 填上：用哪个节点（钥匙哈希）

            subId: subscriptionId,
            // 填上：我的订阅ID

            requestConfirmations: requestConfirmations,
            // 填上：等几个区块确认（3个）

            callbackGasLimit: callbackGasLimit,
            // 填上：回调函数能用的Gas上限（10万）

            numWords: numWords,
            // 填上：我要几个随机数（1个）

            extraArgs: VRFV2PlusClient._argsToBytes(
                VRFV2PlusClient.ExtraArgsV1({nativePayment: true})
            )
            // 这行是额外设置，告诉Chainlink：“我用原生代币（ETH）支付随机数费用。”
        });

        latestRequestId = s_vrfCoordinator.requestRandomWords(req);
        // “我把填好的请求单，交给我的VRF协调器（s_vrfCoordinator，继承得来的），让它去要随机数。”
        // “这个函数会返回一个请求ID，我把它存到latestRequestId里，方便以后查。”
    }

    function fulfillRandomWords(uint256, uint256[] calldata randomWords) internal override {
        // “这是‘随机数送达’函数。当Chainlink拿到随机数后，会自动调用我这个函数。”
        // 第一个参数（requestId）我用不上，所以没写名字，只写了个类型uint256。
        // randomWords 是Chainlink给我的随机数数组，虽然我只要了一个，它还是用数组形式给我。

        require(lotteryState == LOTTERY_STATE.CALCULATING, "Not ready to pick winner");
        // “检查：当前状态必须是‘正在算奖’。如果不是，说明有人捣乱，拒绝。”

        uint256 winnerIndex = randomWords[0] % players.length;
        // “我拿到第一个随机数（randomWords[0]），用它除以玩家总人数，取余数。余数就是中奖者在玩家列表里的下标（索引）。”
        // 比如有5个人，随机数是123，123 % 5 = 3，那么第3个玩家中奖。

        address payable winner = players[winnerIndex];
        // “根据刚才算出的索引，从玩家列表里取出中奖者的地址。”

        recentWinner = winner;
        // “把中奖者的地址存到‘最近中奖者’的变量里，方便大家查询。”

        players = new address payable[](0);
        // “重置玩家列表：创建一个全新的空数组，相当于清空了所有玩家。下一轮重新开始。”

        lotteryState = LOTTERY_STATE.CLOSED;
        // “把彩票状态改回‘关门’。开奖完毕，等待管理员下次开门。”

        (bool sent, ) = winner.call{value: address(this).balance}("");
        // “给中奖者转账。把合约里所有的钱（address(this).balance）都转给中奖者。”
        // .call是底层的转账方式，更安全。sent是个布尔值，表示转账是否成功。

        require(sent, "Failed to send ETH to winner");
        // “如果转账失败（比如中奖者地址拒绝收款），就报错回滚，整个开奖过程取消。”
    }

    function getPlayers() external view returns (address payable[] memory) {
        // “这是一个只读的公共函数，任何人都能调用。它返回当前的玩家列表。”

        return players;
        // “直接返回players这个数组。”
    }
}