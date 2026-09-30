// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MockERC4626 } from "../src/mocks/MockERC4626.sol";
import { ITwabController } from "../src/interfaces/ITwabController.sol";
import { TwabController } from "../src/TwabController/TwabController.sol";
import { SimpleTwabController } from "../src/TwabController/SimpleTwabController.sol";
import { ObservationTwabController } from "../src/TwabController/ObservationTwabController.sol";
import { PrizeVault } from "../src/PrizeVault/PrizeVault.sol";
import { PrizePool } from "../src/PrizePool/PrizePool.sol";
import { LiquidationPair } from "../src/LiquidationPair/LiquidationPair.sol";

/// @notice 端到端闭环测试：两种 TWAB 实现各跑一遍。
///        存款 → 收益 → 清算入池 → 开奖 → 领奖 → 赎回本金。
abstract contract IntegrationTest is Test {
    MockERC20 internal asset;
    MockERC20 internal prizeToken;
    MockERC4626 internal yieldVault;
    ITwabController internal twab;
    PrizeVault internal vault;
    PrizePool internal pool;
    LiquidationPair internal pair;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant OWNER = address(0x0A);
    address internal constant KEEPER = address(0xEAD);
    address internal constant LIQUIDATOR = address(0x11AB);

    uint32 internal constant PERIOD = 1 days;
    uint32 internal constant OFFSET = 1_000_000;

    function _deployTwab() internal virtual returns (ITwabController);

    function setUp() public {
        asset = new MockERC20("USD Coin", "USDC", 6);
        prizeToken = new MockERC20("Prize", "PRIZE", 18);
        yieldVault = new MockERC4626(asset);
        twab = _deployTwab();

        pool = new PrizePool(prizeToken, twab, PERIOD, OFFSET, KEEPER);
        vault = new PrizeVault(asset, yieldVault, twab, "Prize Vault", "pvUSDC", OWNER);
        TwabController(address(twab)).setVault(address(vault));

        pair = new LiquidationPair(prizeToken, asset, vault, PERIOD, OFFSET, 1e18, address(pool));
        vm.prank(OWNER);
        vault.setLiquidationPair(address(pair));

        asset.mint(ALICE, 10_000e6);
        asset.mint(BOB, 10_000e6);
        vm.prank(ALICE);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(BOB);
        asset.approve(address(vault), type(uint256).max);

        prizeToken.mint(LIQUIDATOR, 1_000_000e18);
        vm.prank(LIQUIDATOR);
        prizeToken.approve(address(pair), type(uint256).max);
    }

    function test_full_closed_loop() public {
        vm.warp(OFFSET);
        uint256 aliceDeposit = 1000e6;
        uint256 bobDeposit = 1000e6;

        vm.prank(ALICE);
        vault.deposit(aliceDeposit, ALICE);
        vm.prank(BOB);
        vault.deposit(bobDeposit, BOB);

        // 收益：捐赠给底层 yieldVault，抬升份额单价
        uint256 yield = 200e6;
        asset.mint(OWNER, yield);
        vm.prank(OWNER);
        asset.approve(address(yieldVault), yield);
        vm.prank(OWNER);
        yieldVault.mockHarvest(yield);

        uint256 liquidatable = vault.liquidatableBalanceOf();
        assertGt(liquidatable, 0, "yield is liquidatable");

        // 清算：奖币入池，yield 给清算者
        vm.warp(OFFSET + PERIOD / 2);
        vm.prank(LIQUIDATOR);
        uint256 amountIn = pair.swapExactAmountOut(liquidatable, LIQUIDATOR);
        assertGt(amountIn, 0, "prize injected");

        // 开奖
        vm.warp(OFFSET + PERIOD);
        vm.prank(KEEPER);
        uint32 drawId = pool.awardDraw(20240928);
        assertEq(drawId, 1);

        // 至少一人具备大奖领取资格（Alice 或 Bob 之一）
        uint256 alicePrize = pool.getClaimableAmount(ALICE, 0, 1);
        uint256 bobPrize = pool.getClaimableAmount(BOB, 0, 1);
        assertGt(alicePrize + bobPrize, 0, "someone eligible for grand prize");

        // 大奖只有 1 份：领取其一；另一人的同档奖金被预算封顶（若超额则 revert 或得 0）
        if (alicePrize > 0) {
            uint256 claimed = pool.claimPrize(ALICE, 0, 1);
            assertGt(claimed, 0, "grand prize paid");
        } else {
            uint256 claimed = pool.claimPrize(BOB, 0, 1);
            assertGt(claimed, 0, "grand prize paid");
        }

        // 本金随时可赎回
        uint256 aliceShares = vault.balanceOf(ALICE);
        uint256 bobShares = vault.balanceOf(BOB);
        vm.prank(ALICE);
        uint256 aliceRedeemed = vault.redeem(aliceShares, ALICE, ALICE);
        vm.prank(BOB);
        uint256 bobRedeemed = vault.redeem(bobShares, BOB, BOB);

        // 零损失：双方赎回总额 >= 初始本金之和
        assertGe(aliceRedeemed + bobRedeemed, aliceDeposit + bobDeposit, "no-loss guaranteed");
    }
}

contract IntegrationSimpleTest is IntegrationTest {
    function _deployTwab() internal override returns (ITwabController) {
        return new SimpleTwabController();
    }
}

contract IntegrationObservationTest is IntegrationTest {
    function _deployTwab() internal override returns (ITwabController) {
        return new ObservationTwabController();
    }
}
