// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MemeToken.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MemeFactory  {
    using Clones for address;

    address public immutable memeTokenImplementation;
    address public projectTreasury;
    address public uniswapRouter;

    uint256 public constant PLATFORM_FEE_BPS = 500; // 5% (500 basis points)
    uint256 public constant BPS_DENOMINATOR = 10000;

    struct MemeInfo {
        address tokenAddress;
        address creator;
        uint256 totalSupply;
        uint256 mintedSupply;
        uint256 perMint;
        uint256 price; // mint price in wei
        bool liquidityAdded;
    }

    mapping(address => MemeInfo) public memes;
    address[] public allMemes;

    constructor(address _memeTokenImplementation, address _projectTreasury, address _uniswapRouter) {
        memeTokenImplementation = _memeTokenImplementation;
        projectTreasury = _projectTreasury;
        uniswapRouter = _uniswapRouter;
    }

    event MemeCreated(address indexed creator, address indexed token, uint256 totalSupply, uint256 price);
    event MemeMinted(address indexed buyer, address indexed token, uint256 amount, uint256 ethSpent);
    event LiquidityAdded(address indexed token, uint256 ethAmount, uint256 tokenAmount);
    event MemeBought(address indexed buyer, address indexed token, uint256 amountOut, uint256 ethSpent);

    function createMeme(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        uint256 perMint,
        uint256 mintPrice
    ) external returns (address) {
        address clone = memeTokenImplementation.clone();
        MemeToken(clone).initialize(name, symbol, totalSupply, msg.sender, address(this));
        memes[clone] = MemeInfo({
            tokenAddress: clone,
            creator: msg.sender,
            totalSupply: totalSupply,
            mintedSupply: 0,
            perMint: perMint,
            price: mintPrice,
            liquidityAdded: false
        });
        allMemes.push(clone);
        emit MemeCreated(msg.sender, clone, totalSupply, mintPrice);
        return clone;
    }

    function mintMeme(address tokenAddress) external payable {
        MemeInfo storage meme = memes[tokenAddress];
        require(meme.tokenAddress != address(0), "Invalid meme");
        require(msg.value == meme.price, "Incorrect ETH");

        uint256 platformFee = (msg.value * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
        uint256 creatorShare = msg.value - platformFee;

        // Send creator share
        payable(meme.creator).transfer(creatorShare);

        // Use platform fee to add liquidity
        _addLiquidityETH(tokenAddress, platformFee, meme.price, meme);

        // Mint meme tokens to buyer
        MemeToken(tokenAddress).mint(msg.sender, meme.perMint);
        meme.mintedSupply += meme.perMint;

        emit MemeMinted(msg.sender, tokenAddress, meme.perMint, msg.value);
    }

    function buyMeme(address tokenAddress, uint256 minOut) external payable {
        MemeInfo storage meme = memes[tokenAddress];
        require(meme.tokenAddress != address(0), "Invalid meme");

        IUniswapV2Router router = IUniswapV2Router(uniswapRouter);
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = tokenAddress;

        uint256[] memory amountsOut = router.getAmountsOut(msg.value, path);
        uint256 currentPrice = (msg.value * 1e18) / amountsOut[1];

        require(currentPrice < meme.price, "Uniswap price not better");

        uint256[] memory amounts = router.swapExactETHForTokens{value: msg.value}(
            minOut,
            path,
            msg.sender,
            block.timestamp + 300
        );

        emit MemeBought(msg.sender, tokenAddress, amounts[1], msg.value);
    }

    function _addLiquidityETH(address tokenAddress, uint256 ethAmount, uint256 mintPrice, MemeInfo storage meme) internal {
        MemeToken token = MemeToken(tokenAddress);
        IUniswapV2Router router = IUniswapV2Router(uniswapRouter);

        uint256 tokenAmount = meme.perMint;
        if (!meme.liquidityAdded) {
            // 初次流动性以mintPrice为参考比例
            tokenAmount = (ethAmount * 1e18) / mintPrice;
            meme.liquidityAdded = true;
        }

        token.mint(address(this), tokenAmount);
        token.approve(address(router), tokenAmount);

        router.addLiquidityETH{value: ethAmount}(
            tokenAddress,
            tokenAmount,
            0,
            0,
            projectTreasury, // LP token 接收者
            block.timestamp + 300
        );

        emit LiquidityAdded(tokenAddress, ethAmount, tokenAmount);
    }

    function getMemeInfo(address token) external view returns (MemeInfo memory) {
    return memes[token];
}
}
