# P0-1 不变量状态机 fuzz 测试实现计划

> 目标：把 [contracts/test/Invariants.t.sol](../contracts/test/Invariants.t.sol) 的 fuzz 单测形态升级为 **forge-std `StdInvariant` handler-based 状态机 fuzz**，覆盖全部三条全局不变量，重点补齐**不变量 3（TWAB 只读追溯）**的自动化验证，并让 `ObservationTwabController` 也纳入不变量套件。

## Repository Research

### 1. 当前测试形态与缺口

[Invariants.t.sol](../contracts/test/Invariants.t.sol) 现有两个 fuzz 用例：

- `test_fuzz_deposit_withdraw_no_loss(uint256, uint256)`：两轮独立的 deposit → redeem 序列，断言零损失。
- `test_fuzz_yield_and_withdraw_no_loss(uint256, uint256, uint256)`：注入收益后存取，断言零损失。

缺口（即本任务要解决的）：

1. **不是状态机 fuzz**：每个用例是带 fuzz 参数的单测，动作序列固定两轮，没有跨动作随机序列、没有持续累积的系统状态。
2. **不变量 3 无覆盖**：没有任何用例验证「awardDraw 之后，后续存取款不改变历史 draw 的中奖结果」。
3. **`ObservationTwabController` 未纳入**：现有 Invariants 只实例化 `SimpleTwabController`。

### 2. 不变量 3 的精确定义与可验证性

