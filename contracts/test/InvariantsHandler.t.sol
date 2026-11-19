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

/// @notice 状态机不变量 fuzz（handler-based）：随机存取款 / 转账 / 收益 / 开奖 / 领奖序列下，
///         断言三条全局不变量恒成立。两种 TWAB 实现各跑一遍。
/// @dev 重点覆盖不变量 3（TWAB 只读追溯）：每次开奖后快照所有 (actor, tier, drawId) 的
///      getClaimableAmount，后续任意余额变更不得改变历史值。
abstract contract TwabInvariantBase is Test {
    MockERC20 internal asset;
    MockERC20 internal prizeToken;
    MockERC4626 internal yieldVault;
    ITwabController internal twab;
    PrizeVault internal vault;
    PrizePool internal pool;
    InvariantHandler internal handler;

    uint32 internal constant PERIOD = 1 days;
    uint32 internal constant OFFSET = 1_000_000;
    uint8 internal constant TIER_COUNT = 3;

    address internal constant OWNER = address(0x0A);

    function _deployTwab() internal virtual returns (ITwabController);

    function setUp() public virtual {
        asset = new MockERC20("USD Coin", "USDC", 6);
        prizeToken = new MockERC20("Prize", "PRIZE", 18);
        yieldVault = new MockERC4626(asset);
        twab = _deployTwab();

        vault = new PrizeVault(asset, yieldVault, twab, "Prize Vault", "pvUSDC", OWNER);
        TwabController(address(twab)).setVault(address(vault));

        handler = new InvariantHandler(asset, prizeToken, yieldVault, twab, vault);
        // drawManager = handler：handler 直接调 awardDraw（聚焦 TWAB 不变量，VRF 正确性在 RngRelay.t 测）
        pool = new PrizePool(prizeToken, twab, PERIOD, OFFSET, address(handler));
        handler.setPool(pool);

        // 预置奖池底金，保证首期开奖有奖金；handler 的 fundPool 动作会持续补充
        prizeToken.mint(address(pool), 1_000_000e18);
        // 预置 actor 本金
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            address a = handler.getActor(i);
            asset.mint(a, 1_000_000e6);
            vm.prank(a);
            asset.approve(address(vault), type(uint256).max);
        }

        // 种子存款：bootstrap 底层 yieldVault 的份额单价（使其 totalSupply > 0），
        // 避免「先收益后存款」触发 ERC4626 零供应通胀；与生产部署一致（yield vault 已有流动性）。
        asset.mint(OWNER, 10_000_000e6);
        vm.startPrank(OWNER);
        asset.approve(address(vault), 10_000_000e6);
        vault.deposit(10_000_000e6, OWNER);
        vm.stopPrank();

        // 只把 handler 的状态变更动作纳入 fuzz（排除 view getter 与 snapshot 映射的自动 getter）
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = InvariantHandler.deposit.selector;
        selectors[1] = InvariantHandler.redeem.selector;
        selectors[2] = InvariantHandler.transferShares.selector;
        selectors[3] = InvariantHandler.simulateYield.selector;
        selectors[4] = InvariantHandler.fundPool.selector;
        selectors[5] = InvariantHandler.warpAndAwardDraw.selector;
        selectors[6] = InvariantHandler.claimPrize.selector;
        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
        targetContract(address(handler));
    }

    // ---- 不变量 1：零损失 ----
    function invariant_noLoss() public view {
        assertGe(vault.totalAssets(), vault.totalSupply(), "invariant: totalAssets >= totalSupply");
    }

    // ---- 不变量 2：份额守恒 ----
    function invariant_shareConservation() public view {
        assertEq(twab.totalSupply(), vault.totalSupply(), "invariant: twab.totalSupply == vault.totalSupply");
    }

    // ---- 不变量 3：TWAB 只读追溯 ----
    // awardDraw 后任何存取款/转账/领奖都不得改变历史 draw 的 getClaimableAmount。
    function invariant_twabReadonlyHistory() public view {
        uint256 draws = handler.awardedDrawCount();
        for (uint256 d = 0; d < draws; d++) {
            uint32 drawId = handler.getAwardedDraw(d);
            for (uint256 a = 0; a < handler.actorCount(); a++) {
                address actor = handler.getActor(a);
                for (uint8 t = 0; t < TIER_COUNT; t++) {
                    assertEq(
                        pool.getClaimableAmount(actor, t, drawId),
                        handler.snapshot(drawId, actor, t),
                        "invariant: historical claimable mutated by later balance changes"
                    );
                }
            }
        }
    }
}

