pragma solidity >=0.5.0;

interface IUniswapV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint); //触发交易对

    function feeTo() external view returns (address); // 视图函数：获取协议费用接收地址
    function feeToSetter() external view returns (address); // 视图函数：获取费用设置权限地址

    function getPair(address tokenA, address tokenB) external view returns (address pair); // 视图函数：根据两种代币地址获取对应的交易对地址
    function allPairs(uint) external view returns (address pair); // 视图函数：通过索引获取所有交易对中的某一个
    function allPairsLength() external view returns (uint); // 视图函数：获取已创建的交易对总数

    function createPair(address tokenA, address tokenB) external returns (address pair);  // 外部函数：创建两种代币的交易对

    function setFeeTo(address) external; // 外部函数：设置协议费用接收地址
    function setFeeToSetter(address) external; // 外部函数：设置费用设置权限地址
}