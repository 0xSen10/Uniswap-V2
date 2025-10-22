pragma solidity =0.5.16;

import './interfaces/IUniswapV2Pair.sol';
import './UniswapV2ERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/IUniswapV2Factory.sol';
import './interfaces/IUniswapV2Callee.sol';

contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 {
    using SafeMath  for uint; // 使用 SafeMath 进行 uint 运算
    using UQ112x112 for uint224; // 使用 UQ112x112 库进行定点数运算

    uint public constant MINIMUM_LIQUIDITY = 10**3; // 最小流动性，防止初始份额过小
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));  // ERC20 transfer 函数选择器

    address public factory; // 工厂合约地址
    address public token0; // 代币0地址
    address public token1; // 代币1地址

    // 储备量（打包存储以节省gas）
    uint112 private reserve0;           // 代币0的储备量// uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // 代币1的储备量// uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast; // 最后更新时间戳// uses single storage slot, accessible via getReserves

    uint public price0CumulativeLast; // 代币0的价格累积值
    uint public price1CumulativeLast; // 代币1的价格累积值
    uint public kLast;  // 最近一次流动性事件后的 k 值 (reserve0 * reserve1)// reserve0 * reserve1, as of immediately after the most recent liquidity event

    // 重入锁
    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'UniswapV2: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    // 获取当前储备量
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0; // 代币0储备量
        _reserve1 = reserve1; // 代币1储备量  
        _blockTimestampLast = blockTimestampLast; // 最后更新时间
    }

    // 安全转账函数
    function _safeTransfer(address token, address to, uint value) private {
        // 调用代币合约的transfer函数
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'UniswapV2: TRANSFER_FAILED');
    }

    event Mint(address indexed sender, uint amount0, uint amount1); // 铸造LP代币事件
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap( // 交换事件
        address indexed sender, // 交易的发起者
        uint amount0In, // 代币0输入量
        uint amount1In, // 代币1输入量
        uint amount0Out,  // 代币0输出量
        uint amount1Out,  // 代币1输出量
        address indexed to  // 代币接收者
    );
    event Sync(uint112 reserve0, uint112 reserve1); // 储备量同步事件

    constructor() public {
        factory = msg.sender; // 设置工厂合约地址为部署者
    }

    // called once by the factory at time of deployment  // 初始化函数，由工厂合约在部署时调用一次
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, 'UniswapV2: FORBIDDEN'); // 只有工厂合约可以调用// sufficient check
        token0 = _token0; // 设置代币0地址
        token1 = _token1; // 设置代币1地址
    }

    // 更新储备量和价格累积器的内部函数 // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= uint112(-1) && balance1 <= uint112(-1), 'UniswapV2: OVERFLOW');// 检查余额是否超过uint112的最大值
        uint32 blockTimestamp = uint32(block.timestamp % 2**32); // 获取当前时间戳（取模防止溢出）
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;  // 计算时间流逝（允许溢出） overflow is desired
        // 如果时间已流逝且储备量不为零，更新价格累积器
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            // 更新代币0的价格累积器（reserve1/reserve0 * timeElapsed）
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            // 更新代币1的价格累积器（reserve1/reserve0 * timeElapsed）
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        // 更新储备量
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        // 触发同步事件
        emit Sync(reserve0, reserve1);
    }

    // 协议费用计算函数：如果费用开启，铸造相当于sqrt(k)增长1/6的流动性// if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        // 查询工厂合约的费用接收地址
        address feeTo = IUniswapV2Factory(factory).feeTo();
        // 判断费用是否开启（费用接收地址不为零地址）
        feeOn = feeTo != address(0);
        uint _kLast = kLast; // gas savings// gas优化：缓存kLast值
        if (feeOn) {
            if (_kLast != 0) {
                // 计算当前k值的平方根
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
                // 计算上一次k值的平方根
                uint rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    // 计算应铸造的流动性数量
                    uint numerator = totalSupply.mul(rootK.sub(rootKLast)); // 分子
                    uint denominator = rootK.mul(5).add(rootKLast);  // 分母
                    uint liquidity = numerator / denominator; // 流动性数量 = 1/6的增长
                    if (liquidity > 0) _mint(feeTo, liquidity); // 如果流动性大于0，铸造给费用接收地址
                }
            }
        } else if (_kLast != 0) {
            // 如果费用关闭，重置kLast
            kLast = 0;
        }
    }

    // 添加流动性函数：铸造LP代币（应由路由器合约调用）
    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external lock returns (uint liquidity) {
        // 获取当前储备量（gas优化）
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        // 获取合约当前代币余额
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        // 计算实际转入的代币数量
        uint amount0 = balance0.sub(_reserve0);
        uint amount1 = balance1.sub(_reserve1);

        // 计算并铸造协议费用
        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas优化：缓存总供应量// gas savings, must be defined here since totalSupply can update in _mintFee
        // 如果是首次添加流动性
        if (_totalSupply == 0) {
            // 计算流动性数量 = sqrt(amount0 * amount1) - 最小流动性
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
            // 永久锁定最小流动性到零地址
           _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            // 按比例计算流动性数量（取两种代币计算的最小值）
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }
        // 检查流动性数量是否大于0
        require(liquidity > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED');
        // 向接收地址铸造LP代币
        _mint(to, liquidity);

        // 更新储备量
        _update(balance0, balance1, _reserve0, _reserve1);
        // 如果费用开启，更新kLast
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // 移除流动性函数：销毁LP代币并返回基础代币（应由路由器合约调用）
    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();  // 获取当前储备量（gas优化）// gas savings
        // 缓存代币地址（gas优化）
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        // 获取合约当前代币余额
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        // 获取合约中持有的LP代币数量（由用户转账到此合约）
        uint liquidity = balanceOf[address(this)];

        // 计算并铸造协议费用
        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas优化：缓存总供应量// gas savings, must be defined here since totalSupply can update in _mintFee
        // 按比例计算应返回的代币数量
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
        // 检查代币数量是否都大于0
        require(amount0 > 0 && amount1 > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED');
        // 销毁LP代币
        _burn(address(this), liquidity);
        // 向接收地址转账代币0
        _safeTransfer(_token0, to, amount0);
        // 向接收地址转账代币1
        _safeTransfer(_token1, to, amount1);
        // 更新代币余额（转账后）
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        // 更新储备量
        _update(balance0, balance1, _reserve0, _reserve1);
        // 如果费用开启，更新kLast
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // 代币交换函数：执行代币兑换（支持闪电交换）
    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        // 检查输出量至少有一个大于0
        require(amount0Out > 0 || amount1Out > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT');
        // 获取当前储备量（gas优化）
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        // 检查输出量不超过储备量
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'UniswapV2: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        { // 作用域块：避免堆栈过深错误
            // 缓存代币地址
            address _token0 = token0;
            address _token1 = token1;
            // 检查接收地址不是代币合约地址
            require(to != _token0 && to != _token1, 'UniswapV2: INVALID_TO');
            // 乐观转账：先输出代币
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out);
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out);
            // 如果提供了数据，执行闪电交换回调
            if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
            // 获取转账后的余额
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        // 计算实际输入量
        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        // 检查输入量至少有一个大于0
        require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');
        
        { // 作用域块：避免堆栈过深错误
            // 计算调整后的余额（考虑0.3%手续费）
            uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3)); // 扣除0.3%手续费
            uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3)); // 扣除0.3%手续费
            // 检查恒定乘积公式：调整后的k >= 原来的k
            require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'UniswapV2: K');
        }
        // 更新储备量
        _update(balance0, balance1, _reserve0, _reserve1);
        // 触发交换事件
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // 提取多余代币函数：使余额匹配储备量
    // force balances to match reserves
    function skim(address to) external lock {
        // 缓存代币地址（gas优化）
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        // 转账多余的代币0（余额 - 储备量）
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
        // 转账多余的代币1（余额 - 储备量）
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
    }

    // 同步函数：强制使储备量匹配余额
    // force reserves to match balances
    function sync() external lock {
        // 更新储备量为当前余额
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }
}