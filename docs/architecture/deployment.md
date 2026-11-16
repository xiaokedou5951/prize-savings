# 部署拓扑

> M0 两个目标环境：**本地 anvil**（默认）与 **Base Sepolia 测试网**（84532）。Base 主网仅用于 fork 测试，尚无主网部署规划（见 PRD 第 11 节 M0 集成之后）。

## 链配置

| 网络 | chainId | RPC 端点 | 用途 |
|------|---------|----------|------|
| anvil（foundry 本地链） | 31337 | `http://127.0.0.1:8545` | 合约开发、前端联调（默认） |
| Base Sepolia | 84532 | `BASE_SEPOLIA_RPC_URL`（环境变量，不入库） | 测试网部署验证 |
| Base 主网 | 8453 | `BASE_RPC_URL`（环境变量，不入库） | 仅 fork 测试（[ForkStataYield.t.sol](../../contracts/test/ForkStataYield.t.sol)） |

- 前端链配置：wagmi `foundry` + `baseSepolia` 双链，`NEXT_PUBLIC_CHAIN_ID` 选择默认链（31337 / 84532，见 [chains.ts](../../frontend/src/lib/config/chains.ts)）。
- forge 端点：[foundry.toml](../../contracts/foundry.toml) 的 `[rpc_endpoints]`（`local` / `base` / `base_sepolia`，后两者从环境变量读取）。

## Deploy.s.sol 配置矩阵

部署脚本按环境变量选择底层资产与收益源；资金安全相关的缺省在非本地链一律 revert，不会静默降级：

| 优先级 | 变量 | YvType | 行为 |
|--------|------|--------|------|
| — | `USDC_ADDRESS` | — | 未设时仅 31337 允许部署 mock USDC；非本地链 revert（本金路径不允许 mock） |
| — | `PRIZE_TOKEN_ADDRESS` | — | 未设时部署 MockERC20 奖币；奖币不在本金路径，测试网允许（脚本打印提示） |
| 1 | `YIELD_VAULT_ADDRESS` | `stata` | 直接使用现成 ERC-4626（主路径：Aave 官方 StataToken）；校验 `asset()` 匹配 USDC；`totalSupply()==0` 时打印首充通胀攻击警告 |
| 2 | `AAVE_POOL` + `AAVE_ATOKEN` | `aave-adapter` | 部署自研 AaveYieldVault 适配器；构造器校验 `UNDERLYING_ASSET_ADDRESS`（配错市场在部署时即 revert）；同一 broadcast 内 seed 首充锚定汇率 |
| 3 | （无收益源配置） | `mock` | 仅 31337 允许 MockERC4626；非本地链 revert |

适配器 seed：`AAVE_ADAPTER_SEED`（默认 1_000 USDC）首充份额发死地址 `0xdEaD`，防 ERC-4626 通胀攻击；设 0 可跳过但脚本警告；部署者 USDC 余额不足时 revert（预检）。取舍依据见 [ADR-0005](../decisions/ADR-0005-yield-source-stata-first.md)。

### Aave 参考地址

