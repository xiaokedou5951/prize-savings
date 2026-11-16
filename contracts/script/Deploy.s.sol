// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MockERC4626 } from "../src/mocks/MockERC4626.sol";
import { ITwabController } from "../src/interfaces/ITwabController.sol";
import { TwabController } from "../src/TwabController/TwabController.sol";
import { SimpleTwabController } from "../src/TwabController/SimpleTwabController.sol";
import { ObservationTwabController } from "../src/TwabController/ObservationTwabController.sol";
import { PrizeVault } from "../src/PrizeVault/PrizeVault.sol";
import { PrizePool } from "../src/PrizePool/PrizePool.sol";
import { LiquidationPair } from "../src/LiquidationPair/LiquidationPair.sol";
import { AaveYieldVault, IAavePool, IAaveToken } from "../src/PrizeVault/AaveYieldVault.sol";

/// @notice 部署 + 组装 + 授权（M0 合约 MVP）。
/// @dev 通过环境变量选择实现与收益源（配置矩阵见 docs/architecture/deployment.md）：
///      - TWAB_MODE=simple|observation 选择 TWAB 实现；
///      - USDC_ADDRESS / PRIZE_TOKEN_ADDRESS 指向真实代币，缺省时本地部署 mock；
///      - 收益源三档：YIELD_VAULT_ADDRESS（现成 ERC-4626，主路径 Aave StataToken）
///        > AAVE_POOL+AAVE_ATOKEN（部署 AaveYieldVault 适配器 + 首充 seed）
///        > 仅 chainId 31337 允许 MockERC4626；
///      - 本金路径（USDC / 收益源）在非本地链上不允许 mock，缺配置直接 revert；
///        PRIZE 奖币不在本金路径，允许测试网 mock（脚本打印提示）。
///      随机数由 keeper 注入，不配置真实 Chainlink 订阅。
contract Deploy is Script {
    using SafeERC20 for IERC20;

    uint32 internal constant DAILY = 1 days;
    /// @notice 适配器首充默认金额（1_000 USDC），可用 AAVE_ADAPTER_SEED 覆盖。
    uint256 internal constant DEFAULT_ADAPTER_SEED = 1_000e6;
    /// @notice 死地址：seed 份额接收者，锁死首充份额以锚定适配器汇率。
    address internal constant DEAD_ADDRESS = address(0xdEaD);

    error DeployUsdcRequired(uint256 chainId);
    error DeployYieldSourceRequired(uint256 chainId);
    error DeployAaveConfigIncomplete(address pool, address aToken);
    error DeployYieldVaultAssetMismatch(address yieldVault, address usdc);
    error DeploySeedInsufficient(uint256 balance, uint256 seed);

    function run() external {
        string memory mode = vm.envOr("TWAB_MODE", string("simple"));
        bool useObservation = keccak256(bytes(mode)) == keccak256(bytes("observation"));

        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        bool isLocal = block.chainid == 31337;

        vm.startBroadcast(deployerPk);

        // 1. 底层资产 USDC 与奖币
        (IERC20 usdc, IERC20 prizeToken) = _deployAssets(isLocal);

        // 2. 底层收益金库（三档回退）
        (IERC4626 yieldVault, string memory yvType) = _deployYieldVault(usdc, deployer, isLocal);

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
        console.log("ChainId    :", block.chainid);
        console.log("TWAB_MODE  :", mode);
        console.log("USDC       :", address(usdc));
        console.log("PrizeToken :", address(prizeToken));
        console.log("YieldVault :", address(yieldVault));
        console.log("YvType     :", yvType);
        console.log("Twab       :", address(twab));
        console.log("PrizePool  :", address(prizePool));
        console.log("PrizeVault :", address(vault));
        console.log("LiqPair    :", address(pair));
        console.log("drawOffset :", periodOffset);
    }

    /// @dev USDC：本金路径不允许 mock，非本地链必须显式配置；
    ///      奖币：允许测试网用 MockERC20（不在本金路径，liquidator 可公开 mint 换奖币）。
    function _deployAssets(bool isLocal) internal returns (IERC20 usdc, IERC20 prizeToken) {
        address usdcAddr = vm.envOr("USDC_ADDRESS", address(0));
        if (usdcAddr != address(0)) {
            usdc = IERC20(usdcAddr);
        } else if (isLocal) {
            usdc = IERC20(address(new MockERC20("USD Coin", "USDC", 6)));
        } else {
            revert DeployUsdcRequired(block.chainid);
        }

        address prizeAddr = vm.envOr("PRIZE_TOKEN_ADDRESS", address(0));
        if (prizeAddr != address(0)) {
            prizeToken = IERC20(prizeAddr);
        } else {
            prizeToken = IERC20(address(new MockERC20("Prize Token", "PRIZE", 18)));
            if (!isLocal) {
                console.log(
                    unicode"WARN: PRIZE_TOKEN_ADDRESS 未设置，测试网使用 MockERC20 奖币（liquidator 需自行 mint）"
                );
            }
        }
    }

    /// @dev 收益源三档：YIELD_VAULT_ADDRESS（现成 ERC-4626，主路径 Aave StataToken）
    ///      > AAVE_POOL+AAVE_ATOKEN（自研 AaveYieldVault 适配器 + 首充 seed 防通胀攻击）
    ///      > 仅 chainId 31337 允许 MockERC4626。
    function _deployYieldVault(IERC20 usdc, address deployer, bool isLocal)
        internal
        returns (IERC4626 yieldVault, string memory yvType)
    {
        address yieldVaultAddr = vm.envOr("YIELD_VAULT_ADDRESS", address(0));
        address aavePoolAddr = vm.envOr("AAVE_POOL", address(0));
        address aTokenAddr = vm.envOr("AAVE_ATOKEN", address(0));
        uint256 seed = vm.envOr("AAVE_ADAPTER_SEED", DEFAULT_ADAPTER_SEED);

        if (yieldVaultAddr != address(0)) {
            yieldVault = IERC4626(yieldVaultAddr);
            if (yieldVault.asset() != address(usdc)) {
                revert DeployYieldVaultAssetMismatch(yieldVaultAddr, address(usdc));
            }
            yvType = "stata";
            if (yieldVault.totalSupply() == 0) {
                console.log(
                    unicode"WARN: YIELD_VAULT 份额 totalSupply == 0：全新金库存在首充通胀攻击窗口"
                );
                console.log(
                    unicode"     部署者应先对该金库 seed 存款（份额发死地址）再开放 PrizeVault 存款"
                );
            }
        } else if (aavePoolAddr != address(0) || aTokenAddr != address(0)) {
            if (aavePoolAddr == address(0) || aTokenAddr == address(0)) {
                revert DeployAaveConfigIncomplete(aavePoolAddr, aTokenAddr);
            }
            if (seed > 0 && usdc.balanceOf(deployer) < seed) {
                revert DeploySeedInsufficient(usdc.balanceOf(deployer), seed);
            }
            AaveYieldVault adapter = new AaveYieldVault(
                usdc, IAavePool(aavePoolAddr), IAaveToken(aTokenAddr), "Aave USDC Yield Vault", "aYvUSDC"
            );
            if (seed > 0) {
                // 同一 broadcast 内先于任何外部存款铸出死份额，锚定适配器份额价格
                usdc.forceApprove(address(adapter), seed);
                adapter.deposit(seed, DEAD_ADDRESS);
            } else {
                console.log(unicode"WARN: AAVE_ADAPTER_SEED=0：跳过首充，适配器暴露在通胀攻击窗口下");
            }
            yieldVault = IERC4626(address(adapter));
            yvType = "aave-adapter";
        } else if (isLocal) {
            yieldVault = IERC4626(address(new MockERC4626(usdc)));
            yvType = "mock";
        } else {
            revert DeployYieldSourceRequired(block.chainid);
        }
    }
}