[PrizePool.getClaimableAmount](../contracts/src/PrizePool/PrizePool.sol#L139-L154) 的输出依赖：

| 依赖 | 何时固化 |
|------|----------|
| `draw.winningRandomNumber` / `draw.drawStart` / `draw.drawEnd` | `awardDraw` 时写入 `_draws[drawId]`，之后只读 |
| `_prizeSize[drawId][tier]` | `awardDraw` 时计算固化，之后只读 |
| `twabController.getAverageTotalSupplyBetween(drawStart, drawEnd)` | **历史区间查询** |
| `twabController.getTwabBetween(winner, drawStart, drawEnd)` | **历史区间查询** |

因此不变量 3 等价于：**对于任意已结束的 draw 区间 `[drawStart, drawEnd]`，后续任意 `mint/burn/transfer` 都不得改变该区间的 `getTwabBetween` / `getAverageTotalSupplyBetween` 返回值**，进而 `getClaimableAmount` 不变。

验证策略：在 handler 每次成功 `awardDraw` 后，对所有 actor × 3 tier 记录 `getClaimableAmount` 快照；每轮 invariant 检查当前值与快照严格相等。注意 `getClaimableAmount` 不读 `_claimed`，所以 `claim` 动作不干扰快照（符合预期）。

### 3. 可复用的代码库约定

- **base + 子类模式**：[TwabControllerBehavior.t.sol](../contracts/test/TwabControllerBehavior.t.sol) 用抽象合约 + `_deployTwab()` 虚函数，让 Simple / Observation 两套实现跑同一套断言。本任务复用此模式。
- **部署组装**：参考 [Integration.t.sol](../contracts/test/Integration.t.sol) 的 `_deploy()`：`TestERC20`(USDC, 6 decimals) → `MockERC4626`(yieldVault, 8 decimals) → `TwabController` → `PrizeVault` → `twab.setVault(vault)` hand-off → `PrizePool(drawManager = 测试合约)` → `vault.setPrizePool(pool)`。
- **mock 接口**：`yieldVault.simulateYield(uint256)` 注入收益（Integration 已用）；`underlying.mint(actor, amount)`；actor 需 `underlying.approve(vault, amount)` 后 `vault.deposit`。
- **forge-std**：`StdInvariant` 提供 `targetContract(address)` 注册 handler、`targetSender` / `excludeSender` 限定调用者；handler 的 `public` 函数被随机调用，每轮后执行测试合约中所有 `invariant_*` 函数。
- **foundry.toml**：当前无 `[invariant]` 段，使用 forge 默认（runs=256, depth=15）。必要时新增该段调参。

## Files and Modules

- **新增** `contracts/test/InvariantsHandler.t.sol`：handler fuzz 套件（独立文件，不修改现有 `Invariants.t.sol`，保留其快速 fuzz 单测作回归）。
  - `abstract contract TwabInvariantBase is StdInvariant`：部署 + target 注册 + 三个 invariant 函数。
  - `contract InvariantHandler`：封装随机动作 + 快照记录。
  - 两个具体子类：`SimpleTwabInvariantTest`、`ObservationTwabInvariantTest`，各自实现 `_deployTwab()`。
- **可选修改** `contracts/foundry.toml`：新增 `[invariant]` 段（`runs` / `depth` / `fail_on_revert`），仅当默认值导致测试过慢或无效时调整。
- **可选文档更新** `contracts/ARCHITECTURE.md`：在「测试覆盖」表的 Invariants 行标注已升级为 handler fuzz 并覆盖不变量 3。

## Implementation Steps

1. **新建测试文件骨架**：`InvariantsHandler.t.sol`，定义 `TwabInvariantBase`，`setUp()` 中按 Integration 模式部署全套合约，`drawManager = address(this)`，调用 `targetContract(handler)` 注册 handler，`targetSender` 限定 actor 集合（或 `excludeSender` 排除合约地址）。

2. **实现 `InvariantHandler` 合约**（持有合约引用 + 固定 actor 数组，如 3 个 actor），提供以下 `public` 动作（每个带边界守卫，用 `vm.prank` 切换 actor，内部 `try/catch` 或前置 `require` 避免无谓 revert）：
   - `deposit(uint256 actorSeed, uint256 amountSeed)`：选 actor，`amount` 夹取到 actor 的 underlying 余额上限，approve 后 `vault.deposit`。
   - `redeem(uint256 actorSeed, uint256 sharesSeed)`：选 actor，`shares` 夹取到 `vault.balanceOf(actor)`，`vault.redeem`。
   - `transferShares(uint256 fromSeed, uint256 toSeed, uint256 sharesSeed)`：actor 间份额转账 `vault.transfer`（触发 `twab.transfer`）。
   - `simulateYield(uint256 amountSeed)`：向 yieldVault 注入利息，制造 totalAssets 增长（验证收益下零损失仍成立）。
   - `warpAndAwardDraw(uint256 randomSeed)`：`vm.warp` 到 `nextDrawStart()` 之后，调 `prizePool.awardDraw(random)`；**成功后立即对所有 actor × 3 tier 记录 `getClaimableAmount` 快照**到 handler 内 `mapping(uint32 => mapping(address => mapping(uint8 => uint256)))`。
   - `claimPrize(uint256 actorSeed, uint8 tier, uint32 drawId)`：actor 领奖（验证 claim 后零损失与历史快照不受影响）。

3. **定义三个 invariant 函数**（在 `TwabInvariantBase`，每轮随机动作后自动执行）：
   - `invariant_noLoss()`：`assertGe(vault.totalAssets(), vault.totalSupply())`。
   - `invariant_shareConservation()`：`assertEq(twab.totalSupply(), vault.totalSupply())`（天然恒等，作安全网）。
   - `invariant_twabReadonlyHistory()`：遍历 handler 记录的所有已开奖 draw × actor × tier，`assertEq(prizePool.getClaimableAmount(...), snapshot)`——**核心验证不变量 3**。

4. **两个子类实例化**：`SimpleTwabInvariantTest` / `ObservationTwabInvariantTest` 仅 override `_deployTwab()`，跑同一套 handler + invariant，确保两种 TWAB 实现都通过三条不变量。

5. **本地验证**：`forge test --root contracts` 全绿；重点查看 `--mt invariant_` 的 runs 输出与调用统计。

6. **测试有效性冒烟（mutator check，验证后回退）**：临时篡改 `SimpleTwabController._getTwabBetween` 让其返回最新余额（注入 bug），确认 `invariant_twabReadonlyHistory` 失败；然后**回退篡改**。确保 invariant 不是恒真、确有捕获能力。

7. **（可选）foundry.toml 调参与 ARCHITECTURE.md 更新**：若默认 runs/depth 下测试过慢或动作覆盖率不足，在 `[invariant]` 段调整；更新 `contracts/ARCHITECTURE.md` 测试覆盖表。

## Dependencies and Considerations

- 依赖 `forge-std/StdInvariant.sol`（已在 `contracts/lib/forge-std`，现有测试已 import forge-std）。
- **actor 数量与成本**：快照遍历成本 = 已开奖 draw 数 × actor 数 × 3 tier。actor 固定 3 个，`depth` 控制开奖总数，避免每轮 invariant 计算过慢。
- **时间推进**：`drawPeriodSeconds = 1 days`；`warpAndAwardDraw` 必须先 warp 到 `nextDrawStart()` 之后才能开奖。warp 幅度要可控，避免跳太远导致大量空 draw 区间。
- **份额守恒恒等性**：`vault.totalSupply()` 经 `TwabERC20` 直读 `twab.totalSupply()`，故不变量 2 天然成立；仍保留断言，防止未来重构（如份额落地存储）破坏守恒。
- **claim 不影响快照**：`getClaimableAmount` 不读 `_claimed`，claim 不改变历史可领理论值；但 claim 消耗 `_reserve` 与奖币余额，handler 需保证奖币充足（yield 注入或 prizeToken 预置），使零损失在 claim 后仍成立。
- **不改生产合约**：本任务只新增测试 + 可选配置/文档；若 invariant 暴露真实合约 bug，定位后另行修复（不在本计划默认范围，发现时单独确认）。

## Validation

- `forge test --root contracts` → 全绿（原有 52 passed 保持 + 新增 handler invariant 用例通过）。
- `forge test --mt invariant_ --root contracts -vv` → 确认 runs 数（默认 256）与各 handler 动作均有实际调用（非空转）。
- mutator check：注入历史查询 bug 后 `invariant_twabReadonlyHistory` 必须 fail（验证有效性），回退后恢复 pass。
- `forge fmt --root contracts --check` → 新文件格式合规。

## Risks

- **测试过慢 / gas 高**：降低 `[invariant] depth` 或 actor 数；优先保证不变量 3 的覆盖深度而非动作数量。
- **handler 大量 revert 导致动作空转、不变量空洞通过**：用 `-vv` 查看 call 统计；若某动作几乎没成功执行，调整边界守卫让其更易成功（如 amount 夹取更宽松），或用 `fail_on_revert = true` 暴露问题。
- **快照误报**：`getClaimableAmount` 是纯整数运算，同一历史输入必同一输出，只要历史查询真只读就无误报；若出现 fail，优先怀疑 TwabController 历史实现 bug 而非测试。
- **发现真实合约 bug**：若 invariant 失败，先区分测试逻辑错误 vs 合约 bug；合约 bug 需停下来定位、修复并补对应单测，再继续（属计划内弹性）。
