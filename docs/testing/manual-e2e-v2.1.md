# 手工端到端联调手册 v2.1（Base Sepolia 本地 Fork）

> 回答的问题：**在「本地 mock / 本地 Aave 适配器 / Base Sepolia 本地 Fork（真实 StataToken）」三种收益源部署下，把「存款 → 收益 → 清算入池 → 开奖 → 派奖 → 赎回」整条链路手工走通。**
>
> v2（[manual-e2e-v2.md](manual-e2e-v2.md)）的路径 C 直连真实 Base Sepolia 测试网，需水龙头、受出块速度限制、无法 `evm_increaseTime`。v2.1 将「真实收益源」改为 **anvil 本地 fork Base Sepolia**：状态来自真实测试网（StataToken / Aave Pool / USDC 均为官方地址），但跑在本地，可免费获取测试币、可快进时间。fork **保持 chainId 84532 不覆盖**，完整走 `Deploy.s.sol` 非本地安全分支；前端需临时把 `baseSepolia` 链的 RPC 指向本地 fork（§5.4.1）。合约不变量的自动化证明仍在 `contracts/test/`，本手册只做**跨模块手工回归**。部署细节 SSOT 是 [../architecture/deployment.md](../architecture/deployment.md)，收益源取舍见 [ADR-0005](../decisions/ADR-0005-yield-source-stata-first.md)。

---

## 1. 范围与路径矩阵

M0 集成后收益源由部署期环境变量三档回退决定（[Deploy.s.sol](../../contracts/script/Deploy.s.sol)）：

| 路径 | 链 / chainId | 触发条件 | YvType | 收益模拟方式 |
|------|--------------|----------|--------|--------------|
| A · 本地 mock | anvil 31337（无 fork） | 无收益源配置 | `mock` | 直接向 `MockERC4626` 捐赠 USDC |
| B · 本地适配器 | anvil 31337（无 fork） | `AAVE_POOL` + `AAVE_ATOKEN` | `aave-adapter` | `MockAToken.accrue(adapter, amount)` |
| **C · 本地 fork StataToken** | **anvil fork Base Sepolia（保持 84532，不覆盖链 ID）** | `USDC_ADDRESS` + `YIELD_VAULT_ADDRESS` = 官方地址 | `stata` | Aave 真实利率，**惰性计息**，需 poke |
| D · 真实测试网（仅生产验证） | Base Sepolia 84532 | 同 C，`BASE_SEPOLIA_RPC_URL` 指真实节点 | `stata` | 同 C，但不可 warp、需等真实出块 |

> 路径 C 是 v2.1 的重点：**fork 把真实 Base Sepolia 的状态拉到本地**，因此 `USDC` / `StataToken` / `Aave Pool` 都是真实合约与真实存量（`totalSupply > 0`，无通胀攻击窗口）。fork **不覆盖链 ID**，保持 84532，从而完整验证 `Deploy.s.sol` 的非本地分支（缺 `USDC_ADDRESS` / 收益源即 revert 等安全分支）。代价是前端需临时把 `baseSepolia` 链的 RPC 指向本地 fork（见 §5.4）。
>
> 三条路径的 PrizeVault / PrizePool / LiquidationPair 逻辑完全相同，差异仅在收益源如何产生 `liquidatableBalanceOf()`。路径 A 是日常联调默认；路径 B 验证适配器资金流与 seed；路径 C 验证真实 Aave 的惰性计息行为。

覆盖：

- 双链启动、部署、地址回填、钱包接入。
- 前端写路径：存款（approve + deposit）、赎回（withdraw）、领奖（claimPrize）。
- `cast` 模拟 keeper：注入收益、清算、快进时间、开奖。
- 三条全局不变量链上抽检：零损失 / 份额守恒 / TWAB 只读追溯。
- 真实 Aave 特有行为：惰性计息（warp 无效、poke 后收益才到账）。

不做：真实 keeper 进程、subgraph、Chainlink VRF、多 vault。

---

## 2. 公共前置

| 项 | 要求 |
|----|------|
| 工具链 | node ≥ 20、pnpm 10.33、foundry 1.5.1+（`anvil/forge/cast`） |
| 浏览器 | MetaMask（或任意 injected 钱包） |
| 端口 | 8545（anvil）、3000（Next dev）空闲 |
| 构建 | `pnpm install` 已执行 |
| 路径 C 额外 | `BASE_SEPOLIA_RPC_URL`（任意公开 Base Sepolia RPC，如 PublicNode / Alchemy；仅用于 fork 拉取状态，**不发交易到真实链**） |