/// @notice 随机动作发生器：每个 public 函数是一个状态转移动作，被 forge invariant 随机调用。
contract InvariantHandler is Test {
    MockERC20 public immutable asset;
    MockERC20 public immutable prizeToken;
    MockERC4626 public immutable yieldVault;
    ITwabController public immutable twab;
    PrizeVault public immutable vault;
    PrizePool public pool;

    address[] public actors;
    uint32[] public awardedDraws;

    uint8 public constant TIER_COUNT = 3;

    // snapshot[drawId][actor][tier] = 开奖时记录的 getClaimableAmount（之后不得改变）
    mapping(uint32 => mapping(address => mapping(uint8 => uint256))) public snapshot;

    constructor(
        MockERC20 asset_,
        MockERC20 prizeToken_,
        MockERC4626 yieldVault_,
        ITwabController twab_,
        PrizeVault vault_
    ) {
        asset = asset_;
        prizeToken = prizeToken_;
        yieldVault = yieldVault_;
        twab = twab_;
        vault = vault_;
        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCA401));
    }

    function setPool(PrizePool pool_) external {
        require(address(pool) == address(0), "pool already set");
        pool = pool_;
    }

    function actorCount() public view returns (uint256) {
        return actors.length;
    }

    function getActor(uint256 i) public view returns (address) {
        return actors[i];
    }

    function awardedDrawCount() public view returns (uint256) {
        return awardedDraws.length;
    }

    function getAwardedDraw(uint256 i) public view returns (uint32) {
        return awardedDraws[i];
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    // ---- 动作 1：存款 ----
    function deposit(uint256 actorSeed, uint256 amount) public {
        amount = bound(amount, 1, 10_000e6);
        address actor = _actor(actorSeed);
        asset.mint(actor, amount);
        vm.startPrank(actor);
        asset.approve(address(vault), amount);
        vault.deposit(amount, actor);
        vm.stopPrank();
    }

    // ---- 动作 2：赎回 ----
    function redeem(uint256 actorSeed, uint256 shares) public {
        address actor = _actor(actorSeed);
        uint256 bal = vault.balanceOf(actor);
        if (bal == 0) return;
        shares = bound(shares, 1, bal);
        vm.prank(actor);
        vault.redeem(shares, actor, actor);
    }

    // ---- 动作 3：份额转账（触发 twab.transfer） ----
    function transferShares(uint256 fromSeed, uint256 toSeed, uint256 shares) public {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        if (from == to) return;
        uint256 bal = vault.balanceOf(from);
        if (bal == 0) return;
        shares = bound(shares, 1, bal);
        vm.prank(from);
        vault.transfer(to, shares);
    }

    // ---- 动作 4：注入收益（抬升 vault.totalAssets，验证收益下零损失仍成立） ----
    function simulateYield(uint256 amount) public {
        // 收益只在已有本金时累积（生产中 yield 源于已存入本金）；种子存款保证此处恒成立。
        if (vault.totalSupply() == 0) return;
        amount = bound(amount, 1, 1_000e6);
        asset.mint(address(this), amount);
        asset.approve(address(yieldVault), amount);
        yieldVault.mockHarvest(amount);
    }

    // ---- 动作 5：补充奖池奖金 ----
    function fundPool(uint256 amount) public {
        amount = bound(amount, 1, 100_000e18);
        prizeToken.mint(address(pool), amount);
    }

    // ---- 动作 6：推进时间并开奖；开奖后立即快照历史可领金额 ----
    function warpAndAwardDraw(uint256 random) public {
        uint32 next = pool.nextDrawStart();
        if (block.timestamp < next) {
            vm.warp(next);
        }
        uint32 drawId = pool.awardDraw(random == 0 ? 1 : random);
        awardedDraws.push(drawId);
        _snapshot(drawId);
    }

    // ---- 动作 7：领奖（验证 claim 不影响历史快照与零损失） ----
    function claimPrize(uint256 actorSeed, uint8 tierSeed, uint256 drawSeed) public {
        if (awardedDraws.length == 0) return;
        address actor = _actor(actorSeed);
        uint8 tier = uint8(tierSeed % TIER_COUNT);
        uint32 drawId = awardedDraws[drawSeed % awardedDraws.length];
        if (pool.getClaimableAmount(actor, tier, drawId) == 0) return;
        try pool.claimPrize(actor, tier, drawId) { } catch { }
    }

    function _snapshot(uint32 drawId) internal {
        for (uint256 a = 0; a < actors.length; a++) {
            address actor = actors[a];
            for (uint8 t = 0; t < TIER_COUNT; t++) {
                snapshot[drawId][actor][t] = pool.getClaimableAmount(actor, t, drawId);
            }
        }
    }
}

contract SimpleTwabInvariantTest is TwabInvariantBase {
    function _deployTwab() internal override returns (ITwabController) {
        return new SimpleTwabController();
    }
}

contract ObservationTwabInvariantTest is TwabInvariantBase {
    function _deployTwab() internal override returns (ITwabController) {
        return new ObservationTwabController();
    }
}
