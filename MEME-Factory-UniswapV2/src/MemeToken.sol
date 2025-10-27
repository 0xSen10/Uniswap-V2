// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MemeToken is ERC20 {
    address public factory;
    bool public initialized;

    string private _customName;
    string private _customSymbol;

    // ✅ 无参数构造函数，避免 clone 时构造器执行问题
    constructor() ERC20("", "") {}

    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        address creator_,
        address factory_
    ) external {
        require(!initialized, "Already initialized");

        _customName = name_;
        _customSymbol = symbol_;
        factory = factory_;
        _mint(creator_, totalSupply_);
        initialized = true;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == factory, "Only factory");
        _mint(to, amount);
    }

    // ✅ 覆盖 ERC20 的 name() 和 symbol()
    function name() public view override returns (string memory) {
        return _customName;
    }

    function symbol() public view override returns (string memory) {
        return _customSymbol;
    }
}