anvil 预置账户（公开测试私钥，**严禁用于真实网络**。fork 模式下这些账户仍有 10000 ETH 用于 gas）：

| 角色 | 地址 | 私钥 |
|------|------|------|
| #0 部署者 / drawManager / 清算者 | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` |
| #1 普通用户（导入浏览器） | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d` |
| #2 可选第二用户 / poke 触发者 | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | `0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a` |

公共终端变量（路径 A/B/C 通用，RPC 均为 `http://127.0.0.1:8545`）：

```bash
export RPC=http://127.0.0.1:8545
export PK0=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export PK1=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
export PK2=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
export USER1=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
export USER2=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
export LIQ=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
```

从 `frontend/.env.local` 读取 7 个部署地址：

```bash
USDC=$(grep '^NEXT_PUBLIC_USDC=' frontend/.env.local | cut -d= -f2)
PRIZE=$(grep '^NEXT_PUBLIC_PRIZE_TOKEN=' frontend/.env.local | cut -d= -f2)
YIELD=$(grep '^NEXT_PUBLIC_YIELD_VAULT=' frontend/.env.local | cut -d= -f2)
TWAB=$(grep '^NEXT_PUBLIC_TWAB_CONTROLLER=' frontend/.env.local | cut -d= -f2)
POOL=$(grep '^NEXT_PUBLIC_PRIZE_POOL=' frontend/.env.local | cut -d= -f2)
VAULT=$(grep '^NEXT_PUBLIC_PRIZE_VAULT=' frontend/.env.local | cut -d= -f2)
PAIR=$(grep '^NEXT_PUBLIC_LIQUIDATION_PAIR=' frontend/.env.local | cut -d= -f2)
```

---

## 3. 路径 A：本地 mock 收益源（默认联调）

