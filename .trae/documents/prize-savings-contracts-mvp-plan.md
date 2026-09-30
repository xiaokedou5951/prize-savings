# 储蓄抽奖应用 合约 MVP 实现计划

## 1. Summary（目标）

依据设计文档 [prize-savings-lottery-design.md](file:///Users/mac/work/2026/web3/prize-savings/docs/prd/prize-savings-lottery-design.md) 的 **M0 合约 MVP** 里程碑（第 11 节），在 `contracts/` 内实现核心 Solidity 合约，走通完整闭环：

> 存款 → 赚取收益 → 清算注入奖池 → 每日开奖 → 派奖 → 随时赎回本金

交付物：`TwabController` + `PrizeVault` + `PrizePool` + `LiquidationPair` 四个核心合约 + mocks + Foundry 单元/不变量/集成测试 + 部署脚本。

**已确认的两项关键决策（来自用户）**：
1. 开奖随机数：`awardDraw(uint256 winningRandomNumber)` 由**白名单 keeper 注入随机数**，合约不做链上 VRF。
2. TWAB：**同时实现两种算法、可配置切换**——
   - **简化时间加权累加器**（running integral + 按周期惰性 checkpoint）；
   - **忠实环形缓冲区 Observation**（时间加权 + 二分查找 + 精确定点回溯）。
   二者实现同一 `ITwabController` 接口，PrizeVault/PrizePool 只依赖接口，部署时按开关选择其一。

---

## 2. Current State（现状）

- `contracts/` 已是 `forge init` 生成的 Foundry 工程：`foundry.toml`（solc `0.8.24`、optimizer on、`evm_version=cancun`）、`remappings.txt`、`lib/` 依赖齐备。
- 依赖已就绪：
  - `forge-std`（`lib/forge-std/src/`）
  - OpenZeppelin Contracts **v5.0.0**（含 `ERC4626` / `IERC4626` / `Ownable(address initialOwner)` / `ERC20`）
  - Chainlink（VRF / Automation 接口已存在；**M0 不使用**，随机数由 keeper 注入）
- `remappings.txt` 当前：
  ```
  forge-std/=lib/forge-std/src/
  @openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/
  @chainlink/contracts/=lib/chainlink/contracts/
  ```
- `src/` 下 8 个模块目录（TwabController / PrizeVault / PrizePool / LiquidationPair / Claimer / VaultFactory / RngRelayAuction / mocks）与 `test/`、`script/` 均为 `.gitkeep` 占位，**无任何合约实现**。

### 关键 OZ v5 接口事实（已核实）
- `Ownable` 构造为 `Ownable(address initialOwner)`。
- `ERC4626` 构造为 `ERC4626(IERC20 asset_)`，继承 `ERC20`；`totalAssets()` 为 `virtual` 待实现。
- `ERC20` 的 `_transfer`/`_mint`/`_burn` 均内部转发到 `_update(address from, address to, uint256 value)`（**`_update` 是 virtual 钩子**）。→ TwabERC20 只需覆写 `_update`、`balanceOf`、`totalSupply` 即可把份额路由到 TwabController。

---

## 3. 目标文件结构

```
contracts/
├── src/
│   ├── interfaces/
│   │   ├── ITwabController.sol
│   │   ├── IPrizeVault.sol
│   │   ├── IPrizePool.sol
│   │   └── ILiquidationPair.sol
│   ├── libraries/
│   │   ├── ObservationLib.sol      # Observation 环形缓冲区 + 二分查找（实现 B 用）
│   │   ├── TwabLibObservation.sol  # 账户余额更新 / 记录 Observation / getTwabBetween（实现 B）
│   │   └── TwabLibSimple.sol       # running integral 累加器 + 周期 checkpoint（实现 A）
│   ├── TwabController/
│   │   ├── TwabController.sol      # 抽象基类：onlyVault 权限 + totalSupply + 公共查询骨架
│   │   ├── SimpleTwabController.sol     # 实现 A：简化时间加权累加器
│   │   └── ObservationTwabController.sol# 实现 B：忠实环形缓冲区
│   ├── PrizeVault/
│   │   ├── TwabERC20.sol           # 份额 ERC20 路由到 TwabController
│   │   └── PrizeVault.sol          # ERC4626 + TwabERC20 + Ownable
│   ├── PrizePool/
│   │   └── PrizePool.sol           # 奖池 + 分级开奖 + claim（含加权抽签）
│   ├── LiquidationPair/
│   │   └── LiquidationPair.sol     # yield → 奖币 线性降价清算
│   └── mocks/
│       ├── MockERC20.sol           # USDC / 奖币 mock（可自定义 decimals）
│       └── MockERC4626.sol         # 收益金库 mock（可 mockHarvest 注入收益）
├── test/
│   ├── TwabController.behavior.t.sol # 抽象共享行为测试（对两种实现各跑一遍）
│   ├── SimpleTwabController.t.sol    # 实现 A：实例化 + 复用行为测试
│   ├── ObservationTwabController.t.sol# 实现 B：实例化 + 复用行为测试
│   ├── PrizeVault.t.sol
│   ├── PrizePool.t.sol
│   ├── LiquidationPair.t.sol
│   ├── Integration.t.sol           # 完整闭环端到端（两种 TWAB 各跑一遍）
│   └── Invariants.t.sol            # 零损失 / 份额守恒 不变量 fuzz
└── script/
    └── Deploy.s.sol                # 部署 + 组装 + 授权
```

> 8 个模块目录中 `Claimer/`、`VaultFactory/`、`RngRelayAuction/` 保留 `.gitkeep` 占位，M0 不实现（对应设计文档 P2/M2）。

---

## 4. Proposed Changes（具体改动）

### 4.1 库与基础设施

三种库，两种算法；统一由 `ITwabController` 接口对外暴露（PrizeVault/PrizePool 只依赖接口，不感知实现）。

#### `src/interfaces/ITwabController.sol`（两种实现的共同契约）
按设计文档 7.2 精简，函数签名对实现 A/B 完全一致：
- `mint(address to, uint256 amount)`、`burn(address from, uint256 amount)`、`transfer(address from, address to, uint256 amount)`（仅 vault 可调）
- `balanceOf(address)`、`totalSupply()`
- `getBalanceAt(address, uint32)`、`getTwabBetween(address, uint32 start, uint32 end)`
- `getTotalSupplyAt(uint32)`、`getAverageTotalSupplyBetween(uint32 start, uint32 end)`

#### 实现 A —— `src/libraries/TwabLibSimple.sol`（简化时间加权累加器）
- `struct Account { uint256 balance; uint32 lastUpdate; uint256 cumulative; }`：`cumulative` 为「至今 ∫ balance dt」的 running integral。
- `checkpoint(account, now)`：结算上一段 `cumulative += balance × (now − lastUpdate)`，`lastUpdate = now`。
- `increaseBalance / decreaseBalance / transfer`：先 `checkpoint` 再改 `balance`。
- 历史回溯：除 running integral 外，`SimpleTwabController` 额外维护 `mapping(address => mapping(uint32 periodId => uint256 cumulativeAtPeriodStart))` 的**按开奖周期惰性 checkpoint**——当用户后续再次交互或首次被查询时，把「周期起点」处的 `cumulative` 落盘，从而支撑开奖结束后对 `[drawStart, drawEnd]` 的 TWAB 计算（无需链上枚举用户）。
- `getTwabBetween(start, end)`：由 `cumulative(end) − cumulative(start)` 差值 `/ (end − start)` 得到平均余额（`cumulative(t)` 取自周期 checkpoint + 线性插值）。
- 特性：实现简单、gas/存储省；精度为「按周期对齐」的粗粒度，适合 MVP。

#### 实现 B —— `src/libraries/ObservationLib.sol` + `TwabLibObservation.sol`（忠实环形缓冲区）
- `struct Observation { uint32 timestamp; uint256 balance; uint256 cumulativeBalance; }`
  - `timestamp`：该次余额变动的区块时间。
  - `balance`：在 `[timestamp, next.timestamp)` 区间内生效的余额。
  - `cumulativeBalance`：到 `timestamp` 为止的「余额 × 时间」累计值。
- 固定容量环形缓冲区：`MAX_CARDINALITY = 2**16`（uint16 索引，满则覆盖最旧记录，回溯最长约 1 年）。
- `binarySearch(observations, cardinality, nextIndex, targetTimestamp)`：返回「时间 ≤ target 的最新 observation」下标（二分）。
- `increaseBalance / decreaseBalance / transfer`：每次余额变化写一条 Observation（`cumulativeBalance = 旧cumulative + 旧balance × (now − 旧timestamp)`）。
- `getBalanceAt / getTwabBetween`：二分定位后按段内 `balance` 线性插值，`twab = (cum(end) − cum(start)) / (end − start)`。
- 说明：相较 PoolTogether 的 2 字段 Observation（余额靠相邻两条反推），此处每条约多存一个 `balance` 字段以简化取值，算法语义等价、回溯/时间加权逻辑忠实。

#### `src/interfaces/*.sol`
除 `ITwabController` 外的 `IPrizeVault` / `IPrizePool` / `ILiquidationPair` 按 4.3–4.5 各函数签名定义，供合约间解耦调用。

---

### 4.2 `TwabController`（抽象基类 + 两个实现，公平性基石）

**抽象基类 `src/TwabController/TwabController.sol`**：
- 持有 `ITwabController vault` 权限位与 `uint256 _totalSupply`；实现 `onlyVault` 修饰符、`totalSupply()` 及与实现无关的公共逻辑。
- 声明 `virtual`：`_mint` / `_burn` / `_transfer` / `_getBalanceAt` / `_getTwabBetween` / `_getAverageTotalSupplyBetween`，由子类落地。

**实现 A `SimpleTwabController.sol`**（`is TwabController, ITwabController`）：
- 存储 `mapping(address => TwabLibSimple.Account) _accounts` + 周期 checkpoint mapping；调用 `TwabLibSimple` 实现上述抽象方法。

**实现 B `ObservationTwabController.sol`**（`is TwabController, ITwabController`）：
- 存储 `mapping(address => TwabLibObservation.Account) _accounts`；调用 `ObservationLib`/`TwabLibObservation` 实现上述抽象方法。

> 「可配置切换」即：PrizeVault/PrizePool 构造只接收 `ITwabController`，部署脚本按参数选择实例化 `SimpleTwabController` 或 `ObservationTwabController`；二者对外行为一致，可无缝替换。
> **M0 不含 `delegate` 委托**（设计文档 FR-9 为 P2，延后）。

---

### 4.3 `PrizeVault.sol` + `TwabERC20.sol`

#### `TwabERC20.sol`（`is ERC20`）
- 覆写 `balanceOf`、`totalSupply` → 直读 `ITwabController`。
- 覆写 `_update(from, to, value)`：`from==0`→`twab.mint(to,value)`；`to==0`→`twab.burn(from,value)`；其余→`twab.transfer(from,to,value)`；并在内部 emit `Transfer`（沿用 ERC20 语义，不调用父 `_update` 以避免写冗余 `_balances`）。
- 构造 `ERC20(name_, symbol_)` 透传。

#### `PrizeVault.sol`（`is TwabERC20, ERC4626, Ownable`）
构造：`(IERC20 asset_, IERC4626 yieldVault_, ITwabController twab_, string name_, string symbol_, address owner_)`。
- `TwabERC20(name_, symbol_)`、`ERC4626(asset_)`、`Ownable(owner_)`；把 `twab_` 地址传入 `TwabERC20`（或在 `_update` 中读取，实现时保证唯一副本）。
- 状态：`uint256 _totalDebt`（已投到底层 yieldVault 的本金）、`uint256 _yieldBuffer`（收益缓冲，吸收舍入误差）。
- `totalAssets() override` = `yieldVault` 内本金的当前估值(`convertToAssets`) + 合约持有的 loose asset 余额。
- 存款/赎回走 ERC4626 `deposit/mint/withdraw/redeem`（底层 `_deposit/_withdraw` 会自动经 `_mint/_burn` 路由到 TWAB）。
- 收益接入：`convertToShares/convertToAssets` 基于「`_totalDebt` → yieldVault 当前份额价值」实现，使 yield 累积自动抬升单价。
- `liquidatableBalanceOf() view` = `totalAssets() − totalSupply() − _yieldBuffer`（超过本金+缓冲的可清算收益，向下取整、不小于 0）。
- `transferTokensOut(address receiver, uint256 amountOut)`：仅 `liquidationPair` 可调；从 yieldVault 赎回 `amountOut` 底层资产转给 `receiver`。
- `setLiquidationPair(address pair)`：`onlyOwner`，绑定唯一清算对。
- `setYieldBuffer(uint256)`：`onlyOwner`。
- `withdraw/redeem` 前校验本金可还（`totalAssets() >= totalSupply()` 不变量兜底）。

> 设计文档中的 `contributePrizeTokens` / `claimPrize` hook 在 M0 不做（promise，M2），奖币注入由 LiquidationPair 直接转账进 PrizePool。

---

### 4.4 `LiquidationPair.sol`（yield → 奖币）

构造：`(IERC20 tokenIn_, IERC20 tokenOut_, IPrizeVault source_, uint32 periodLength_, uint32 periodOffset_, uint256 startPrice_)`。
- `tokenIn` = 奖币；`tokenOut` = 金库底层资产（USDC）；`source` = PrizeVault；`startPrice_` 为周期起点的「每单位 yield 所需奖币」（`1e18 = 1:1`）。
- **线性降价**（对应设计文档 7.4「随时间线性降价」）：
  - 当前价 `price(t) = startPrice × (periodEnd − t) / periodLength`，`periodEnd = periodOffset + k × periodLength` 的最近未来边界。
  - `computeExactAmountIn(amountOut) = amountOut × price(t) / 1e18`。
- `swapExactAmountOut(uint256 amountOut, address receiver) returns (uint256 amountIn)`：
  1. `amountOut = min(amountOut, source.liquidatableBalanceOf())`；
  2. `amountIn = computeExactAmountIn(amountOut)`；
  3. `tokenIn.safeTransferFrom(msg.sender, prizePool, amountIn)`（奖币**直接进奖池**）；
  4. `source.transferTokensOut(receiver, amountOut)`。
  - 返回实际 `amountIn`。
- `liquidatableBalanceOf() view` 透传 `source.liquidatableBalanceOf()`。
- `prizePool` 地址由构造注入，与 PrizePool 解耦（复用设计文档「清算者用奖币买走 yield，奖币注入奖池」）。

---

### 4.5 `PrizePool.sol`（奖池 + 分级开奖 + claim）

构造：`(IERC20 prizeToken_, ITwabController twab_, uint32 drawPeriodSeconds_, uint32 drawPeriodOffset_, address drawManager_)`。
- `drawManager`（keeper）仅能调 `awardDraw`（可后续 `setDrawManager` 由 owner 换）。

**分级奖金（3 档，对齐设计文档 8.2，构造硬编码）**：
- `tierCount = 3`，每档 `prizeCount`（奖项数）与 `tierFraction`（占当期奖池比例，`1e18` 为单位）：
  | tier | 名称 | prizeCount | tierFraction |
  |------|------|-----------|--------------|
  | 0 | Grand Prize | 1 | 60% (6e17) |
  | 1 | 次级奖 | 4 | 25% (2.5e17) |
  | 2 | Canary | 100 | 15% (1.5e17) |

**开奖 `awardDraw(uint256 winningRandomNumber) onlyDrawManager`**：
- 要求当前抽奖周期已结束（`block.timestamp >= nextDrawStart = drawPeriodOffset + (drawId+1) × drawPeriodSeconds`）。
- `drawAmount = prizeToken.balanceOf(this) − _reserved`（`_reserved` 为已登记待领取金额，防重复计入）。
- 记录 `drawId`、`winningRandomNumber`、`drawStart/drawEnd`，为每档计算 `prizeSize_t = drawAmount × tierFraction_t / prizeCount_t`。
- emit `DrawAwarded(drawId, winningRandomNumber, drawAmount)`。

**中奖判定 `isWinner(user, tier, drawId)` / `getClaimableAmount(user, tier, drawId)`（纯 view，可反复查询）**：
- `totalTwab = twab.getAverageTotalSupplyBetween(drawStart, drawEnd)`（分母）。
- `userTwab = twab.getTwabBetween(user, drawStart, drawEnd)`。
- **加权抽签（Algorand/PoolTogether 式，无需链上枚举用户，概率严格正比 TWAB）**：
  ```
  slots = (userTwab × prizeCount_t) / totalTwab
  remainder = (userTwab × prizeCount_t) % totalTwab
  seed = uint256(keccak256(abi.encode(user, drawId, tier, winningRandomNumber)))
  if (remainder > 0 && (seed % totalTwab) < remainder) slots += 1
  amount = slots × prizeSize_t
  ```
  - Grand Prize：`prizeCount=1`，`userTwab ≤ totalTwab` ⇒ 最多 1 个 slot。
  - Canary：`prizeCount=100`，大户可中多个 slot（多份小奖）。

**领取 `claimPrize(address user, uint8 tier, uint32 drawId)`**（任意人可代 `user` 领取，奖金发给 `user`）：
- `amount = getClaimableAmount(...)`，要求 `amount > 0`；
- 首次领取登记 `claimed[drawId][tier][user] = true`（`mapping(uint32 => mapping(uint8 => mapping(address => bool)))`）防重复；
- `prizeToken.safeTransfer(user, amount)`，`_reserved -= amount`；
- emit `PrizeClaimed(...)`。

**注入 `contributePrizeTokens(...)`（可选）**：M0 主要靠 LiquidationPair 直接 `transfer` 奖币进合约；此函数允许 vault/他人显式转入并记录（`prizeToken.safeTransferFrom`），保持接口对齐设计文档。

---

### 4.6 mocks

#### `src/mocks/MockERC20.sol`
- `mint(address, uint256)`（任意人可铸，测试用）、自定义 `name/symbol/decimals`。
- 用于：USDC（6 decimals）、奖币（18 decimals）。

#### `src/mocks/MockERC4626.sol`
- `is ERC4626(IERC20 asset_)`，可 depodit/withdraw。
- `mockHarvest(uint256 amount)`：`onlyOwner`（或 `asset.transferFrom` 由调用者）向金库**捐赠底层资产**，使 `totalAssets` 提升、份额单价抬升 → 模拟 Aave/Compound 收益累积。
- 无需真实时间 APY，测试中调用 `mockHarvest` 即可触发「收益 → 可清算」闭环。

---

### 4.7 关键不变量（对应设计文档 7.3，写入测试与注释）
1. **零损失**：任意时点 `PrizeVault.totalAssets() >= totalSupply()`（yield buffer 兜底）。
2. **份额守恒**：`TwabController.totalSupply() == PrizeVault.totalSupply()`。
3. **TWAB 只读追溯**：`awardDraw` 后任何存取款不改变历史 draw 的中奖结果（claimable 金额由 `drawStart~drawEnd` 的固定 TWAB 计算）。

---

### 4.8 测试（`test/`）

- **TwabController.behavior.t.sol（抽象共享行为测试）+ SimpleTwabController.t.sol + ObservationTwabController.t.sol**：以抽象基类测试（虚函数 `_deployTwab()` 由两端各覆盖）对**两种实现跑同一套断言**——mint/burn/transfer 后 `balanceOf/totalSupply`；`getBalanceAt` 时间点取值正确；`getTwabBetween` 时间加权正确（分段余额 × 时长）；实现 B 环满覆盖最旧记录后仍可回溯；权限（非 vault 调 mint 应 revert）；两种实现对同一账户时序给出等价 TWAB。
- **PrizeVault.t.sol**：deposit/withdraw/redeem 金额与份额换算；`mockHarvest` 前 `liquidatableBalanceOf()==0`，harvest 后 > 0；`totalAssets() >= totalSupply()`；`transferTokensOut` 仅 LiquidationPair 可调。
- **PrizePool.t.sol**：awardDraw 权限/周期校验；prizeSize 按档分配正确；`isWinner`/`getClaimableAmount` 与 TWAB 正比（用已知 totalTwab 断言 slot 数量）；claim 后防重复、余额正确；Grand Prize 最多 1 份。
- **LiquidationPair.t.sol**：价格随时间线性下降；`swapExactAmountOut` 正确扣奖币、得 yield、奖币进池；超额 amountOut 被 `liquidatableBalanceOf` 封顶。
- **Integration.t.sol**（闭环）：mock USDC+奖币+yieldVault+Twab+PrizePool+PrizeVault+LiquidationPair → 用户存款 → `mockHarvest` 注入收益 → 清算者 `swapExactAmountOut` 把收益换成奖币注入奖池 → `awardDraw(random)` → 某用户 `claimPrize` 领奖 → 原用户 `withdraw` 全额赎回本金。对**两种 Twab 实现各跑一遍**（参数化 `_deployTwab()`）。
- **Invariants.t.sol**：fuzz 随机存款/赎回/harvest/清算序列，断言零损失、份额守恒不变量恒成立。
- 开奖公平性抽样：多账户不同 TWAB 下，统计 `isWinner` 命中频率近似正比（确定性断言 + 期望值区间）。

---

### 4.9 部署脚本（`script/Deploy.s.sol`）

按设计文档 12.2 顺序，`vm.startBroadcast()` 内：
1. 部署 `MockERC20` USDC（6d）、奖币（18d）。
2. 部署 `MockERC4626`（USDC 收益金库）。
3. 部署 TwabController：按启动参数/环境变量 `TWAB_MODE`（`simple|observation`）二选一实例化 `SimpleTwabController` 或 `ObservationTwabController`。
4. 部署 `PrizePool(prizeToken, twab, period, offset, keeper)`。
5. 部署 `PrizeVault(USDC, yieldVault, twab, name, symbol, owner)`。
6. 部署 `LiquidationPair(prizeToken, USDC, vault, period, offset, startPrice)`。
7. `vault.setLiquidationPair(pair)`。
8. 铸币给测试账户（USDC/奖币）。
9. 写 `deployed.json`（各地址，含 `twabMode`）到 `broadcast/`。

> 不配置真实 Chainlink 订阅（M0 随机数由 keeper 注入）。

---

## 5. Assumptions & Decisions（决策与假设）

| 决策点 | 结论 |
|--------|------|
| 随机数 | `awardDraw(uint256)` + 白名单 keeper（用户确认）；无链上 VRF（M0），后续可外层包 VRF |
| TWAB | **两种实现都要 + 可配置切换**（用户确认）：实现 A 简化时间加权累加器、实现 B 忠实 Observation 环形缓冲区；统一 `ITwabController` 接口，部署时按 `TWAB_MODE` 二选一 |
| 委托 delegate | **M0 不做**（设计文档 FR-9 为 P2），后续 M1 加入 |
| 清算定价 | 线性降价（对应设计文档 7.4），非 PoolTogether 的 ContinuousGDA（MVP 简化） |
| 奖币注入 | LiquidationPair 将奖币直接 `transfer` 进 PrizePool，`PrizeVault.contributePrizeTokens` 暂不做 |
| 溢金结构 | 3 档硬编码（Grand 1 / 次级 4 / Canary 100；60%/25%/15%） |
| 编译器/依赖 | solc 0.8.24、OZ v5.0.0、forge-std；不新增依赖；Chainlink 存量但 M0 不引用 |
| 范围边界 | 不实现 Claimer / VaultFactory / RngRelayAuction / 委托 / 真实 Chainlink 订阅 |

---

## 6. Verification（验证步骤）

按根 `package.json` 已有脚本：
```bash
forge build --root contracts          # 全部合约编译通过、无警告级错误
forge test --root contracts -vvv      # 单测 + 不变量 + 集成 全绿
forge fmt --root contracts --check    # 格式通过（若需）
```

逐条预期：
1. `forge build` 成功（`out/` 生成各合约 ABI/bytecode）。
2. `SimpleTwabController.t.sol` / `ObservationTwabController.t.sol`（复用 `TwabController.behavior.t.sol`）/ `PrizeVault.t.sol` / `PrizePool.t.sol` / `LiquidationPair.t.sol` 各自通过。
3. `Integration.t.sol` 走通「存款 → 收益 → 清算入池 → 开奖 → 领奖 → 赎回本金」完整闭环。
4. `Invariants.t.sol` fuzz 断言零损失与份额守恒不变量永不违反。
5. `script/Deploy.s.sol` 在本地 anvil 可执行并输出 `broadcast/deployed.json`。

---

## 7. 明确不做（Out of Scope）

- Claimer / VaultFactory / RngRelayAuction 合约。
- TWAB 委托（delegate）。
- 链上 VRF / Chainlink Automation 接入（M0 随机数由 keeper 注入）。
- 前端、subgraph、keeper 业务逻辑（本计划仅合约 MVP）。