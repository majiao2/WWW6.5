// SPDX-License-Identifier: MIT
// 代码开源协议：MIT协议，大家可以随便用。

pragma solidity ^0.8.20;
// 这个合约需要用Solidity 0.8.20及以上版本编译。

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
// 导入ERC721接口（NFT的标准接口）。用来操作NFT的转账、查询等。

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
// 导入重入攻击防护。防止黑客在转账过程中反复调用合约函数偷钱。

contract NFTMarketplace is ReentrancyGuard {
// 定义一个合约叫"NFT市场"，它继承自ReentrancyGuard（防重入保护）。

    address public owner;
    // 合约所有者地址（管理员）。

    uint256 public marketplaceFeePercent; // 以基点为单位 (100 = 1%)
    // 市场手续费百分比，用基点表示。
    // 100基点 = 1%，10000基点 = 100%。例如设置250就是2.5%。

    address public feeRecipient;
    // 手续费接收地址（平台收的钱打给谁）。

    struct Listing {
        // 定义一个结构体，代表一个NFT的挂牌信息。
        
        address seller;
        // 卖家地址。
        
        address nftAddress;
        // NFT合约地址（一个NFT系列）。
        
        uint256 tokenId;
        // NFT的ID（同一个系列里的不同编号）。
        
        uint256 price;
        // 挂牌价格（单位：wei）。
        
        address royaltyReceiver;
        // 版税接收地址（NFT创作者收的钱打给谁）。
        
        uint256 royaltyPercent; // 以基点为单位
        // 版税百分比，用基点表示（比如500 = 5%）。
        
        bool isListed;
        // 是否正在挂牌中（true表示在卖，false表示已下架或已卖出）。
    }

    mapping(address => mapping(uint256 => Listing)) public listings;
    // 创建一个双层映射：NFT合约地址 → NFT的ID → 挂牌信息
    // 这样可以快速查询某个NFT是否在出售中。

    event Listed(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price,
        address royaltyReceiver,
        uint256 royaltyPercent
    );
    // 挂牌事件：谁，挂出了哪个NFT（哪个系列的几号），多少钱，版税给谁，版税多少。

    event Purchase(
        address indexed buyer,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price,
        address seller,
        address royaltyReceiver,
        uint256 royaltyAmount,
        uint256 marketplaceFeeAmount
    );
    // 购买事件：谁，买了哪个NFT，花了多少钱，卖家是谁，版税给了谁，版税多少，平台费多少。

    event Unlisted(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId
    );
    // 下架事件：谁，下架了哪个NFT。

    event FeeUpdated(
        uint256 newMarketplaceFee,
        address newFeeRecipient
    );
    // 手续费更新事件：新的手续费率，新的手续费接收地址。

    constructor(uint256 _marketplaceFeePercent, address _feeRecipient) {
        // 构造函数，部署时运行一次。设置手续费率和手续费接收地址。

        require(_marketplaceFeePercent <= 1000, "Marketplace fee too high (max 10%)");
        // 检查：手续费不能超过1000基点（10%）。太高了不合理。

        require(_feeRecipient != address(0), "Fee recipient cannot be zero");
        // 检查：手续费接收地址不能是0地址（必须有地方收钱）。

        owner = msg.sender;
        // 合约部署者成为所有者（管理员）。

        marketplaceFeePercent = _marketplaceFeePercent;
        // 设置手续费率。

        feeRecipient = _feeRecipient;
        // 设置手续费接收地址。
    }

    modifier onlyOwner() {
        // 定义一个修饰符，只有管理员才能调用某些函数。

        require(msg.sender == owner, "Only owner");
        // 检查：调用者必须是owner。

        _;
        // 执行原函数。
    }

    function setMarketplaceFeePercent(uint256 _newFee) external onlyOwner {
        // 设置新手续费率。只有管理员能调用。

        require(_newFee <= 1000, "Marketplace fee too high");
        // 检查：新费率不能超过10%。

        marketplaceFeePercent = _newFee;
        // 更新手续费率。

        emit FeeUpdated(_newFee, feeRecipient);
        // 发出手续费更新事件。
    }

    function setFeeRecipient(address _newRecipient) external onlyOwner {
        // 设置新手续费接收地址。只有管理员能调用。

        require(_newRecipient != address(0), "Invalid fee recipient");
        // 检查：新地址不能是0地址。

        feeRecipient = _newRecipient;
        // 更新手续费接收地址。

        emit FeeUpdated(marketplaceFeePercent, _newRecipient);
        // 发出手续费更新事件。
    }

    function listNFT(
        address nftAddress,
        uint256 tokenId,
        uint256 price,
        address royaltyReceiver,
        uint256 royaltyPercent
    ) external {
        // 挂牌出售NFT。任何人（卖家）都可以调用。

        require(price > 0, "Price must be above zero");
        // 检查：价格必须大于0。

        require(royaltyPercent <= 1000, "Max 10% royalty allowed");
        // 检查：版税不能超过10%（最高1000基点）。

        require(!listings[nftAddress][tokenId].isListed, "Already listed");
        // 检查：这个NFT不能已经挂牌了。如果已经在卖，不能重复挂牌。

        IERC721 nft = IERC721(nftAddress);
        // 把NFT合约地址转换成IERC721接口类型，方便调用NFT的方法。

        require(nft.ownerOf(tokenId) == msg.sender, "Not the owner");
        // 检查：调用者必须是这个NFT的当前持有者。

        require(
            nft.getApproved(tokenId) == address(this) || nft.isApprovedForAll(msg.sender, address(this)),
            "Marketplace not approved"
        );
        // 检查：市场合约是否被授权转移这个NFT。
        // 两种授权方式任选其一：
        // 1. getApproved(tokenId) == address(this)：专门授权这个市场合约转移这个NFT
        // 2. isApprovedForAll(msg.sender, address(this))：卖家授权市场合约转移他所有的NFT

        listings[nftAddress][tokenId] = Listing({
            // 创建挂牌信息并存储到mapping中。
            seller: msg.sender,
            // 卖家就是调用者。
            
            nftAddress: nftAddress,
            // NFT合约地址。
            
            tokenId: tokenId,
            // NFT的ID。
            
            price: price,
            // 挂牌价格。
            
            royaltyReceiver: royaltyReceiver,
            // 版税接收地址（创作者）。
            
            royaltyPercent: royaltyPercent,
            // 版税百分比。
            
            isListed: true
            // 标记为正在挂牌中。
        });

        emit Listed(msg.sender, nftAddress, tokenId, price, royaltyReceiver, royaltyPercent);
        // 发出挂牌事件。
    }

    function buyNFT(address nftAddress, uint256 tokenId) external payable nonReentrant {
        // 购买NFT。payable表示可以付ETH。nonReentrant防止重入攻击。

        Listing memory item = listings[nftAddress][tokenId];
        // 从存储中读取挂牌信息到内存（memory）中。

        require(item.isListed, "Not listed");
        // 检查：这个NFT确实在挂牌出售中。

        require(msg.value == item.price, "Incorrect ETH sent");
        // 检查：付的ETH必须等于挂牌价格。不能多也不能少。

        require(
            item.royaltyPercent + marketplaceFeePercent <= 10000,
            "Combined fees exceed 100%"
        );
        // 检查：版税 + 平台费不能超过100%（10000基点）。
        // 防止设置太高导致卖家拿不到钱。

        uint256 feeAmount = (msg.value * marketplaceFeePercent) / 10000;
        // 计算平台手续费金额 = 总价 × 平台费率 ÷ 10000

        uint256 royaltyAmount = (msg.value * item.royaltyPercent) / 10000;
        // 计算版税金额 = 总价 × 版税率 ÷ 10000

        uint256 sellerAmount = msg.value - feeAmount - royaltyAmount;
        // 卖家实际收到的钱 = 总价 - 手续费 - 版税

        // 市场费用
        if (feeAmount > 0) {
            // 如果手续费大于0
            payable(feeRecipient).transfer(feeAmount);
            // 把手续费转给平台钱包
        }

        // 创作者版税
        if (royaltyAmount > 0 && item.royaltyReceiver != address(0)) {
            // 如果版税大于0，并且版税接收地址不是0地址
            payable(item.royaltyReceiver).transfer(royaltyAmount);
            // 把版税转给创作者
        }

        // 卖家支付
        payable(item.seller).transfer(sellerAmount);
        // 把剩下的钱转给卖家

        // 将NFT转移给买家
        IERC721(item.nftAddress).safeTransferFrom(item.seller, msg.sender, item.tokenId);
        // 调用NFT合约，把NFT从卖家转给买家
        // safeTransferFrom是安全的转账方式，会检查接收方是否支持ERC721

        // 删除列表
        delete listings[nftAddress][tokenId];
        // 删除这个NFT的挂牌信息（已经卖出去了）

        emit Purchase(
            msg.sender,
            nftAddress,
            tokenId,
            msg.value,
            item.seller,
            item.royaltyReceiver,
            royaltyAmount,
            feeAmount
        );
        // 发出购买事件。
    }

    function cancelListing(address nftAddress, uint256 tokenId) external {
        // 下架NFT。卖家可以取消挂牌。

        Listing memory item = listings[nftAddress][tokenId];
        // 读取挂牌信息。

        require(item.isListed, "Not listed");
        // 检查：这个NFT确实在挂牌中。

        require(item.seller == msg.sender, "Not the seller");
        // 检查：调用者必须是卖家本人。只有卖家才能下架自己的NFT。

        delete listings[nftAddress][tokenId];
        // 删除挂牌信息。

        emit Unlisted(msg.sender, nftAddress, tokenId);
        // 发出下架事件。
    }

    function getListing(address nftAddress, uint256 tokenId) external view returns (Listing memory) {
        // 查看某个NFT的挂牌信息。view表示只读不修改状态。

        return listings[nftAddress][tokenId];
        // 返回挂牌信息。
    }

    receive() external payable {
        // receive是特殊函数，当有人直接向合约地址转账（不带calldata）时会触发。

        revert("Direct ETH not accepted");
        // 拒绝直接转账，报错："不接受直接转账"。
        // 想买NFT必须调用buyNFT函数。
    }

    fallback() external payable {
        // fallback是特殊函数，当有人调用了不存在的函数时触发。

        revert("Unknown function");
        // 报错："未知函数"。
    }
}
// 合约结束