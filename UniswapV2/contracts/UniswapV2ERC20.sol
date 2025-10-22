pragma solidity =0.5.16;

import './interfaces/IUniswapV2ERC20.sol';
import './libraries/SafeMath.sol';

contract UniswapV2ERC20 is IUniswapV2ERC20 {
    using SafeMath for uint;  //将SafeMath库可以用uint来表示

    string public constant name = 'Uniswap V2'; //Token name
    string public constant symbol = 'UNI-V2'; //Token symbol
    uint8 public constant decimals = 18; //Token 小数点
    uint  public totalSupply; //Token总数
    mapping(address => uint) public balanceOf; // 地址余额映射
    mapping(address => mapping(address => uint)) public allowance; // 授权额度映射

// EIP-712 相关变量
    bytes32 public DOMAIN_SEPARATOR;  // 域分隔符
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public nonces; //地址nonce防止重放攻击

    event Approval(address indexed owner, address indexed spender, uint value); // 授权事件
    event Transfer(address indexed from, address indexed to, uint value); //转账事件

    constructor() public {
        uint chainId;
        assembly {
            chainId := chainid // 内联汇编获取当前链ID
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }

    function _mint(address to, uint value) internal { // 内部函数：铸造代币
        totalSupply = totalSupply.add(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint value) internal { // 内部函数：销毁代币
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
        emit Transfer(from, address(0), value);
    }

    function _approve(address owner, address spender, uint value) private {  // 内部函数：授权操作
        allowance[owner][spender] = value; // 设置授权额度
        emit Approval(owner, spender, value);
    }

    // 内部函数：转账操作
    function _transfer(address from, address to, uint value) private {
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }

    function approve(address spender, uint value) external returns (bool) { // 外部函数：授权代币给某个地址
        _approve(msg.sender, spender, value); // 调用内部授权函数
        return true;
    }

    //转账函数
    function transfer(address to, uint value) external returns (bool) {
        _transfer(msg.sender, to, value); // 调用内部转账函数
        return true;
    }

    // 外部函数：从授权地址转账
    function transferFrom(address from, address to, uint value) external returns (bool) {
        // 如果授权额度不是最大值，则减少相应额度
        if (allowance[from][msg.sender] != uint(-1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }
        _transfer(from, to, value);
        return true;
    }

    // 外部函数：使用签名进行授权（EIP-2612许可）
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'UniswapV2: EXPIRED'); //判断，如果时间期限超过当前时间戳则报错
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01', // EIP-712 前缀
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s); // 从签名中恢复地址
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'UniswapV2: INVALID_SIGNATURE');
        _approve(owner, spender, value);
    }
}