# M0 集成：接入真实 ERC-4626 收益源 + Base Sepolia 部署 实施计划（v2）

> v2 变更：按审查意见修订——收益源策略改为 **StataToken 优先、自研回退**；范围扩大到 **Base Sepolia 实际部署**；补齐首充通胀攻击防护、fork 测试守卫、Aave 惰性计息断言、OZ 舍入方向纠偏、默认套件覆盖、mock 守卫、ADR 与 module-contracts 同步。

## 已确认决策

- **收益源策略**：优先直接使用 Aave 官方 **StataToken**（StaticATokenLM，ERC-4626 合规、已审计、生产在用）——资金路径零新增自研合约。自研 `AaveYieldVault` 适配器仅作为"无 stata 市场"的回退路径实现，带首充攻击防护与默认套件单测。取舍记录于 ADR-0005。
- **范围**：含 Base Sepolia 实际部署与冒烟验证。**VRF 不在本计划**——维持 ADR-0003 的 keeper 注入路线，测试网阶段 drawManager 由部署者临时承担，VRF 另行计划。

## 仓库调研结论

- **PrizeVault 已完成收益源抽象**：[PrizeVault.sol](../../contracts/src/PrizeVault/PrizeVault.sol) 构造器接收 `IERC4626 yieldVault_`，核心合约（PrizeVault/Twab/PrizePool/LiquidationPair）零改动即可接入任意合规 ERC-4626。
- **通胀攻击边界**：PrizeVault 自身 1:1 恒等份额映射免疫 ERC-4626 通胀攻击（向它捐赠只会变成可清算 yield，不影响份额价格）；但**浮动汇率收益金库不免疫**——全新适配器（或全新 stata 实例）在部署后、首笔外部存款前，攻击者可 deposit 1 wei + 捐赠 aToken 抬价，使 `PrizeVault.totalAssets() < totalSupply()`，击穿零损失不变量。OZ v5 虚拟份额偏移只挡粉尘级攻击。
- **Aave v3 利息惰性更新**：`liquidityIndex` 仅在该储备发生状态变更交易时推进；`vm.warp` 不会让 `aToken.balanceOf` / `convertToAssets` / `liquidatableBalanceOf` 变化。fork 测试必须先"poke"再断言。
- **OZ v5 舍入方向（纠正 v1 表述）**：`convertToShares` Floor、`convertToAssets` **Ceil**（多报 ≤1 wei）——对零损失方向有利；`liquidatableBalanceOf` 理论上可高估 ≤1 wei，被 redeem 实际值钳制，可忽略。本代码库 `yieldBuffer` 的实际作用是把舍入粉尘**挡在清算者之外**（从可清算额中扣除），并不加进 `totalAssets`。
- **Aave 地址（已验证，来源 bgd-labs/aave-address-book，2026-10）**：

| 网络 | Aave POOL | USDC | USDC Stata |
|------|-----------|------|-----------|
| Base Sepolia | `0x8bAB6d1b75f19e9eD9fCe8b9BD338844fF79aE27` | `0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f` | `0xf430cb6E2b85f99222fBFA6dFEa18Ff60FA6B32a` |
| Base 主网（fork 测试用） | 实施时从 AaveV3Base 地址簿确认 | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | 实施时确认 |

- 注意 Base Sepolia 存在**多个 Aave 市场实例**（core / Lido）；实施时用 `POOL_ADDRESSES_PROVIDER.getPool()` 校验后把地址与来源写进 deployment.md。

## 方案

### 主路径：StataToken 直接作为 yieldVault

`Deploy.s.sol` 通过 `YIELD_VAULT_ADDRESS` 直接指向 USDC stata。PrizeVault 用到的全部接口（`deposit/convertToAssets/maxRedeem/previewWithdraw/redeem/balanceOf`）stata 均合规实现，资金路径**零新增自研合约**。共享实例已有存量 supply，通胀攻击在经济上不可行；部署脚本校验 `stata.totalSupply() > 0`，为 0 时打警告并提示需 seed（部署者先存入一笔份额发往死地址）。

### 回退路径：AaveYieldVault 自研适配器（无 stata 市场时）

```solidity
contract AaveYieldVault is ERC4626 {
    IAavePool public immutable pool;   // 最小接口：supply(asset, amount, onBehalfOf, referralCode) / withdraw(asset, amount, to)
    IERC20 public immutable aToken;

    function totalAssets() public view override returns (uint256) {
        return aToken.balanceOf(address(this)); // Aave v3 aToken 与底层 1:1，利息体现为余额增长
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        IERC20(asset()).safeTransferFrom(caller, address(this), assets);
        IERC20(asset()).forceApprove(address(pool), assets);
        pool.supply(asset(), assets, address(this), 0);
        _mint(receiver, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal override {
        _spendAllowanceIfNeeded(caller, owner, shares); // 按 OZ v5 原语义处理授权
        _burn(owner, shares);
        pool.withdraw(asset(), assets, receiver);
    }
}
```

