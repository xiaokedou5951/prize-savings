# LiquidationPair 清算定价 decimals 归一化 实施计划

## 仓库调研

### 现状（问题）

[LiquidationPair.sol#L80-82](../../contracts/src/LiquidationPair/LiquidationPair.sol) 的定价：

```solidity
function computeExactAmountIn(uint256 amountOut) public view returns (uint256) {
    return amountOut * _price() / PRICE_SCALE;   // PRICE_SCALE = 1e18
}
```

`amountOut` 是 tokenOut（USDC，6 decimals）的 raw 数量，返回值是 tokenIn（PRIZE，18 decimals）的 raw 数量。合约**没有按两种 token 的 decimals 做换算**，直接 1 raw 换 1 raw。

部署时 `startPrice = 1e18`，满价时：

```
amountIn = amountOut  =>  1 raw USDC → 1 raw PRIZE
=>  1e-6 USDC → 1e-18 PRIZE
=>  1 USDC → 1e-12 PRIZE
```

即 1 USDC 的收益只能换来十亿分之一 PRIZE，前端 6 位小数格式化后显示为 0。这正是 [manual-e2e.md](../docs/testing/manual-e2e.md) §6.1 里"刻意放大捐赠到 1e20 raw"的根因。

### 设计意图（ADR-0004 第 18 行）

> 仅清算定价一处涉及 USDC/奖币两种 decimals，由各自 ERC20 元数据承担。

该意图在当前实现中**未被履行**，本修复补齐。

### 修复思路

在构造函数读取两个 token 的 `decimals()`，把 `amountOut`（tokenOut 单位）折算成 tokenIn 单位后再乘价格：

```
amountIn = amountOut × price × 10^tokenInDecimals / (PRICE_SCALE × 10^tokenOutDecimals)
```

对 USDC(6)→PRIZE(18)：`amountIn = amountOut × 1e18 × 1e18 / (1e18 × 1e6) = amountOut × 1e12`。满价时 1 USDC 收益 → 1 PRIZE，符合"1:1 价值"的 mock 定价假设。

### 溢出与精度校核

- `amountOut` 上限 ≈ 1e30，`_price()` ≤ 1e18，`10^tokenInDecimals` ≤ 1e18 → 分子 ≈ 1e66，远小于 uint256 上限（~1e77），无溢出。
- 先乘后除，精度损失仅在最后一次除法（`10^tokenOutDecimals`），对 6/18 组合无实质损失。

### ABI 影响

**无**。`computeExactAmountIn(uint256)(uint256)`、`swapExactAmountOut(uint256,address)(uint256)` 签名不变；新增的 `decimals()` 调用在构造函数内部、不进 ABI。所以 `packages/contracts/src/abis/LiquidationPair.ts` **无需重新生成**。

### 测试影响面

- `LiquidationPair.t.sol`：3 处具体数值断言需更新（满价 `amountIn = amountOut × 1e12`）。
- `Integration.t.sol`：仅 `assertGt(amountIn, 0)`，无需改动。
- `PrizeVault.t.sol`：不调用 swap，无需改动。

---

## 文件与改动

| 文件 | 改动 |
|------|------|
| `contracts/src/LiquidationPair/LiquidationPair.sol` | 引入 `IERC20Metadata`；新增 `tokenInDecimals`/`tokenOutDecimals` immutable（构造时读取）；改写 `computeExactAmountIn` 公式；更新 NatSpec |
| `contracts/test/LiquidationPair.t.sol` | 更新 3 处期望值（满价 1 USDC yield → 1 PRIZE）；修正注释"1 USDC yield = 1 奖币"现在为真 |
| `docs/testing/manual-e2e.md` | §6.1 捐赠量改回正常数量（100 USDC = 100e6）；删除"放大数量绕过 decimals"的注释；§6.2 预期奖池 ≈ 100 PRIZE；§9 FAQ 删除"奖池显示为 0"的小数成因条目 |

不改：`Deploy.s.sol`（`startPrice=1e18` 仍表示满价 1:1 价值）、ABI、`module-contracts.md`（事件/接口签名不变）、ADR（决策记录不动）。

---

## 实施步骤

1. **改合约** `LiquidationPair.sol`：
   - `import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";`
   - 新增 `uint8 public immutable tokenInDecimals; uint8 public immutable tokenOutDecimals;`
   - 构造函数内：`tokenInDecimals = IERC20Metadata(tokenIn_).decimals(); tokenOutDecimals = IERC20Metadata(tokenOut_).decimals();`
   - `computeExactAmountIn`：
     ```solidity
     return amountOut * _price() * 10 ** tokenInDecimals / (PRICE_SCALE * 10 ** tokenOutDecimals);
     ```
   - 更新 `_price()`/`computeExactAmountIn` 的 NatSpec，说明价格是「每 1 单位 tokenOut 值多少 tokenIn」。

2. **改测试** `LiquidationPair.t.sol`：
   - `test_price_decreases_over_time`：`computeExactAmountIn(1e6)` 起点断言 `1e18`，半程 `5e17`，周期末 `< 1e18`。
   - `test_swap_injects_prize_and_grants_yield`：`expectedIn = available * 1e12`；事件断言 `emit Liquidation(LIQUIDATOR, LIQUIDATOR, expectedIn, available)`；`assertEq(amountIn, expectedIn)`。
   - `test_amount_out_capped_by_liquidatable`：同上改 `available * 1e12`。
   - 注释 `1 USDC yield = 1 奖币` 现在字面成立。

3. **改文档** `docs/testing/manual-e2e.md`：
   - §6.1 捐赠命令：`mint(address,uint256) $YIELD 100000000`（100 USDC）；删除「数量刻意放大」两行注释，改为一行说明「满价时 1 USDC 收益 ≈ 1 PRIZE」。
   - §6.2 预期：奖池 ≈ 100 PRIZE；清算者收到 ≈ 100 USDC 收益。
   - §9 FAQ：删除「奖池金额显示为 0」那条（成因已消除）。

4. **验证**：
   - `forge build --root contracts`
   - `forge test --root contracts`（LiquidationPair 3 cases + 全量 38 cases 通过）
   - `forge fmt --root contracts --check`
   - `pnpm --filter @prize-savings/contracts build`（ABI 未变，确认类型仍通过）

---

## 依赖与注意

- OZ `IERC20Metadata.decimals()` 返回 `uint8`；MockERC20 与生产 ERC20 均实现。若 token 不含 `decimals()`，构造函数 revert——可接受（标准 ERC20 都有）。
- `10 ** uint8` 在 Solidity 中合法；结果为 uint256。
- 构造函数现多 2 次 `decimals()` 静态调用（部署时一次性），不影响运行时 gas。
- 不改变 `_periodEnd`/`_price` 的时间衰减逻辑，只改 `computeExactAmountIn` 的量纲换算。

---

## 风险

| 风险 | 处理 |
|------|------|
| 公式乘除顺序导致精度/溢出 | 先乘后除一次；分子上界 1e66 ≪ uint256 上限；6/18 组合精度无损 |
| 测试数值更新遗漏 | LiquidationPair.t.sol 全量重跑，三处 assert 逐一对照新公式 |
| 文档数量描述与实际不符 | 改完跑一次 `forge test` 取真实 event amountIn 回填文档预期值 |
| 误改 ABI/Deploy | 明确不碰 ABI 与 Deploy.s.sol；验证步骤含 SDK build 确认 ABI 稳定 |
