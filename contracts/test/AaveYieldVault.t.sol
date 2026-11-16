// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MockAavePool } from "../src/mocks/MockAavePool.sol";
import { MockAToken } from "../src/mocks/MockAToken.sol";
import { AaveYieldVault, IAavePool, IAaveToken } from "../src/PrizeVault/AaveYieldVault.sol";

/// @notice AaveYieldVault 适配器默认套件单测（无外部 RPC 依赖）。
/// @dev 通胀攻击用例复现 M0 集成审查结论：无 seed 时攻击者的「1 wei 存款 + aToken
///      捐赠」会使受害者存款换到 0 份额，必须被 shares==0 守卫拒绝；有 seed 时
///      同样的攻击对受害者造成的损失被死地址份额吸收到粉尘级。
contract AaveYieldVaultTest is Test {
    MockERC20 internal asset;
    MockAavePool internal pool;
    MockAToken internal aToken;
    AaveYieldVault internal vault;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant ATTACKER = address(0xBAD);
    /// @notice 死地址：seed 份额接收者，模拟 Deploy.s.sol 的首充防护。
    address internal constant DEAD = address(0xdEaD);

    /// @notice 与 Deploy.s.sol 的 DEFAULT_ADAPTER_SEED 保持一致。
    uint256 internal constant SEED = 1_000e6;
    uint256 internal constant VICTIM_DEPOSIT = 1e6;

    function setUp() public {
        asset = new MockERC20("USD Coin", "USDC", 6);
        pool = new MockAavePool(asset);
        aToken = pool.aToken();
        vault = new AaveYieldVault(
            asset, IAavePool(address(pool)), IAaveToken(address(aToken)), "Aave USDC Yield Vault", "aYvUSDC"
        );

        asset.mint(ALICE, 1_000_000e6);
        asset.mint(BOB, 1_000_000e6);
        asset.mint(ATTACKER, 1_000_000e6);

        vm.prank(ALICE);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(BOB);
        asset.approve(address(vault), type(uint256).max);
        vm.startPrank(ATTACKER);
        asset.approve(address(vault), type(uint256).max);
        asset.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    /// @notice 存赎 roundtrip：空金库 1:1 铸份额，全额赎回拿回本金。
    function test_deposit_redeem_roundtrip() public {
        vm.prank(ALICE);
        uint256 shares = vault.deposit(1000e6, ALICE);

        assertEq(shares, 1000e6, "1:1 shares on empty vault");
        assertEq(vault.totalAssets(), 1000e6, "totalAssets == aToken balance");
        assertEq(aToken.balanceOf(address(vault)), 1000e6, "aToken minted to vault");

        vm.prank(ALICE);
        uint256 redeemed = vault.redeem(shares, ALICE, ALICE);
        assertEq(redeemed, 1000e6, "full principal returned");
        assertEq(asset.balanceOf(ALICE), 1_000_000e6, "asset returned to user");
    }

    /// @notice Aave 计息后 totalAssets 增长，利息按份额比例分摊（浮动汇率语义，
    ///         区别于 PrizeVault 的 1:1 本金基准）。
    function test_interest_accrues_pro_rata() public {
        vm.prank(ALICE);
        vault.deposit(1000e6, ALICE);
        vm.prank(BOB);
        vault.deposit(1000e6, BOB);

        // 模拟 Aave 计息：适配器名下 aToken 余额增长
        aToken.accrue(address(vault), 100e6);

        assertEq(vault.totalAssets(), 2100e6, "totalAssets includes interest");
        // OZ v5.0.0 虚拟份额偏移（totalAssets+1 / supply+1）带来 <=1 wei 舍入，用容差断言
        assertApproxEqAbs(vault.convertToAssets(vault.balanceOf(ALICE)), 1050e6, 2, "alice share of interest");
        assertApproxEqAbs(vault.convertToAssets(vault.balanceOf(BOB)), 1050e6, 2, "bob share of interest");

        // 先取份额再 prank：prank 只作用于「下一个调用」，写在参数里会被 balanceOf 消耗掉
        uint256 aliceShares = vault.balanceOf(ALICE);
        vm.prank(ALICE);
        uint256 redeemed = vault.redeem(aliceShares, ALICE, ALICE);
        assertApproxEqAbs(redeemed, 1050e6, 2, "alice redeems principal + interest");
    }

    /// @notice maxRedeem 只反映份额余额，不查询 Aave 底层流动性（语义锁定；
    ///         Aave 枯竭场景由 redeem revert 表达，见合约 NatSpec）。
    function test_maxRedeem_returns_share_balance() public {
        vm.prank(ALICE);
        vault.deposit(1000e6, ALICE);
        aToken.accrue(address(vault), 100e6);

        assertEq(vault.maxRedeem(ALICE), vault.balanceOf(ALICE), "maxRedeem == share balance");
        assertEq(vault.maxRedeem(ALICE), 1000e6);
    }

    /// @notice 赎回授权：caller != owner 时按份额扣减 allowance（语义与 PrizeVault 一致）。
    function test_redeem_via_allowance() public {
        vm.prank(BOB);
        vault.deposit(1000e6, BOB);

        vm.prank(BOB);
        vault.approve(ALICE, 400e6);
        vm.prank(ALICE);
        uint256 redeemed = vault.redeem(400e6, ALICE, BOB);
        assertEq(redeemed, 400e6, "allowed redeem pays out");
        assertEq(asset.balanceOf(ALICE), 1_000_000e6 + 400e6, "receiver got assets");

        vm.prank(ALICE);
        vm.expectRevert(); // allowance 已耗尽
        vault.redeem(1, ALICE, BOB);
    }

    /// @notice 无 seed：攻击者 1 wei 存款 + 捐赠 20 倍存款额的 aToken 抬升汇率，
    ///         受害者存款换 0 份额 -> 被 shares==0 守卫拒绝，而不是沉默变捐赠。
    function test_inflation_attack_reverted_without_seed() public {
        // 攻击者先存 1 wei，成为唯一份额持有者（1 share）
        vm.prank(ATTACKER);
        vault.deposit(1, ATTACKER);
        assertEq(vault.totalSupply(), 1, "attacker holds the only share");

        // 攻击者直接向 pool 供应获取 aToken，再捐赠给金库抬升 totalAssets
        vm.startPrank(ATTACKER);
        pool.supply(address(asset), 20 * VICTIM_DEPOSIT, ATTACKER, 0);
        aToken.transfer(address(vault), 20 * VICTIM_DEPOSIT);
        vm.stopPrank();

        // 受害者 1 USDC 存款经 Floor 舍入只值 0 份额（带参数自定义错误需全量匹配）
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(AaveYieldVault.AaveYieldVaultZeroShares.selector, ALICE, VICTIM_DEPOSIT));
        vault.deposit(VICTIM_DEPOSIT, ALICE);
    }

    /// @notice 有 seed：死地址份额锚定汇率，同样的攻击下受害者损失被吸收到粉尘级。
    function test_seed_absorbs_inflation_attack() public {
        // 部署者首充 seed（此处由 ALICE 扮演），份额发往死地址
        vm.prank(ALICE);
        vault.deposit(SEED, DEAD);
        assertEq(vault.totalSupply(), SEED, "dead shares anchor the rate");

        vm.startPrank(ATTACKER);
        vault.deposit(1, ATTACKER);
        pool.supply(address(asset), 20 * VICTIM_DEPOSIT, ATTACKER, 0);
        aToken.transfer(address(vault), 20 * VICTIM_DEPOSIT);
        vm.stopPrank();

        uint256 expectedShares = vault.convertToShares(VICTIM_DEPOSIT);

        // 受害者存款仍能换到 ≈ 全额份额（汇率未被显著抬升）
        vm.prank(ALICE);
        uint256 shares = vault.deposit(VICTIM_DEPOSIT, ALICE);
        assertGt(shares, 0, "victim gets shares");
        assertGe(shares, expectedShares - expectedShares / 1000, "share price not materially inflated");

        // 全额赎回：本金损失 <= 0.1%（seed 吸收了捐赠造成的汇率冲击）
        vm.prank(ALICE);
        uint256 redeemed = vault.redeem(shares, ALICE, ALICE);
        assertGe(redeemed, VICTIM_DEPOSIT - VICTIM_DEPOSIT / 1000, "victim loss <= dust");
    }

    /// @notice aToken 底层与金库资产不一致时构造 revert（防接线错误）。
    function test_constructor_reverts_on_a_token_mismatch() public {
        MockERC20 otherAsset = new MockERC20("Token B", "TKB", 18);
        MockAavePool otherPool = new MockAavePool(otherAsset);
        // 先取出 getter 结果：expectRevert 只作用于「下一个调用」
        address otherAToken = address(otherPool.aToken());

        vm.expectRevert(
            abi.encodeWithSelector(AaveYieldVault.AaveYieldVaultAssetMismatch.selector, otherAToken, address(asset))
        );
        new AaveYieldVault(asset, IAavePool(address(otherPool)), IAaveToken(otherAToken), "Bad Vault", "badV");
    }
}