- 不覆写 `_convertToShares/_convertToAssets`，沿用 OZ 默认（浮动汇率，利息自然摊入份额价格）。
- **首充攻击防护（必须）**：`Deploy.s.sol` 在同一 broadcast 内、任何外部存款前，由部署者对适配器做 **seed deposit**（金额默认 1_000 USDC，`AAVE_ADAPTER_SEED` 可覆盖），份额发往死地址（如 `address(0xdEaD)`）作 dead shares。脚本预检部署者 USDC 余额 ≥ seed。
- NatSpec 明示：`maxWithdraw/maxRedeem` 不覆写为查询底层协议流动性——Aave 流动性枯竭时 redeem 直接 revert，属已接受风险（与 PRD 10.2 收益源风险一致）。

### Deploy.s.sol 配置矩阵（三档回退）

| 环境变量 | 设置时的行为 | 未设置时的回退 |
|----------|--------------|----------------|
| `USDC_ADDRESS` | 直接用真实 USDC | 部署 MockERC20 |
| `PRIZE_TOKEN_ADDRESS` | 直接用真实奖币 | 部署 MockERC20（PRIZE） |
| `YIELD_VAULT_ADDRESS` | 直接用该 ERC-4626（**stata 主路径**） | ↓ |
| `AAVE_POOL` + `AAVE_ATOKEN` | 部署 AaveYieldVault（回退路径，含 seed） | ↓ |
| （都未设置） | — | `chainId == 31337`：部署 MockERC4626；**否则 revert** |

- **mock 守卫**：MockERC4626（本金路径）只许本地 anvil；`PRIZE` 用 MockERC20 在测试网可接受（不在本金路径，liquidator 需公开 mint 获取奖币，满足 M0 测试网需要），但脚本对非 31337 链打印一行提示。
- console.log 输出 `YieldVault` 地址与类型（mock/aave-adapter/stata），保持 deploy-local.sh 标签解析兼容。

## 文件与模块

| 文件 | 变更 |
|------|------|
| `contracts/src/PrizeVault/AaveYieldVault.sol` | 新增：回退适配器 + 最小 `IAavePool` 接口 |
| `contracts/src/mocks/MockAavePool.sol`、`MockAToken.sol` | 新增：默认套件单测用（aToken 余额可手动抬升模拟计息，约 40 行） |
| `contracts/test/AaveYieldVault.t.sol` | 新增：默认套件单测——deposit/redeem roundtrip、计息后 totalAssets 增长、maxRedeem 返回语义、seed 存在时外部存款无法显著改变汇率 |
| `contracts/test/ForkStataYield.t.sol` | 新增：Base 主网 fork，stata 全链路（skip guard + poke） |
| `contracts/script/Deploy.s.sol` | 修改：配置矩阵 + mock 守卫 + adapter seed + stata totalSupply 校验 |
| `contracts/foundry.toml` | 修改：`base = "${BASE_RPC_URL}"`、`base_sepolia = "${BASE_SEPOLIA_RPC_URL}"` |
| `frontend/src/lib/config/chains.ts` | 修改：`[foundry, baseSepolia]`，按 `NEXT_PUBLIC_CHAIN_ID`（31337/84532）选择 |
| `packages/contracts/src/deployments.ts` | 修改：部署后回填 `DEPLOYMENTS[84532]` |
| `scripts/deploy-testnet.sh` | 新增：Base Sepolia 部署包装（读 `BASE_SEPOLIA_RPC_URL` + `DEPLOYER_PRIVATE_KEY`，跑 forge script，打印地址供回填） |
| `contracts/ARCHITECTURE.md`、`docs/architecture/deployment.md`、`docs/architecture/module-contracts.md` | 修改：合约清单、测试网部署小节（含环境变量与 Aave 地址来源）、接口面同步 |
| `docs/decisions/ADR-0005-yield-source-stata-first.md` | 新增：收益源策略决策记录 |

> 前端改动小但受 Next.js 16 破坏性变更约束：动 frontend 代码前先读 `frontend/node_modules/next/dist/docs/` 相关部分（见 frontend/AGENTS.md）。

## 实施步骤

