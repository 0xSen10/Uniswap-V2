// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/MemeFactory.sol";
import "../src/MemeToken.sol";

contract MemeFactoryTest is Test {
    MemeFactory public factory;
    address public user = address(0x123);
    address public projectTreasury = address(0x999);
    address public uniswapRouter = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    function setUp() public {
        vm.deal(user, 100 ether);
        // 直接部署工厂合约，实现合约会在工厂构造函数内部部署
        factory = new MemeFactory(projectTreasury, uniswapRouter, address(0));
        
        console.log(unicode"✅ MemeFactory deployed:", address(factory));
        console.log(unicode"✅ MemeToken implementation:", factory.memeTokenImplementation());
    }

    function testCreateMemeAndMint() public {
        vm.deal(user, 100 ether);
        vm.startPrank(user);
        console.log(unicode"👤 User:", user);

        // 部署 Meme Token
        address tokenAddress = factory.createMeme(
            "Test Meme",    // name
            "TME",           // symbol
            1_000_000 ether, // totalSupply
            10 ether,        // perMint
            0.01 ether       // price
        );

        // 获取 Meme 信息
        MemeFactory.MemeInfo memory info = factory.getMemeInfo(tokenAddress);
        console.log(unicode"📦 New MemeToken:", info.tokenAddress);
        console.log(unicode"💰 Price per mint:", info.price);
        console.log(unicode"🪙 Tokens per mint:", info.perMint);

        // 记录用户和合约的初始余额
        uint256 userBalanceBefore = user.balance;
        uint256 treasuryBalanceBefore = projectTreasury.balance;
        uint256 creatorBalanceBefore = user.balance; // 创建者就是当前用户

        // Mint 代币 - 传递正确的 ETH 金额
        factory.mintMeme{value: 0.01 ether}(tokenAddress);
        console.log(unicode"✅ Minted one Meme");

        // 验证结果
        MemeToken token = MemeToken(tokenAddress);
        uint256 balance = token.balanceOf(user);
        console.log(unicode"💰 User token balance:", balance);
        
        // 检查代币余额
        assertEq(balance, 10 ether, "User should have 10 tokens");
        
        // 检查已铸造数量更新
        MemeFactory.MemeInfo memory infoAfter = factory.getMemeInfo(tokenAddress);
        assertEq(infoAfter.mintedSupply, 10 ether, "Minted supply should be 10");
        
        // 检查用户 ETH 余额减少
        assertEq(user.balance, userBalanceBefore - 0.01 ether, "User should pay 0.01 ETH");

        vm.stopPrank();
    }
}