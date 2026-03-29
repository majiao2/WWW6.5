// SPDX-License-Identifier: MIT
// 代码开源协议：MIT协议，大家可以随便用。

pragma solidity ^0.8.20;
// 这个合约需要用Solidity 0.8.20及以上版本编译。

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// 从OpenZeppelin导入ERC20标准合约。这个合约自己也会变成一个ERC20代币（流动性代币）。

/// @title Automated Market Maker with Liquidity Token
// 合约标题：带流动性代币的自动化做市商

contract AutomatedMarketMaker is ERC20 {
// 定义一个合约叫"自动化做市商"，它继承自ERC20。
// 这意味着这个合约本身就是一个代币，叫"流动性代币"（LP Token），代表你在资金池里的份额。

    IERC20 public tokenA;
    // 交易对中的第一个代币（比如USDT）。IERC20是接口类型。

    IERC20 public tokenB;
    // 交易对中的第二个代币（比如ETH）。

    uint256 public reserveA;
    // 资金池中tokenA的储备量。x * y = k 公式里的x。

    uint256 public reserveB;
    // 资金池中tokenB的储备量。x * y = k 公式里的y。

    address public owner;
    // 合约部署者地址（管理员）。

    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 liquidity);
    // 添加流动性事件：谁，添加了多少tokenA，多少tokenB，获得了多少LP代币。

    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB, uint256 liquidity);
    // 移除流动性事件：谁，取回了多少tokenA，多少tokenB，销毁了多少LP代币。

    event TokensSwapped(address indexed trader, address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut);
    // 兑换事件：谁，用什么代币换了什么代币，各换了多少。

    constructor(address _tokenA, address _tokenB, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        // 构造函数，部署时运行。传入两个代币地址，以及LP代币的名称和符号。
        // ERC20(_name, _symbol) 是调用父类ERC20的构造函数，设置LP代币的名字（比如"USDT-ETH LP"）。

        tokenA = IERC20(_tokenA);
        // 把传入的tokenA地址存起来，并转换成IERC20接口类型。

        tokenB = IERC20(_tokenB);
        // 把传入的tokenB地址存起来。

        owner = msg.sender;
        // 记录合约部署者地址。
    }

    /// @notice Add liquidity to the pool
    // 注释：向资金池添加流动性

    function addLiquidity(uint256 amountA, uint256 amountB) external {
        // 添加流动性函数。传入要添加的tokenA数量和tokenB数量。

        require(amountA > 0 && amountB > 0, "Amounts must be > 0");
        // 检查：两种代币的数量都必须大于0。

        tokenA.transferFrom(msg.sender, address(this), amountA);
        // 从调用者钱包里转出amountA个tokenA到合约地址（资金池）。

        tokenB.transferFrom(msg.sender, address(this), amountB);
        // 从调用者钱包里转出amountB个tokenB到合约地址（资金池）。

        uint256 liquidity;
        // 声明一个变量，记录要铸造多少LP代币给流动性提供者。

        if (totalSupply() == 0) {
            // 如果当前LP代币总供应量为0（这是第一次添加流动性）
            liquidity = sqrt(amountA * amountB);
            // 流动性代币数量 = sqrt(数量A × 数量B)
            // 这是Uniswap V2的公式，确保初始价格 = amountA/amountB
        } else {
            // 如果不是第一次添加
            liquidity = min(
                amountA * totalSupply() / reserveA,
                amountB * totalSupply() / reserveB
            );
            // 根据你添加的两种代币数量，分别计算应该获得的LP代币数量，取较小值
            // 公式：LP = min( 添加的A × 总LP ÷ 池子A, 添加的B × 总LP ÷ 池子B )
            // 这样可以确保添加的比例和现有池子比例一致
        }

        _mint(msg.sender, liquidity);
        // 铸造liquidity数量的LP代币，发给调用者。_mint是ERC20自带的方法。

        reserveA += amountA;
        // 更新tokenA储备量：增加amountA

        reserveB += amountB;
        // 更新tokenB储备量：增加amountB

        emit LiquidityAdded(msg.sender, amountA, amountB, liquidity);
        // 发出添加流动性事件。
    }

    /// @notice Remove liquidity from the pool
    // 注释：从资金池移除流动性

    function removeLiquidity(uint256 liquidityToRemove) external returns (uint256 amountAOut, uint256 amountBOut) {
        // 移除流动性函数。传入要销毁的LP代币数量。
        // 返回两个值：取回的tokenA数量和tokenB数量。

        require(liquidityToRemove > 0, "Liquidity to remove must be > 0");
        // 检查：要移除的LP数量必须大于0。

        require(balanceOf(msg.sender) >= liquidityToRemove, "Insufficient liquidity tokens");
        // 检查：你的LP代币余额足够。

        uint256 totalLiquidity = totalSupply();
        // 获取当前LP代币总供应量。

        require(totalLiquidity > 0, "No liquidity in the pool");
        // 检查：总供应量大于0（资金池不是空的）。

        amountAOut = liquidityToRemove * reserveA / totalLiquidity;
        // 计算你能取回多少tokenA：
        // 公式 = (你销毁的LP ÷ 总LP) × 池子里tokenA的总量
        // 你占的份额比例 × tokenA总量

        amountBOut = liquidityToRemove * reserveB / totalLiquidity;
        // 计算你能取回多少tokenB：
        // 公式 = (你销毁的LP ÷ 总LP) × 池子里tokenB的总量

        require(amountAOut > 0 && amountBOut > 0, "Insufficient reserves for requested liquidity");
        // 检查：两种代币都能取回正数（防止四舍五入为0）。

        reserveA -= amountAOut;
        // 从储备中减去要取出的tokenA。

        reserveB -= amountBOut;
        // 从储备中减去要取出的tokenB。

        _burn(msg.sender, liquidityToRemove);
        // 销毁你的LP代币。_burn是ERC20自带的方法。

        tokenA.transfer(msg.sender, amountAOut);
        // 把tokenA转给你。

        tokenB.transfer(msg.sender, amountBOut);
        // 把tokenB转给你。

        emit LiquidityRemoved(msg.sender, amountAOut, amountBOut, liquidityToRemove);
        // 发出移除流动性事件。

        return (amountAOut, amountBOut);
        // 返回取回的两种代币数量。
    }

    /// @notice Swap token A for token B
    // 注释：用tokenA兑换tokenB

    function swapAforB(uint256 amountAIn, uint256 minBOut) external {
        // 用tokenA换tokenB。传入：要卖出的tokenA数量，最少能接受多少tokenB（防滑点）。

        require(amountAIn > 0, "Amount must be > 0");
        // 检查：卖出的数量必须大于0。

        require(reserveA > 0 && reserveB > 0, "Insufficient reserves");
        // 检查：资金池里两种代币都有储备。

        uint256 amountAInWithFee = amountAIn * 997 / 1000;
        // 扣除0.3%的手续费（Uniswap标准费率）。
        // 997/1000 = 0.997，即扣除0.3%后实际进入池子的数量。
        // 手续费留在了池子里，会分给流动性提供者。

        uint256 amountBOut = reserveB * amountAInWithFee / (reserveA + amountAInWithFee);
        // 计算能换出多少tokenB。
        // 公式（恒定乘积公式 x*y=k）：
        // 新储备A = 原储备A + 扣费后的A
        // 新储备B = 原储备B - 输出B
        // 根据 x*y = k，推出：
        // 输出B = 原储备B × 扣费后A ÷ (原储备A + 扣费后A)

        require(amountBOut >= minBOut, "Slippage too high");
        // 检查：实际能换出的数量 >= 你设定的最小接受数量。
        // 如果滑点太大，交易失败，保护你不被抢跑攻击。

        tokenA.transferFrom(msg.sender, address(this), amountAIn);
        // 从你钱包转出amountAIn个tokenA到合约。

        tokenB.transfer(msg.sender, amountBOut);
        // 把计算出的tokenB转给你。

        reserveA += amountAInWithFee;
        // 更新tokenA储备：增加扣费后的数量（手续费留在池子里了）。

        reserveB -= amountBOut;
        // 更新tokenB储备：减少输出的数量。

        emit TokensSwapped(msg.sender, address(tokenA), amountAIn, address(tokenB), amountBOut);
        // 发出兑换事件。
    }

    /// @notice Swap token B for token A
    // 注释：用tokenB兑换tokenA（逻辑完全对称）

    function swapBforA(uint256 amountBIn, uint256 minAOut) external {
        // 用tokenB换tokenA。

        require(amountBIn > 0, "Amount must be > 0");
        require(reserveA > 0 && reserveB > 0, "Insufficient reserves");

        uint256 amountBInWithFee = amountBIn * 997 / 1000;
        // 扣除0.3%手续费。

        uint256 amountAOut = reserveA * amountBInWithFee / (reserveB + amountBInWithFee);
        // 计算能换出多少tokenA。

        require(amountAOut >= minAOut, "Slippage too high");

        tokenB.transferFrom(msg.sender, address(this), amountBIn);
        // 从你钱包转出tokenB。

        tokenA.transfer(msg.sender, amountAOut);
        // 把tokenA转给你。

        reserveB += amountBInWithFee;
        // 更新tokenB储备（扣费后的数量）。

        reserveA -= amountAOut;
        // 更新tokenA储备。

        emit TokensSwapped(msg.sender, address(tokenB), amountBIn, address(tokenA), amountAOut);
        // 发出兑换事件。
    }

    /// @notice View the current reserves
    // 注释：查看当前储备量

    function getReserves() external view returns (uint256, uint256) {
        // 只读函数，返回当前两种代币的储备量。

        return (reserveA, reserveB);
        // 返回(reserveA, reserveB)
    }

    /// @dev Utility: Return the smaller of two values
    // 注释：工具函数，返回两个数中较小的那个

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        // internal：只能被合约内部调用。pure：不读取也不修改状态。
        return a < b ? a : b;
        // 如果a小于b，返回a，否则返回b（三元运算符）。
    }

    /// @dev Utility: Babylonian square root
    // 注释：巴比伦平方根算法（牛顿迭代法）

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        // 计算y的平方根。internal pure：内部调用，只读。

        if (y > 3) {
            // 如果y大于3
            z = y;
            // z初始等于y
            uint256 x = y / 2 + 1;
            // x = y/2 + 1
            while (x < z) {
                // 当x小于z时循环
                z = x;
                // z更新为x
                x = (y / x + x) / 2;
                // 牛顿迭代公式：x_new = (y/x_old + x_old) / 2
            }
        } else if (y != 0) {
            // 如果y是1,2,3
            z = 1;
            // 平方根是1
        }
        // 如果y=0，z默认就是0
    }
}
// 合约结束