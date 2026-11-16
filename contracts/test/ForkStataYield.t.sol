// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { SimpleTwabController } from "../src/TwabController/SimpleTwabController.sol";
import { PrizeVault } from "../src/PrizeVault/PrizeVault.sol";

/// @notice Base 主网 fork 测试：Aave 官方 USDC StataToken 直接作为 PrizeVault 底层
///         收益源的全链路验证（M0 真实收益源主路径）。
/// @dev 依赖 BASE_RPC_URL；默认套件未配置该变量时整个合约 skip，
///      保证 `pnpm contracts:test` 无外部 RPC 依赖即可全绿。手动运行：
///      `BASE_RPC_URL=<url> forge test --root contracts --match-contract ForkStataYield`。
contract ForkStataYieldTest is Test {
    /// @notice 地址来源：bgd-labs/aave-address-book AaveV3Base.sol（2026-10 抓取）
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant USDC_STATA = 0xC768c589647798a6EE01A91FdE98EF2ed046DBD6;

    uint256 internal constant DEPOSIT = 1000e6;
    /// @notice poke 用小额存款：路径 PrizeVault._deposit -> stata.deposit -> pool.supply，
    ///         一笔交易同时推进 USDC 储备 liquidityIndex 并刷新 stata 汇率。
    uint256 internal constant POKE_DEPOSIT = 1e6;

    IERC20 internal usdc;
    IERC4626 internal stata;
    SimpleTwabController internal twab;
    PrizeVault internal vault;

    address internal alice;
    address internal bob;

    function setUp() public {
        // skip 守卫：默认套件不依赖外部 RPC（未设置 BASE_RPC_URL 时跳过全部用例）
        if (bytes(vm.envOr("BASE_RPC_URL", string(""))).length == 0) {
            vm.skip(true);
        }
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        usdc = IERC20(USDC);
        stata = IERC4626(USDC_STATA);
        twab = new SimpleTwabController();
        vault = new PrizeVault(usdc, stata, twab, "Prize Vault USDC", "pvUSDC", address(this));
        twab.setVault(address(vault));

        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // 资金注入：deal 直接改写 USDC 余额（Base 原生 USDC 为代理代币，balanceOf 为
        // 标准 mapping 布局，foundry deal 可探测；若未来 deal 失效，回退方案是用
        // Base 上持币 whale 的 prank + transfer，见计划 v2 风险表）。
        deal(USDC, alice, DEPOSIT * 10);
        deal(USDC, bob, POKE_DEPOSIT * 10);
        assertEq(usdc.balanceOf(alice), DEPOSIT * 10, "deal ineffective: switch to whale fallback");

        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);
    }

    /// @notice 全链路：存款 -> 30 天惰性计息（warp + poke）-> 收益可清算 -> 零损失赎回。
    function test_stata_yield_lifecycle() public {
        // 共享 stata 实例必须已有存量供应（部署期反通胀攻击的前置条件）
        assertGt(stata.totalSupply(), 0, "stata should be a shared instance");

        // 1) 存款：PrizeVault 经 stata 把 USDC 供应给 Aave；份额 1:1
        vm.prank(alice);
        uint256 shares = vault.deposit(DEPOSIT, alice);
        assertEq(shares, DEPOSIT, "1:1 share mint");
        assertGe(vault.totalAssets(), vault.totalSupply(), "zero-loss at deposit");

        // 2) 前进 30 天。Aave 惰性计息：liquidityIndex 只在储备发生状态变更交易时
        //    推进，warp 本身不改变 aToken 余额/stata 汇率（OZ 虚拟偏移可能留下 ≤1 wei）。
        uint256 liquidatableBeforeWarp = vault.liquidatableBalanceOf();
        vm.warp(block.timestamp + 30 days);
        assertEq(vault.liquidatableBalanceOf(), liquidatableBeforeWarp, "warp alone accrues nothing (lazy interest)");

        // 3) poke：bob 的小额存款触发 USDC 储备状态更新 + stata 汇率刷新
        vm.prank(bob);
        vault.deposit(POKE_DEPOSIT, bob);

        // 4) poke 后收益可见且可清算（30 天利息 >> 舍入粉尘）
        assertGt(vault.totalAssets(), vault.totalSupply(), "assets grew after poke");
        assertGt(vault.liquidatableBalanceOf(), liquidatableBeforeWarp, "yield visible after poke");
        assertGt(vault.liquidatableBalanceOf(), 0, "yield liquidatable after poke");

        // 5) 零损失赎回：本金完整返回（收益留在金库待清算）
        uint256 before = usdc.balanceOf(alice);
        vm.prank(alice);
        uint256 redeemed = vault.redeem(shares, alice, alice);
        assertGe(redeemed, DEPOSIT, "zero-loss: principal intact");
        assertEq(usdc.balanceOf(alice) - before, redeemed, "USDC received by alice");
    }
}
