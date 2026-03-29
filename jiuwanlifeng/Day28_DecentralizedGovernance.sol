// SPDX-License-Identifier: MIT
// 代码开源协议：MIT协议，大家可以随便用。

pragma solidity ^0.8.0;
// 这个合约需要用Solidity 0.8.0及以上版本编译。

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// 导入ERC20接口（代币标准接口）。用来操作治理代币的转账、余额查询等。

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
// 导入重入攻击防护。防止黑客在转账过程中反复调用合约函数偷钱。

contract DecentralizedGovernance is ReentrancyGuard {
// 定义一个合约叫"去中心化治理"，它继承自ReentrancyGuard（防重入保护）。

    IERC20 public governanceToken;
    // 治理代币。持有这个代币的人可以参与投票。
    // 代币数量 = 投票权重。

    struct Proposal {
        // 定义一个结构体，代表一个治理提案。
        
        address proposer;
        // 提案发起人地址。
        
        string description;
        // 提案描述（比如"是否增加国库资金？"）。
        
        uint256 forVotes;
        // 赞成票总数（按代币权重累计）。
        
        uint256 againstVotes;
        // 反对票总数（按代币权重累计）。
        
        uint256 startTime;
        // 投票开始时间戳。
        
        uint256 endTime;
        // 投票结束时间戳。
        
        bool executed;
        // 是否已执行（true表示已经执行过了）。
        
        bool canceled;
        // 是否已取消（true表示提案被取消了）。
        
        uint256 timelockEnd;
        // 时间锁结束时间戳。提案通过后需要等待一段时间才能执行。
    }

    mapping(uint256 => Proposal) public proposals;
    // 创建一个映射：提案ID → 提案详情。
    // 存储所有提案的信息。

    mapping(uint256 => mapping(address => bool)) public hasVoted;
    // 创建一个双重映射：提案ID → 投票者地址 → 是否已投票。
    // 防止同一个地址对同一个提案重复投票。

    uint256 public nextProposalId;
    // 下一个提案的ID（自动递增）。初始为0，第一个提案ID是0。

    uint256 public votingDuration;
    // 投票持续时间（秒）。比如设置7天 = 604800秒。

    uint256 public timelockDuration;
    // 时间锁持续时间（秒）。提案通过后要等这么久才能执行。
    // 给社区时间检查提案，如果发现恶意提案可以提前退出。

    address public admin;
    // 管理员地址（合约部署者）。可以修改一些参数。

    uint256 public quorumPercentage;
    // 法定人数百分比。需要至少这么多比例的代币参与投票，提案才能通过。
    // 比如设置4%，需要总供应量的4%参与投票。

    uint256 public proposalDepositAmount;
    // 提案押金金额。发起提案需要抵押一定数量的治理代币。
    // 防止垃圾提案，提案通过后退还。

    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description);
    // 提案创建事件：提案ID，发起人，描述。

    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    // 投票事件：提案ID，投票者，是否支持，投票权重。

    event ProposalExecuted(uint256 indexed proposalId);
    // 提案执行事件：提案ID。

    event QuorumNotMet(uint256 indexed proposalId);
    // 未达到法定人数事件：提案ID。

    event ProposalTimelockStarted(uint256 indexed proposalId);
    // 提案进入时间锁事件：提案ID。

    modifier onlyAdmin() {
        // 定义一个修饰符，只有管理员才能调用某些函数。

        require(msg.sender == admin, "Not admin");
        // 检查：调用者必须是admin。

        _;
        // 执行原函数。
    }

    constructor(
        address _governanceToken,
        uint256 _votingDuration,
        uint256 _timelockDuration,
        uint256 _quorumPercentage,
        uint256 _proposalDepositAmount
    ) {
        // 构造函数，部署时运行一次。设置所有初始参数。

        require(_governanceToken != address(0), "Invalid token");
        // 检查：治理代币地址不能是0地址。

        require(_votingDuration > 0, "Invalid duration");
        // 检查：投票持续时间必须大于0。

        require(_quorumPercentage > 0 && _quorumPercentage <= 100, "Invalid quorum");
        // 检查：法定人数必须在1%到100%之间。

        governanceToken = IERC20(_governanceToken);
        // 设置治理代币地址。

        votingDuration = _votingDuration;
        // 设置投票持续时间。

        timelockDuration = _timelockDuration;
        // 设置时间锁持续时间。

        admin = msg.sender;
        // 合约部署者成为管理员。

        quorumPercentage = _quorumPercentage;
        // 设置法定人数百分比。

        proposalDepositAmount = _proposalDepositAmount;
        // 设置提案押金金额。
    }

    // 创建提案
    function createProposal(string memory description) external returns (uint256) {
        // 创建提案函数。传入提案描述，返回提案ID。

        require(bytes(description).length > 0, "Empty description");
        // 检查：描述不能是空字符串。

        // 收取提案押金
        if (proposalDepositAmount > 0) {
            // 如果押金金额大于0
            governanceToken.transferFrom(msg.sender, address(this), proposalDepositAmount);
            // 从发起人钱包转出押金到合约地址
        }

        uint256 proposalId = nextProposalId++;
        // 生成提案ID：先取当前nextProposalId的值，然后自增1。
        // 第一个提案ID是0，第二个是1，以此类推。

        proposals[proposalId] = Proposal({
            // 创建提案结构体并存储。
            
            proposer: msg.sender,
            // 发起人是调用者。
            
            description: description,
            // 提案描述。
            
            forVotes: 0,
            // 初始赞成票为0。
            
            againstVotes: 0,
            // 初始反对票为0。
            
            startTime: block.timestamp,
            // 投票开始时间 = 当前时间。
            
            endTime: block.timestamp + votingDuration,
            // 投票结束时间 = 当前时间 + 投票持续时间。
            
            executed: false,
            // 初始未执行。
            
            canceled: false,
            // 初始未取消。
            
            timelockEnd: 0
            // 初始时间锁结束时间为0（未设置）。
        });

        emit ProposalCreated(proposalId, msg.sender, description);
        // 发出提案创建事件。

        return proposalId;
        // 返回提案ID。
    }

    // 投票
    function vote(uint256 proposalId, bool support) external {
        // 投票函数。传入提案ID，是否支持。

        Proposal storage proposal = proposals[proposalId];
        // 获取提案信息（storage引用，可以修改）。

        require(block.timestamp >= proposal.startTime, "Not started");
        // 检查：投票还没开始（时间未到）。

        require(block.timestamp <= proposal.endTime, "Ended");
        // 检查：投票已经结束。

        require(!proposal.executed, "Already executed");
        // 检查：提案还没被执行。

        require(!proposal.canceled, "Canceled");
        // 检查：提案还没被取消。

        require(!hasVoted[proposalId][msg.sender], "Already voted");
        // 检查：这个地址还没对这个提案投过票。

        uint256 weight = governanceToken.balanceOf(msg.sender);
        // 获取投票者的治理代币余额（投票权重）。
        // 1个代币 = 1票。

        require(weight > 0, "No voting power");
        // 检查：必须有投票权（代币余额>0）。

        hasVoted[proposalId][msg.sender] = true;
        // 标记这个地址已经投票。

        if (support) {
            // 如果投票支持
            proposal.forVotes += weight;
            // 赞成票增加weight
        } else {
            // 如果投票反对
            proposal.againstVotes += weight;
            // 反对票增加weight
        }

        emit Voted(proposalId, msg.sender, support, weight);
        // 发出投票事件。
    }

    // 完成提案（进入时间锁或取消）
    function finalizeProposal(uint256 proposalId) external {
        // 完成提案函数。投票结束后调用，决定提案是否通过。

        Proposal storage proposal = proposals[proposalId];
        // 获取提案信息。

        require(block.timestamp > proposal.endTime, "Voting not ended");
        // 检查：投票已经结束（当前时间 > 结束时间）。

        require(!proposal.executed, "Already executed");
        // 检查：提案还没执行。

        require(!proposal.canceled, "Canceled");
        // 检查：提案还没取消。

        uint256 totalVotes = proposal.forVotes + proposal.againstVotes;
        // 计算总投票数（赞成+反对）。

        uint256 totalSupply = governanceToken.totalSupply();
        // 获取治理代币总供应量。

        uint256 quorumRequired = (totalSupply * quorumPercentage) / 100;
        // 计算法定人数要求 = 总供应量 × 法定人数百分比 ÷ 100
        // 例如：总供应量100万，法定人数4%，需要至少4万票参与。

        if (totalVotes >= quorumRequired && proposal.forVotes > proposal.againstVotes) {
            // 如果满足两个条件：
            // 1. 总投票数达到法定人数
            // 2. 赞成票 > 反对票
            
            if (timelockDuration > 0) {
                // 如果时间锁持续时间大于0
                proposal.timelockEnd = block.timestamp + timelockDuration;
                // 设置时间锁结束时间 = 当前时间 + 时间锁持续时间
                emit ProposalTimelockStarted(proposalId);
                // 发出提案进入时间锁事件
            } else {
                // 如果没有时间锁（timelockDuration = 0）
                proposal.executed = true;
                // 直接标记为已执行
                _refundDeposit(proposalId);
                // 退还押金
                emit ProposalExecuted(proposalId);
                // 发出提案执行事件
            }
        } else {
            // 如果不满足条件（未达法定人数或反对票更多）
            proposal.canceled = true;
            // 标记提案为已取消
            emit QuorumNotMet(proposalId);
            // 发出未达法定人数事件
            // 注意：押金不退！防止垃圾提案
        }
    }

    // 执行提案
    function executeProposal(uint256 proposalId) external {
        // 执行提案函数。时间锁结束后调用，真正执行提案。

        Proposal storage proposal = proposals[proposalId];
        // 获取提案信息。

        require(proposal.timelockEnd > 0, "No timelock set");
        // 检查：提案已经设置了时间锁（说明已经通过finalizeProposal）。

        require(block.timestamp >= proposal.timelockEnd, "Timelock not ended");
        // 检查：时间锁已经结束（当前时间 >= 时间锁结束时间）。

        require(!proposal.executed, "Already executed");
        // 检查：提案还没执行。

        require(!proposal.canceled, "Canceled");
        // 检查：提案还没取消。

        proposal.executed = true;
        // 标记提案为已执行。

        _refundDeposit(proposalId);
        // 退还押金。

        emit ProposalExecuted(proposalId);
        // 发出提案执行事件。
        
        // 注意：这个合约没有实际执行提案内容的代码！
        // 在实际应用中，需要继承这个合约，重写execute逻辑。
    }

    // 退还押金
    function _refundDeposit(uint256 proposalId) internal {
        // 内部函数：退还提案押金。

        if (proposalDepositAmount > 0) {
            // 如果押金金额大于0
            Proposal storage proposal = proposals[proposalId];
            // 获取提案信息
            governanceToken.transfer(proposal.proposer, proposalDepositAmount);
            // 把押金退还给提案发起人
        }
    }

    // 获取提案结果
    function getProposalResult(uint256 proposalId) external view returns (
        bool passed,
        uint256 forVotes,
        uint256 againstVotes,
        bool executed
    ) {
        // 查看提案结果的函数。返回：是否通过，赞成票数，反对票数，是否已执行。

        Proposal memory proposal = proposals[proposalId];
        // 获取提案信息（memory副本，只读）。

        passed = proposal.forVotes > proposal.againstVotes;
        // 是否通过 = 赞成票 > 反对票

        return (passed, proposal.forVotes, proposal.againstVotes, proposal.executed);
        // 返回结果。
    }

    // 管理员设置参数
    function setQuorumPercentage(uint256 _newQuorum) external onlyAdmin {
        // 设置新法定人数百分比。只有管理员能调用。

        require(_newQuorum > 0 && _newQuorum <= 100, "Invalid quorum");
        // 检查：新值必须在1%到100%之间。

        quorumPercentage = _newQuorum;
        // 更新法定人数百分比。
    }

    function setProposalDepositAmount(uint256 _newAmount) external onlyAdmin {
        // 设置新提案押金金额。只有管理员能调用。

        proposalDepositAmount = _newAmount;
        // 更新提案押金金额。
    }
}
// 合约结束