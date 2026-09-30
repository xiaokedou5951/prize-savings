// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MockERC4626 } from "../src/mocks/MockERC4626.sol";
import { SimpleTwabController } from "../src/TwabController/SimpleTwabController.sol";
import { PrizeVault } from "../src/PrizeVault/PrizeVault.sol";
import { LiquidationPair } from "../src/LiquidationPair/LiquidationPair.sol";

contract LiquidationPairTest is Test {
    MockERC20 internal asset; // USDC
    MockERC20 internal prizeToken;
    MockERC4626 internal yieldVault;
    SimpleTwabController internal twab;
    PrizeVault internal vault;
    LiquidationPair internal pair;

    address internal constant USER = address(0xA11CE);
    address internal constant OWNER = address(0x0A);
    address internal constant LIQUIDATOR = address(0x11AB);
    address internal constant PRIZE_POOL = address(0x0001);

    uint32 internal constant PERIOD = 1 days;
    uint32 internal constant OFFSET = 1_000_000;
    uint256 internal constant START_PRICE = 1e18; // 1:1

    function setUp() public {
        asset = new MockERC20("USD Coin", "USDC", 6);
        prizeToken = new MockERC20("Prize", "PRIZE", 18);
        yieldVault = new MockERC4626(asset);
        twab = new SimpleTwabController();
        vault = new PrizeVault(asset, yieldVault, twab, "Prize Vault", "pvUSDC", OWNER);
        twab.setVault(address(vault));

        pair = new LiquidationPair(prizeToken, asset, vault, PERIOD, OFFSET, START_PRICE, PRIZE_POOL);
        vm.prank(OWNER);
        vault.setLiquidationPair(address(pair));

        // 准备用户资金
        asset.mint(USER, 1_000_000e6);
        vm.prank(USER);
        asset.approve(address(vault), type(uint256).max);
    }

    function _injectYield(uint256 amount) internal {
        asset.mint(OWNER, amount);
        vm.prank(OWNER);
        asset.approve(address(yieldVault), amount);
        vm.prank(OWNER);
        yieldVault.mockHarvest(amount);
    }

    function test_price_decreases_over_time() public {
        uint32 t = OFFSET; // 周期起点
        vm.warp(t);
        assertEq(pair.computeExactAmountIn(1e6), 1e6, "full price at start");

        vm.warp(t + PERIOD / 2);
        // 半程：价格 = startPrice * 0.5
        assertEq(pair.computeExactAmountIn(1e6), 5e5, "half price midway");

        vm.warp(t + PERIOD - 1);
        // 周期末：价格趋近于 0（远低于起点价 1e6）
        assertLt(pair.computeExactAmountIn(1e6), 1e6, "price near zero at period end");
    }

    function test_swap_injects_prize_and_grants_yield() public {
        vm.prank(USER);
        vault.deposit(1000e6, USER);
        _injectYield(100e6);

        uint256 available = vault.liquidatableBalanceOf();
        assertGt(available, 0);

        // 清算者持奖币
        prizeToken.mint(LIQUIDATOR, 1000e18);
        vm.prank(LIQUIDATOR);
        prizeToken.approve(address(pair), type(uint256).max);

        vm.warp(OFFSET); // 满价，1 USDC yield = 1 奖币
        uint256 beforePool = prizeToken.balanceOf(PRIZE_POOL);
        uint256 beforeLiquid = asset.balanceOf(LIQUIDATOR);

        vm.prank(LIQUIDATOR);
        uint256 amountIn = pair.swapExactAmountOut(available, LIQUIDATOR);

        assertGt(amountIn, 0);
        assertEq(prizeToken.balanceOf(PRIZE_POOL), beforePool + amountIn, "prize injected to pool");
        assertEq(asset.balanceOf(LIQUIDATOR), beforeLiquid + available, "yield delivered to liquidator");
    }

    function test_amount_out_capped_by_liquidatable() public {
        vm.prank(USER);
        vault.deposit(1000e6, USER);
        _injectYield(10e6);

        uint256 available = vault.liquidatableBalanceOf();
        prizeToken.mint(LIQUIDATOR, 1000e18);
        vm.prank(LIQUIDATOR);
        prizeToken.approve(address(pair), type(uint256).max);

        vm.warp(OFFSET);
        vm.prank(LIQUIDATOR);
        uint256 amountIn = pair.swapExactAmountOut(1_000_000e6, LIQUIDATOR); // 请求远超可清算量

        // 实际清算应以可用量封顶，且本金不被动
        assertLe(amountIn, 1000e18);
        assertEq(vault.liquidatableBalanceOf(), 0, "yield fully liquidated");
        assertGe(vault.totalAssets(), vault.totalSupply(), "no-loss after liquidation");
    }
}