> 与 v1/v2 完全一致，此处仅给精简版，完整 TC 与边界用例见 [manual-e2e-v2.md §3](manual-e2e-v2.md#3-路径-a本地-mock-收益源默认联调)。

### 3.1 起链 + 部署

```bash
# 终端 1：起链（注入 Multicall3）
lsof -ti:8545 | xargs kill 2>/dev/null; sleep 1
pnpm chain

# 终端 2：默认 mock 路径部署，自动回填 frontend/.env.local
pnpm deploy:local
```

预期：输出 7 地址 + `YvType : mock`，`.env.local` 7 个变量非空。

### 3.2 存款 / 收益 / 清算 / 开奖 / 领奖

完整步骤见 v2 §3.2–§3.3。核心命令摘要：

```bash
# 存款
cast send $USDC "mint(address,uint256)" $USER1 1000000000 --rpc-url $RPC --private-key $PK1
# 前端 /vault 存入 1000

# 捐赠收益 → 清算 → 开奖 → 领奖
cast send $USDC "mint(address,uint256)" $YIELD 100000000 --rpc-url $RPC --private-key $PK0
cast send $PRIZE "mint(address,uint256)" $LIQ $(cast max-uint) --rpc-url $RPC --private-key $PK0
cast send $PRIZE "approve(address,uint256)" $PAIR $(cast max-uint) --rpc-url $RPC --private-key $PK0
AVAIL=$(cast call $VAULT "liquidatableBalanceOf()(uint256)" --rpc-url $RPC | awk '{print $1}')
cast send $PAIR "swapExactAmountOut(uint256,address)" $AVAIL $LIQ --rpc-url $RPC --private-key $PK0
cast rpc evm_increaseTime 86400 --rpc-url $RPC && cast rpc evm_mine --rpc-url $RPC
cast send $POOL "awardDraw(uint256)" 20261023 --rpc-url $RPC --private-key $PK0
```

---

## 4. 路径 B：本地 aave-adapter 收益源

> 验证自研 `AaveYieldVault` 适配器的资金流、seed 首充、`MockAToken.accrue` 计息。与 v2 §4 完全一致，此处略。完整步骤见 [manual-e2e-v2.md §4](manual-e2e-v2.md#4-路径-b本地-aave-adapter-收益源)。

---

## 5. 路径 C：Base Sepolia 本地 Fork（真实 StataToken）

> **v2.1 核心路径**。fork 真实 Base Sepolia 状态到本地，使用官方 USDC StataToken 作为收益源，验证 Aave 惰性计息：`evm_increaseTime` 不推进 `liquidityIndex`，必须有一笔状态变更交易（poke）后收益才体现在 `liquidatableBalanceOf()`。

### 5.1 Base Sepolia 官方地址（fork 状态来源）

来源：[bgd-labs/aave-address-book](https://github.com/bgd-labs/aave-address-book)（与 [deployment.md](../architecture/deployment.md) 一致）。

| 角色 | 地址 |
|------|------|
| USDC（测试币） | `0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f` |
| Aave Pool | `0x8bAB6d1b75f19e9eD9fCe8b9BD338844fF79aE27` |
| USDC StataToken（收益源） | `0xf430cb6E2b85f99222fBFA6dFEa18Ff60FA6B32a` |

### 5.2 起 fork 链（终端 1，常驻）

fork 拉取 Base Sepolia 状态到本地，**不覆盖链 ID**，保持 84532，从而完整走 `Deploy.s.sol` 的非本地安全分支。真实 StataToken / Aave / USDC 合约以其官方地址存在于 fork 状态中。

```bash
export BASE_SEPOLIA_RPC_URL=https://base-sepolia-rpc.publicnode.com

lsof -ti:8545 | xargs kill 2>/dev/null; sleep 1
# 方式一：复用 start-anvil.sh（自动处理 Multicall3 注入 + 进程清理；不传 --chain-id）
bash scripts/start-anvil.sh --fork-url "$BASE_SEPOLIA_RPC_URL"

# 方式二：直接 anvil（fork 自带 Multicall3，无需注入）
# anvil --fork-url "$BASE_SEPOLIA_RPC_URL"
```

验证 fork 成功（链 ID 保持 84532，且拉到了真实合约代码）：

```bash
cast chain-id --rpc-url $RPC           # 84532（保持原链 ID）
cast code 0xf430cb6E2b85f99222fBFA6dFEa18Ff60FA6B32a --rpc-url $RPC | head -c 20
# 预期：非 0x（StataToken runtime code 已 fork 到本地）
cast call 0xf430cb6E2b85f99222fBFA6dFEa18Ff60FA6B32a "totalSupply()(uint256)" --rpc-url $RPC
# 预期：> 0（真实 StataToken 已有存量供应，无通胀攻击窗口）
```

### 5.3 获取测试 USDC（无需水龙头）

fork 上 anvil 预置账户只有 ETH，没有真实 Base Sepolia USDC。用 `anvil_impersonateAccount` 冒充一个 USDC 大户转账即可。**首选 Aave Pool**（用户存入的 USDC 由 Pool 托管）：

```bash
export BASE_USDC=0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f
export AAVE_POOL=0x8bAB6d1b75f19e9eD9fCe8b9BD338844fF79aE27

# 1) 确认 Aave Pool 持有 USDC（应为正数）
cast call $BASE_USDC "balanceOf(address)(uint256)" $AAVE_POOL --rpc-url $RPC

# 2) 冒充 Pool，给部署者与用户各转 1000 USDC（6 位小数）
cast rpc anvil_impersonateAccount $AAVE_POOL --rpc-url $RPC

# 2a) 查 AAVE_POOL 的 ETH 余额（fork 上真实 Pool 合约通常为 0）
cast balance $AAVE_POOL --rpc-url $RPC
# 若为 0，则充 ETH 付 gas（--unlocked 只免签名不免 gas；不充会报 "Out of gas: allowance: 0"）
# 注意：anvil_setBalance 接收十六进制。1 ETH = 10^18 wei = 0xDE0B6B3A7640000，
#       勿用 0x1000000000000000000（那是 2^72 ≈ 4722 ETH）。
cast rpc anvil_setBalance $AAVE_POOL $(cast to-hex $(cast to-wei 1 ether)) --rpc-url $RPC
cast balance $AAVE_POOL --rpc-url $RPC   # 校验 = 1000000000000000000

cast send $BASE_USDC "transfer(address,uint256)" $LIQ   1000000000 --from $AAVE_POOL --unlocked --rpc-url $RPC
cast send $BASE_USDC "transfer(address,uint256)" $USER1 1000000000 --from $AAVE_POOL --unlocked --rpc-url $RPC
cast send $BASE_USDC "transfer(address,uint256)" $USER2  100000000 --from $AAVE_POOL --unlocked --rpc-url $RPC
cast rpc anvil_stopImpersonatingAccount $AAVE_POOL --rpc-url $RPC

# 3) 校验
cast call $BASE_USDC "balanceOf(address)(uint256)" $USER1 --rpc-url $RPC   # = 1000000000
```

> **若 Aave Pool USDC 不足**：换一个大户。可在 Base Sepolia 区块浏览器查 USDC top holders，或冒充任意 `balanceOf > 0` 的地址。`anvil_impersonateAccount` 对 EOA 与合约均有效。
>
> **极端回退**：用 `anvil_setStorageAt` 直接改写 USDC `balances` mapping。Circle FiatToken（代理）的 `balances` mapping 在实现合约 slot 0，计算方式：
> ```bash
> # slot = keccak256(abi.encode(owner, uint256(0)))
> SLOT=$(cast keccak $(cast abi-encode "address,uint256" $USER1 0))
> cast rpc anvil_setStorageAt $BASE_USDC $SLOT 0x000000000000000000000000000000000000000000000000000000003b9aca00 --rpc-url $RPC
> ```
> （`0x3b9aca00` = 1e9 = 1000 USDC；不同 FiatToken 实现版本 slot 可能不同，优先用 impersonation。）

### 5.4 部署（stata 主路径，走非本地分支）

因 fork 保持 `chainId = 84532`，`Deploy.s.sol` 的 `isLocal = false`，必须显式提供 `USDC_ADDRESS` 与收益源，否则脚本 revert（这正是要验证的非本地安全分支）。使用 `deploy-testnet.sh`，把 `BASE_SEPOLIA_RPC_URL` 指向**本地 fork**：

```bash
# 终端 2
export BASE_USDC=0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f

BASE_SEPOLIA_RPC_URL=http://127.0.0.1:8545 \
DEPLOYER_PRIVATE_KEY=$PK0 \
USDC_ADDRESS=$BASE_USDC \
YIELD_VAULT_ADDRESS=0xf430cb6E2b85f99222fBFA6dFEa18Ff60FA6B32a \
  pnpm deploy:testnet
# PRIZE_TOKEN_ADDRESS 留空 → 部署 MockERC20 奖币（奖币不在本金路径，测试网允许）
```

预期输出 `YvType : stata` 与 7 个地址。`deploy-testnet.sh` **自动回填** `frontend/.env.local`（设 `NEXT_PUBLIC_CHAIN_ID=84532`、`NEXT_PUBLIC_RPC_URL` 为部署所用 RPC、7 个合约地址；保留原有的 WalletConnect projectId），无需手动复制：

```bash
# 部署完成后 .env.local 已被脚本自动写入，直接重启前端即可。
# 如需手动校验：cat frontend/.env.local | grep NEXT_PUBLIC_
```

> 注意：stata 路径下 Deploy.s.sol 不部署 USDC / YieldVault（直接复用 fork 上的官方合约），部署者 nonce 序列与 mock 路径不同，**`DEPLOYMENTS[31337]` 的硬编码地址完全不适用**，必须以本次 `deploy-testnet.sh` 输出的地址为准。`getDeployment()` 对未在 `DEPLOYMENTS` 登记的链（如 84532）完全由 `NEXT_PUBLIC_*` env 解析地址，**无需往 `DEPLOYMENTS` 里加 84532 条目**。env 用静态字面量读取，浏览器端可被 Next.js 内联；改完 `.env.local` 后必须**重启 `pnpm frontend:dev`** 才生效。

#### 5.4.1 前端 RPC 指向本地 fork（必需）

wagmi `baseSepolia` 链默认使用公开 Base Sepolia RPC，不会读写本地 fork。需临时让 `baseSepolia` 链的 RPC 指向 localhost。编辑 [chains.ts](../../frontend/src/lib/config/chains.ts)：

```ts
import { baseSepolia, foundry } from "wagmi/chains";
import type { Chain } from "wagmi/chains";

// fork 联调临时覆盖：baseSepolia 指向本地 anvil fork
const baseSepoliaFork = {
  ...baseSepolia,
  rpcUrls: {
    default: { http: ["http://127.0.0.1:8545"] },
    public: { http: ["http://127.0.0.1:8545"] },
  },
} as const;

const DEFAULT_CHAIN_ID = Number(process.env.NEXT_PUBLIC_CHAIN_ID ?? "31337");

export const chains: [Chain, ...Chain[]] =
  DEFAULT_CHAIN_ID === 84532
    ? [baseSepoliaFork, foundry]
    : [foundry, baseSepolia];
```

> 验证完成后必须回滚此改动，避免污染默认 `baseSepolia` 配置（真实测试网部署仍用公开 RPC）。

#### 5.4.2 MetaMask 接入

添加自定义网络：chainId `84532`、RPC `http://127.0.0.1:8545`、货币符号 ETH；导入 anvil #1 私钥（`0x59c6995e...`）。因 fork 链 ID 与真实 Base Sepolia 相同，MetaMask 可能提示「此网络已存在」，直接编辑已有 Base Sepolia 网络的 RPC 为 localhost 即可，验证后改回。

### 5.5 存款与赎回（PrizeVault → StataToken → Aave Pool）

```bash
# 用户存款 1000 USDC（前端 /vault，或 cast）
cast send $USDC "approve(address,uint256)" $VAULT 1000000000 --rpc-url $RPC --private-key $PK1
cast send $VAULT "deposit(uint256,address)" 1000000000 $USER1 --rpc-url $RPC --private-key $PK1

# 验证：PrizeVault 份额 1:1，底层资产已进入 StataToken
cast call $VAULT "balanceOf(address)(uint256)" $USER1 --rpc-url $RPC     # = 1000e6
cast call $VAULT "totalAssets()(uint256)" --rpc-url $RPC                  # >= 1000e6
cast call $VAULT "totalSupply()(uint256)" --rpc-url $RPC                  # = 1000e6
```

事件链：USDC 从用户 → PrizeVault → StataToken（ERC-4626 deposit）→ Aave Pool（`pool.supply`），aToken 铸给 StataToken，StataToken 份额铸给 PrizeVault，pvUSDC 份额铸给用户。

赎回 500：

```bash
cast send $VAULT "redeem(uint256,address,address)" 500000000 $USER1 $USER1 --rpc-url $RPC --private-key $PK1
cast call $USDC "balanceOf(address)(uint256)" $USER1 --rpc-url $RPC     # 回到 500e6
```

### 5.6 惰性计息验证（路径 C 关键差异点）

Aave V3 利率模型为**惰性计息**：`liquidityIndex` 仅在储备发生状态变更交易（supply / withdraw / borrow / repay / liquidation）时推进。纯时间快进（`evm_increaseTime`）不产生任何状态变更，因此 `liquidatableBalanceOf()` 不变。

```bash
# 1) 记录快进前可清算余额（应为 0）
cast call $VAULT "liquidatableBalanceOf()(uint256)" --rpc-url $RPC

# 2) 快进 30 天
cast rpc evm_increaseTime 2592000 --rpc-url $RPC
cast rpc evm_mine --rpc-url $RPC

# 3) 再次读取 —— 仍为 0（惰性计息，warp 无效）
cast call $VAULT "liquidatableBalanceOf()(uint256)" --rpc-url $RPC
```

**poke**：触发任意 Aave USDC 储备的状态变更交易。最便捷的方式是让第二个用户向 PrizeVault 存一笔小额 USDC（路径 `PrizeVault.deposit → stata.deposit → pool.supply`，一笔交易同时推进 `liquidityIndex` 并刷新 StataToken 汇率）：

```bash
cast send $USDC "approve(address,uint256)" $VAULT 1000000 --rpc-url $RPC --private-key $PK2
cast send $VAULT "deposit(uint256,address)" 1000000 $USER2 --rpc-url $RPC --private-key $PK2

# poke 后收益到账
cast call $VAULT "liquidatableBalanceOf()(uint256)" --rpc-url $RPC   # > 0
cast call $VAULT "totalAssets()(uint256)" --rpc-url $RPC              # > totalSupply
```

> 也可直接对 StataToken 做小额存款（`cast send $YIELD "deposit(uint256,address)" 1000000 $LIQ ...`），效果相同。poke 的本质是触发 Aave Pool 的 `updateState`。

### 5.7 清算 / 开奖 / 领奖

后续与路径 A §3.3 完全一致（奖池金额以链上 `liquidatableBalanceOf()` 为准，受 Aave 真实利率影响）：

```bash
# 清算者买入收益（荷兰拍）
cast send $PRIZE "mint(address,uint256)" $LIQ $(cast max-uint) --rpc-url $RPC --private-key $PK0
cast send $PRIZE "approve(address,uint256)" $PAIR $(cast max-uint) --rpc-url $RPC --private-key $PK0
AVAIL=$(cast call $VAULT "liquidatableBalanceOf()(uint256)" --rpc-url $RPC | awk '{print $1}')
cast send $PAIR "swapExactAmountOut(uint256,address)" $AVAIL $LIQ --rpc-url $RPC --private-key $PK0

# 开奖（快进 1 天到 draw 边界；#0 为 drawManager）
cast rpc evm_increaseTime 86400 --rpc-url $RPC && cast rpc evm_mine --rpc-url $RPC
cast send $POOL "awardDraw(uint256)" 20261023 --rpc-url $RPC --private-key $PK0

# 领奖（单人 TWAB 占多数时三档可领）
cast call $POOL "getClaimableAmount(address,uint8,uint32)(uint256)" $USER1 0 1 --rpc-url $RPC
# 前端 /account 逐行领取，或 cast send $POOL "claimPrize(address,uint8,uint32)" $USER1 0 1 ...
```

### 5.8 清理

```bash
# 停掉 fork anvil（终端 1 Ctrl-C）
# 回滚 frontend/src/lib/config/chains.ts 中 baseSepoliaFork 的临时改动
# 恢复 MetaMask 中 Base Sepolia 网络的 RPC 为公开端点
# 重启普通 anvil 后重新走路径 A，恢复 SSOT 地址
```

---

## 6. 跨路径不变量抽检

三条路径均需满足（自动化证明以 Foundry 为准，此处为链上抽检）：

```bash
# 1. 零损失
cast call $VAULT "totalAssets()(uint256)" --rpc-url $RPC
cast call $VAULT "totalSupply()(uint256)" --rpc-url $RPC
# 预期：totalAssets >= totalSupply

# 2. 份额守恒
cast call $TWAB "totalSupply()(uint256)" --rpc-url $RPC
# 预期：与上面 PrizeVault.totalSupply() 逐字节相等

# 3. TWAB 只读追溯（开奖后再存取款，历史 draw 的可领金额不变）
cast call $POOL "getClaimableAmount(address,uint8,uint32)(uint256)" $USER1 1 1 --rpc-url $RPC
# ... 发生新的存取款 ...
cast call $POOL "getClaimableAmount(address,uint8,uint32)(uint256)" $USER1 1 1 --rpc-url $RPC
# 预期：两次返回值完全相同
```

路径 C 额外抽检：

```bash
# 4. StataToken 存量供应 > 0（无通胀攻击窗口）
cast call $YIELD "totalSupply()(uint256)" --rpc-url $RPC
# 预期：> 0

# 5. 惰性计息：warp 前后 liquidatableBalanceOf 不变，poke 后 > 0
# （见 §5.6）
```

---

## 7. 回归通过标准

- 所选路径的存款 / 赎回 / 清算 / 开奖 / 领奖全链路成功。
- 三条不变量抽检全部满足。
- 金额小数位正确：USDC / pvUSDC 为 6 位、PRIZE 为 18 位。
- **路径 C 必须验证惰性计息**：warp 后 `liquidatableBalanceOf = 0`、poke 后 `> 0`。
- 路径 C 必须确认 `totalAssets() >= totalSupply()` 在 poke 后仍成立（收益入账不破坏零损失）。

执行记录（手工回归时填写）：

| 字段 | 内容 |
|------|------|
| 执行人 / 日期 | |
| 路径 | A mock / B adapter / C fork-stata |
| fork 区块号（路径 C） | `cast block-number --rpc-url $RPC` |
| 代码版本（commit） | |
| foundry 版本 / 浏览器 | |
| 结果汇总 | VAULT __/4 · DRAW __/4 · INVARIANTS __/3 · LAZY __/2 |
| 失败用例与现象 | |

---

## 8. 常见问题

| 现象 | 原因 / 处理 |
|------|-------------|
| fork 起链后 `cast code <StataToken>` 返回 `0x` | fork 失败：`BASE_SEPOLIA_RPC_URL` 不可达或配额耗尽 → 检查 RPC、换 PublicNode 等公开端点 |
| `cast call $BASE_USDC "balanceOf(address)" $AAVE_POOL` 返回 0 | Aave Pool 当前无 USDC 存量 → 换一个 USDC 大户（区块浏览器查 top holders），或用 `anvil_setStorageAt` 回退（§5.3） |
| `anvil_impersonateAccount` 后 `transfer` 仍 revert | 若冒充的是合约，部分 ERC20 实现会校验 `msg.sender` 是否为合约本身——USDC（FiatToken）无此限制，应可直接转；若换其它代币失败，改用 `anvil_setStorageAt` |
| `cast send --from $AAVE_POOL --unlocked` 报 `Out of gas: gas required exceeds allowance: 0` | 被冒充的 `AAVE_POOL` 地址在 fork 上 ETH 余额为 0，`--unlocked` 只免签名不免 gas → 先 `cast rpc anvil_setBalance $AAVE_POOL $(cast to-hex $(cast to-wei 1 ether)) --rpc-url $RPC` 充 ETH（注意参数是十六进制，`0x1000000000000000000` ≈ 4722 ETH 非 1 ETH；见 §5.3 步骤 2a） |
| 路径 C 部署后 `YvType` 不是 `stata` | `USDC_ADDRESS` / `YIELD_VAULT_ADDRESS` 未透传到 `forge script` → 确认在运行 `pnpm deploy:testnet` 前已正确传参，或直接用 `forge script Deploy.s.sol` 显式传参 |
| 路径 C 前端显示「奖池未部署或地址未配置」 | 两个叠加原因：① `getDeployment(84532)` 因 `DEPLOYMENTS` 无 84532 条目直接抛错；② 旧代码用动态 `process.env[key]` 读 env，浏览器端无法内联。已修复（`packages/contracts/src/deployments.ts`：未知链由 env 解析 + 静态字面量读 env）。确认 `.env.local` 7 个 `NEXT_PUBLIC_*` 地址非空、`NEXT_PUBLIC_CHAIN_ID=84532`，然后**重启 `pnpm frontend:dev`**（env 在构建时内联，热更新不生效） |
| 路径 C `awardDraw` revert `PrizePoolDrawNotReady` | 时间未到：`nextDrawStart() = 部署时间戳 + 1 天 × 期数` → 先 `evm_increaseTime` 再 `evm_mine` |
| 路径 C warp 后 `liquidatableBalanceOf` 仍为 0 | **Aave 惰性计息**：`liquidityIndex` 仅在储备状态变更时推进 → 先 poke（任意 Aave supply/withdraw 交易）再读取 |
| 路径 C poke 后 `liquidatableBalanceOf` 增长极小 | Aave 真实利率年化约 4–6%，30 天 1000 USDC 本金收益约 3–5 USDC，属正常；若需更大奖池可增大本金或 warp 更久 |
| 路径 C 前端连不上 / 读写到真实测试网数据 | wagmi `baseSepolia` 默认 RPC 不是本地 → 检查 §5.4.1 的 `chains.ts` 临时覆盖是否生效，`NEXT_PUBLIC_CHAIN_ID` 是否为 84532 |
| 重启 anvil 后钱包交易 pending / nonce 报错 | 链重置但 MetaMask 保留旧状态 → 钱包「设置 → 高级 → 清除活动账户数据」 |
| 前端 BigInt/构建类报错 | Next 16 下禁用 BigInt 字面量（`0n`），须用 `BigInt(...)`；属代码问题，出现即回归失败 |
| 交易 revert 但无明确错误信息 / 需要定位 gas 消耗 | 用 `cast tx <hash>` 看原始交易（from/to/value/data/gasLimit），`cast receipt <hash>` 看执行结果（`status`、`gasUsed`、`logs`、合约地址等）。bare revert（如除零、溢出）`cast receipt` 不会显示 reason，需用 `cast call --from <from> <to> <sig> <args>` 重放模拟以获取 revert data。gas 异常高说明在深层调用才失败（如 StataToken → Aave `supply` 内部）；gas 极低说明前置校验就失败（如授权不足）。结合 `cast run <hash>` 可重放整笔交易并打印每一步 opcode/trace，定位具体 revert 指令 |
