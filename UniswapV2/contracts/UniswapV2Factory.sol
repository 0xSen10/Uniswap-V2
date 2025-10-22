pragma solidity =0.5.16;

import './interfaces/IUniswapV2Factory.sol';
import './UniswapV2Pair.sol';

contract UniswapV2Factory is IUniswapV2Factory {
    address public feeTo; //协议费用接收地址
    address public feeToSetter; //有权设置 feeTo 地址的管理员

    // 映射：通过两种代币地址查询对应的交易对合约地址
    // getPair[tokenA][tokenB] = pairAddress
    mapping(address => mapping(address => address)) public getPair; //获取交易对地址映射
    address[] public allPairs; //存储所有已创建的交易对地址

    event PairCreated(address indexed token0, address indexed token1, address pair, uint); //交易对触发事件

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter; //初始化 feeToSetter
    }

    function allPairsLength() external view returns (uint) { //返回已创建的交易对总数
        return allPairs.length;
    }

    //创建交易对
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'UniswapV2: IDENTICAL_ADDRESSES');
        // 对代币地址进行排序，确保 token0 < token1
        // 这是为了确保无论输入顺序如何，相同的代币对总是得到相同的 token0 和 token1
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2: ZERO_ADDRESS');
        // 检查：该交易对是否已存在（避免重复创建）
        require(getPair[token0][token1] == address(0), 'UniswapV2: PAIR_EXISTS'); // single check is sufficient
        // 获取 UniswapV2Pair 合约的创建字节码
        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        // 计算盐值：使用排序后的代币地址生成唯一的 salt
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        // 使用 create2 操作码部署新合约
        // create2 可以根据确定的盐值预测合约地址
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt) //0：要发送的以太币数量（wei）
        } //add(bytecode, 32) ：字节码在内存中的起始位置  //mload(bytecode) - 字节码的长度
        // 初始化新创建的交易对合约
        IUniswapV2Pair(pair).initialize(token0, token1);
        // 更新映射：记录交易对地址
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction  // 反向也记录，方便查询
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    // 外部函数：设置协议费用接收地址
    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeTo = _feeTo;
    }

    // 外部函数：转移 feeToSetter 权限
    function setFeeToSetter(address _feeToSetter) external {
        // 只有当前的 feeToSetter 有权调用此函数
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}