1. **foundry.toml**：补 `base` / `base_sepolia` RPC endpoint（env 占位，不入库）。
2. **AaveYieldVault 适配器**（回退路径）：实现 + NatSpec（maxRedeem 语义、OZ 舍入方向、aToken 1:1 假设——接 Compound cToken 等浮动汇率源时需改用 exchangeRate 换算）。
3. **MockAavePool/MockAToken + AaveYieldVault.t.sol**：进默认套件（满足工作区规则"资产转移函数需 test/ 覆盖"）。
4. **ForkStataYield.t.sol**（Base 主网）：
   - setUp 首行 skip guard：`if (bytes(vm.envOr("BASE_RPC_URL", string(""))).length == 0) vm.skip(true);`——否则默认 `pnpm contracts:test` 会因 `createSelectFork` revert 全红。
   - 资金注入：先试 `deal(USDC, user, amount)`，Base 原生 USDC 为代理代币，`deal` 失败则回退 whale `prank`+`transfer`（二选一实现并注释原因）。
   - 断言序列：`vault.deposit` 后 `totalAssets() >= totalSupply()` → `vm.warp(30 days)` → **poke**（funded 账户 `pool.supply(USDC, 1, addr, 0)` 触发 liquidityIndex 推进）→ `aToken/stata convertToAssets` 增长、`vault.liquidatableBalanceOf() > 0` → `vault.redeem` 拿回 ≥ 本金。
5. **Deploy.s.sol**：配置矩阵 + 守卫 + seed + 校验（见方案节）。
6. **本地回归**：`pnpm contracts:build / contracts:test`（fork 用例自动 skip，全绿）、`forge fmt --root contracts --check`、`pnpm deploy:local` 零配置行为不变（mock 全回退路径）。
7. **前端链配置**：chains.ts 双链 + `NEXT_PUBLIC_CHAIN_ID` 选择；确认 `getDeployment(84532)` 缺省时前端有明确报错路径。
8. **Base Sepolia 部署**：实施时先验证测试 USDC（`0xba50...`）的 mint/faucet 可用性 → 跑 `scripts/deploy-testnet.sh`（stata 主路径：`USDC_ADDRESS` + `YIELD_VAULT_ADDRESS` 指向 stata）→ 回填 `deployments.ts[84532]` 与 `frontend/.env.local`。
9. **测试网冒烟**（小额度，数百 USDC）：deposit → withdraw roundtrip（不等待真实利息）→（可选全链路）mint PRIZE → LiquidationPair 清算 → `awardDraw` → `claimPrize` → 赎回本金。
10. **文档同步**：contracts/ARCHITECTURE.md（清单 + 删除"待补 fork 测试"）、deployment.md（测试网小节 + 地址来源 + Base Sepolia 多市场校验说明）、module-contracts.md（新增合约接口面）、ADR-0005。

## 验证

- `forge build --root contracts` 通过；`forge test --root contracts` 默认套件全绿（fork 用例 skip），含新增 AaveYieldVault 单测。
- `BASE_RPC_URL=... forge test --root contracts --match-contract ForkStataYield` 通过，断言含 poke 后的 liquidatable > 0。
- `forge fmt --root contracts --check` 合规。
- `pnpm deploy:local` 零配置输出与现状等价（7 个地址 + 标签可解析）。
- Base Sepolia：部署产物地址可解析、回填后前端在 84532 链可连接、冒烟 roundtrip 成功。
- `pnpm frontend:dev` 在本地链（31337）与测试网（84532）两种 env 下均正常启动。

## 风险

| 风险 | 处理 |
|------|------|
| Base Sepolia 测试 USDC 不可公开 mint | 实施时验证 `0xba50...` mint 权限；不可 mint 则接 Aave 官方 faucet 或选持币 whale 来源；文档记录获取路径 |
| 测试网 aUSDC/stata 流动性薄 | 冒烟用小额（数百 USDC）；测试网 fork 冒烟前可先 `cast call` 查可用流动性 |
| 全新 stata/适配器实例的通胀窗口 | 共享 stata 有存量 supply（部署时校验 >0 并告警）；自研适配器 seed deposit + 单测断言 |
| fork 测试依赖外部 RPC | skip guard 保护默认套件；fork 用例仅手动/CI 可选跑 |
| `deal` 对 Base 原生 USDC 失败 | 回退 whale prank（计划内已定） |
| 适配器回退路径的长期维护成本 | ADR-0005 记录；M1 复评是否保留双路径 |
| Base Sepolia 多 Aave 市场实例混淆 | 用 `POOL_ADDRESSES_PROVIDER.getPool()` 校验 + deployment.md 记录地址来源与日期 |
