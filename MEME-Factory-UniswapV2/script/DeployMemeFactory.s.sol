// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../src/MemeFactory.sol";
import "../src/MemeToken.sol";

contract DeployMemeFactory is Script {
    function run() external {
        // ✅ 1. 私钥（uint256 类型）
        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );

        // ✅ 2. 地址（address 类型）
        address deployer = vm.addr(deployerPrivateKey);

        // ✅ 3. Treasury 地址（env 或默认使用 deployer）
        address projectTreasury = vm.envOr("PROJECT_TREASURY", deployer);

        console.log("Deployer:", deployer);
        console.log("Treasury:", projectTreasury);

        vm.startBroadcast(deployerPrivateKey);

        // ✅ 部署 MemeToken 实现合约（逻辑合约）
        MemeToken memeImplementation = new MemeToken();
        console.log(unicode"✅ MemeToken implementation deployed at:", address(memeImplementation));

        // ✅ 部署 MemeFactory（假设最后一个参数是 router，可留空或填本地mock）
        MemeFactory factory = new MemeFactory(address(memeImplementation), projectTreasury, address(0));
        console.log(unicode"✅ MemeFactory deployed at:", address(factory));

        vm.stopBroadcast();

        console.log(unicode"🎉 Deployment complete!");
    }
}
