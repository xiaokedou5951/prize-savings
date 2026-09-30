// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MockERC4626 } from "../src/mocks/MockERC4626.sol";
import { ITwabController } from "../src/interfaces/ITwabController.sol";
import { TwabController } from "../src/TwabController/TwabController.sol";
import { SimpleTwabController } from "../src/TwabController/SimpleTwabController.sol";
import { ObservationTwabController } from "../src/TwabController/ObservationTwabController.sol";
import { PrizeVault } from "../src/PrizeVault/PrizeVault.sol";
import { PrizePool } from "../src/PrizePool/PrizePool.sol";
import { LiquidationPair } from "../src/LiquidationPair/LiquidationPair.sol";

/// @notice 部署 + 组装 + 授权（M0 合约 MVP）。
/// @dev 通过环境变量 TWAB_MODE（simple|observation）选择 TWAB 实现。
///      随机数由 keeper 注入，不配置真实 Chainlink 订阅。
contract Deploy is Script {
    uint32 internal constant DAILY = 1 days;

    function run() external {
        string memory mode = vm.envOr("TWAB_MODE", string("simple"));
        bool useObservation = keccak256(bytes(mode)) == keccak256(bytes("observation"));

        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        vm.startBroadcast(deployerPk);

        // 1. 资产：USDC（底层）与奖币
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 prizeToken = new MockERC20("Prize Token", "PRIZE", 18);

        // 2. 底层收益金库
        MockERC4626 yieldVault = new MockERC4626(usdc);

        // 3. TWAB 控制器（simple / observation 可配置切换）
        ITwabController twab = useObservation
            ? ITwabController(address(new ObservationTwabController()))
            : ITwabController(address(new SimpleTwabController()));

        // 4. 奖池
        uint32 periodOffset = uint32(block.timestamp);
        PrizePool prizePool = new PrizePool(prizeToken, twab, DAILY, periodOffset, deployer);

        // 5. PrizeVault
        PrizeVault vault = new PrizeVault(usdc, yieldVault, twab, "Prize Vault USDC", "pvUSDC", deployer);

        // 6. LiquidationPair（奖币进奖池，yield 给清算者）
        LiquidationPair pair =
            new LiquidationPair(prizeToken, usdc, vault, DAILY, periodOffset, 1e18, address(prizePool));

        // 7. 组装授权
        TwabController(address(twab)).setVault(address(vault));
        vault.setLiquidationPair(address(pair));

        vm.stopBroadcast();

        console.log("--- Prize Savings MVP deployed ---");
        console.log("TWAB_MODE  :", mode);
        console.log("USDC       :", address(usdc));
        console.log("PrizeToken :", address(prizeToken));
        console.log("YieldVault :", address(yieldVault));
        console.log("Twab       :", address(twab));
        console.log("PrizePool  :", address(prizePool));
        console.log("PrizeVault :", address(vault));
        console.log("LiqPair    :", address(pair));
        console.log("drawOffset :", periodOffset);
    }
}