来源：[bgd-labs/aave-address-book](https://github.com/bgd-labs/aave-address-book)（2026-10 核验）。外部协议地址不属本仓库 SSOT 管辖（[deployments.ts](../../packages/contracts/src/deployments.ts) 只承载本仓库合约），使用前建议与来源再核对。

Base 主网（fork 测试用）：

| 角色 | 地址 |
|------|------|
| Aave Pool | `0xA238Dd80C259a72e81d7e4664a9801593F98d1c5` |
| USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| USDC StataToken | `0xC768c589647798a6EE01A91FdE98EF2ed046DBD6` |
| aUSDC | `0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB` |

Base Sepolia（测试网部署用）：

| 角色 | 地址 |
|------|------|
| Aave Pool | `0x8bAB6d1b75f19e9eD9fCe8b9BD338844fF79aE27` |
| USDC（测试币） | `0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f` |
| USDC StataToken | `0xf430cb6E2b85f99222fBFA6dFEa18Ff60FA6B32a` |
| PoolAddressesProvider | `0xE4C23309117Aa30342BFaae6c95c6478e0A4Ad00` |

## 本地部署步骤

推荐一条命令完成「部署 + 回填前端地址」（[scripts/deploy-local.sh](../../scripts/deploy-local.sh)）：

```bash
# 终端 1：起链（含 Multicall3 注入），保持常驻
pnpm chain

# 终端 2：部署并自动把 7 个地址写入 frontend/.env.local（保留已填的 WalletConnect projectId）
pnpm deploy:local
```

脚本内部等价于执行下列手工步骤；需要自定义时可直接照做：

```bash
# 编译 + 部署（--broadcast 实际发交易）
DEPLOYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
TWAB_MODE=simple \
  forge script script/Deploy.s.sol --root contracts --rpc-url local --broadcast
```

部署脚本 [Deploy.s.sol](../../contracts/script/Deploy.s.sol) 依次部署 USDC、奖币、收益源（本地默认 `MockERC4626`）、TWAB（按 `TWAB_MODE` 二选一）、PrizePool、PrizeVault、LiquidationPair，完成 `setVault` / `setLiquidationPair` 组装，并把 7 个地址 + `ChainId` / `YvType` 打印到 stdout（零配置行为与 SSOT 地址见 `DEPLOYMENTS[31337]`；anvil 重启后地址不变的前提是部署者 nonce 序列未被打乱）。

## Base Sepolia 部署步骤（runbook）

用 [scripts/deploy-testnet.sh](../../scripts/deploy-testnet.sh)（`pnpm deploy:testnet`），脚本做 RPC 预检、配置完整性检查、`forge script --broadcast`、地址提取：

```bash
BASE_SEPOLIA_RPC_URL=<RPC> \
DEPLOYER_PRIVATE_KEY=0x<部署账户私钥> \
USDC_ADDRESS=0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f \
YIELD_VAULT_ADDRESS=0xf430cb6E2b85f99222fBFA6dFEa18Ff60FA6B32a \
  pnpm deploy:testnet
```

前置条件：

1. 部署账户持有 Base Sepolia 测试 USDC（水龙头领取；仅 ETH 而无 USDC 无法完成部署后冒烟）。
2. 收益源用上表 StataToken（主路径，输出 `YvType: stata`）；若 stata 份额为 0，按脚本警告先对其 seed 存款（份额发死地址）再开放 PrizeVault 存款。
3. `PRIZE_TOKEN_ADDRESS` 可省略（部署 MockERC20 奖币，liquidator 需自行 mint）。

部署后必做：

1. **回填 SSOT**：把输出的 7 个地址填入 [deployments.ts](../../packages/contracts/src/deployments.ts) 的 `DEPLOYMENTS[84532]` 并同 PR 提交。`DEPLOYMENTS[84532]` 在真实部署前保持缺省（`getDeployment(84532)` 会 throw，前端相关查询自动禁用），**禁止预填占位假地址**。
2. **前端切换**：`NEXT_PUBLIC_CHAIN_ID=84532` 写入 `frontend/.env.local` 后 `pnpm frontend:build` 验证（或依赖 SSOT 回填后的默认值）。
3. **冒烟**：对 PrizeVault 小额 `deposit` → `redeem` roundtrip；`cast call` 验证 `PrizeVault.totalAssets() >= totalSupply()`。
4. **角色交接**：`PrizePool.setDrawManager(keeper)`（见下节）。

## 已部署地址（SSOT）

权威地址表在代码中：[packages/contracts/src/deployments.ts](../../packages/contracts/src/deployments.ts)。`DEPLOYMENTS[31337]` 已回填（anvil 零配置部署的确定性地址）；`DEPLOYMENTS[84532]` 留待首次真实部署后按上节 runbook 回填。`pnpm deploy:local` 自动写入 `frontend/.env.local`（默认路径，不入库）。需要共享给团队或换种方式时也可以：

1. 把 stdout 地址写入 `DEPLOYMENTS[31337]`（随仓库共享）；或
2. 手动复制 [frontend/.env.example](../../frontend/.env.example) 为 `frontend/.env.local` 填写（个人本地、不入库）。

> 安全约束：`.env*` 不入库；`PRIVATE_KEY` 只允许存在于本地环境。

## 环境变量清单

### frontend（`NEXT_PUBLIC_` 前缀，构建期注入）

| 变量 | 必填 | 说明 |
|------|------|------|
| `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` | 连钱包时必填 | WalletConnect Cloud projectId；占位值仅能通过构建 |
| `NEXT_PUBLIC_CHAIN_ID` | 否 | 默认 `31337`；`84532` 时默认链切到 Base Sepolia |
| `NEXT_PUBLIC_RPC_URL` | 否 | 默认 `http://127.0.0.1:8545` |
| `NEXT_PUBLIC_USDC` / `NEXT_PUBLIC_PRIZE_TOKEN` / `NEXT_PUBLIC_YIELD_VAULT` / `NEXT_PUBLIC_TWAB_CONTROLLER` / `NEXT_PUBLIC_PRIZE_POOL` / `NEXT_PUBLIC_PRIZE_VAULT` / `NEXT_PUBLIC_LIQUIDATION_PAIR` | 否 | 逐项覆盖 SSOT 地址 |

### keeper（运行期注入，[keeper/.env.example](../../keeper/.env.example)）

| 变量 | 说明 |
|------|------|
| `RPC_URL` | 节点 RPC |
| `PRIVATE_KEY` | 清算/开奖机器人签名密钥；需先被 `setDrawManager` 授权并持有奖币 |

### 合约脚本与测试（forge 环境变量）

| 变量 | 说明 |
|------|------|
| `DEPLOYER_PRIVATE_KEY` | 部署者私钥（本地默认 anvil 账户 #0） |
| `TWAB_MODE` | `simple`（默认）/ `observation` |
| `USDC_ADDRESS` / `PRIZE_TOKEN_ADDRESS` | 指向已部署代币；缺省时本地部署 mock（USDC 仅限 31337） |
| `YIELD_VAULT_ADDRESS` | 收益源主路径（现成 ERC-4626，如 Aave StataToken） |
| `AAVE_POOL` / `AAVE_ATOKEN` / `AAVE_ADAPTER_SEED` | 适配器回退路径（与 `YIELD_VAULT_ADDRESS` 互斥，配一半 revert；seed 默认 1_000 USDC） |
| `BASE_RPC_URL` | Base 主网 RPC，仅 fork 测试用；未设时 `ForkStataYield.t.sol` 自动 skip |
| `BASE_SEPOLIA_RPC_URL` | Base Sepolia RPC，`pnpm deploy:testnet` 必填 |

## 角色交接（部署后必做）

[Deploy.s.sol](../../contracts/script/Deploy.s.sol) 中 `PrizePool` 的初始 `drawManager` 是部署者本人。keeper 落地后需由 owner 执行一次：

```solidity
PrizePool.setDrawManager(keeperAddress);
```

在此之前，可用部署者账户直接 `cast send` 调 `awardDraw` 完成手工开奖联调。

## keeper 运行形态

规划为常驻 Node 进程（`tsx watch` 开发 / `node dist` 生产，见根 `pnpm keeper:dev|build`），轮询周期边界驱动清算与开奖。**当前为 no-op 脚手架**，无任何部署物；M1 接入 VRF 后需重新评估其可信边界（见 [ADR-0003](../decisions/ADR-0003-keeper-injected-rng-over-pfda.md)）。
