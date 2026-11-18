# 手工端到端联调手册 v2（M0 集成真实收益源后）

> 回答的问题：**在「本地 mock / 本地 Aave 适配器 / Base Sepolia StataToken」三种收益源部署下，把「存款 → 收益 → 清算入池 → 开奖 → 派奖 → 赎回」整条链路手工走通，每一步该点什么、该看到什么。**
>
> v1（`manual-e2e.md`）仅覆盖本地 mock 路径；本 v2 在此基础上新增真实收益源路径与双链支持。合约不变量的自动化证明在 `contracts/test/`，本手册只做**跨模块手工回归**。部署细节 SSOT 是 [../architecture/deployment.md](../architecture/deployment.md)，收益源取舍见 [ADR-0005](../decisions/ADR-0005-yield-source-stata-first.md)。

---

## 1. 范围与路径矩阵

M0 集成后收益源由部署期环境变量三档回退决定（[Deploy.s.sol](../../contracts/script/Deploy.s.sol)）：

| 路径 | 适用网络 | 触发条件 | YvType | 收益模拟方式 |
|------|----------|----------|--------|--------------|
| A · 本地 mock | anvil 31337（默认） | 无收益源配置 | `mock` | 直接向 `MockERC4626` 捐赠 USDC |
| B · 本地适配器 | anvil 31337 | `AAVE_POOL` + `AAVE_ATOKEN` | `aave-adapter` | `MockAToken.accrue(adapter, amount)` |
| C · StataToken | Base Sepolia 84532 | `YIELD_VAULT_ADDRESS` = 官方 StataToken | `stata` | Aave 真实利率，**惰性计息**，需 poke |

> 三条路径的 PrizeVault / PrizePool / LiquidationPair 逻辑完全相同，差异仅在收益源如何产生 `liquidatableBalanceOf()`。路径 A 是日常联调默认；路径 B 验证适配器资金流与 seed；路径 C 验证真实 Aave 的惰性计息行为。

覆盖：

- 双链启动、部署、地址回填、钱包接入。
- 前端写路径：存款（approve + deposit）、赎回（withdraw）、领奖（claimPrize）。
- `cast` 模拟 keeper：注入收益、清算、快进时间、开奖。
- 三条全局不变量链上抽检：零损失 / 份额守恒 / TWAB 只读追溯。
- 真实 Aave 特有行为：惰性计息（warp 无效、poke 后收益才到账）。

不做：真实 keeper 进程、subgraph、多 vault。

---

## 2. 公共前置

| 项 | 要求 |
|----|------|
| 工具链 | node ≥ 20、pnpm 10.33、foundry 1.5.1+（`anvil/forge/cast`） |
| 浏览器 | MetaMask（或任意 injected 钱包） |
| 端口 | 8545（anvil）、3000（Next dev）空闲 |
| 构建 | `pnpm install` 已执行 |

anvil 预置账户（公开测试私钥，**严禁用于真实网络**）：

| 角色 | 地址 | 私钥 |
|------|------|------|
| #0 部署者 / drawManager / 清算者 | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` |
| #1 普通用户（导入浏览器） | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d` |
| #2 可选第二用户 | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | `0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a` |

公共终端变量（三条路径通用，路径 A/B 用 anvil RPC，路径 C 用测试网 RPC）：

```bash
export RPC=<对应链的 RPC>
export PK0=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export PK1=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
export USER1=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
export LIQ=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
```

从 `frontend/.env.local` 读取 9 个部署地址：

```bash
USDC=$(grep '^NEXT_PUBLIC_USDC=' frontend/.env.local | cut -d= -f2)
PRIZE=$(grep '^NEXT_PUBLIC_PRIZE_TOKEN=' frontend/.env.local | cut -d= -f2)
YIELD=$(grep '^NEXT_PUBLIC_YIELD_VAULT=' frontend/.env.local | cut -d= -f2)
TWAB=$(grep '^NEXT_PUBLIC_TWAB_CONTROLLER=' frontend/.env.local | cut -d= -f2)
POOL=$(grep '^NEXT_PUBLIC_PRIZE_POOL=' frontend/.env.local | cut -d= -f2)
RNG_RELAY=$(grep '^NEXT_PUBLIC_RNG_RELAY=' frontend/.env.local | cut -d= -f2)
VRF=$(grep '^NEXT_PUBLIC_VRF_COORDINATOR=' frontend/.env.local | cut -d= -f2)
VAULT=$(grep '^NEXT_PUBLIC_PRIZE_VAULT=' frontend/.env.local | cut -d= -f2)
PAIR=$(grep '^NEXT_PUBLIC_LIQUIDATION_PAIR=' frontend/.env.local | cut -d= -f2)
```

---

## 3. 路径 A：本地 mock 收益源（默认联调）

> 与 v1 手册的核心流程一致；此处给出精简版，完整 TC 编号与边界用例见 [manual-e2e.md](manual-e2e.md)。

### 3.1 起链 + 部署

```bash
# 终端 1：起链（注入 Multicall3）
lsof -ti:8545 | xargs kill 2>/dev/null; sleep 1
pnpm chain

# 终端 2：默认 mock 路径部署，自动回填 frontend/.env.local
pnpm deploy:local
```

预期：输出 9 地址 + `YvType : mock`，`.env.local` 9 个变量非空。

### 3.2 存款与赎回

1. 给用户铸 1000 USDC：`cast send $USDC "mint(address,uint256)" $USER1 1000000000 --rpc-url $RPC --private-key $PK1`
2. 浏览器导入 #1，连钱包，进 `/vault` 存 1000 → 份额 1000、USDC 余额 0。
3. 部分赎回 100 → 份额 900、USDC 余额 100。
4. MAX 赎回 → 份额 0、USDC 余额 1000（本金 1:1 无损）。

### 3.3 收益 → 清算 → 开奖 → 领奖

MockERC4626 通过直接接收底层资产捐赠抬升份额单价：

```bash
# 重新存入 1000 USDC 后：
# 1) 捐赠 100 USDC 到收益金库模拟计息
cast send $USDC "mint(address,uint256)" $YIELD 100000000 --rpc-url $RPC --private-key $PK0
cast call $VAULT "liquidatableBalanceOf()(uint256)" --rpc-url $RPC   # ≈ 100e6

# 2) 清算者买入收益（荷兰拍）
cast send $PRIZE "mint(address,uint256)" $LIQ 1000000000000000000000 --rpc-url $RPC --private-key $PK0
cast send $PRIZE "approve(address,uint256)" $PAIR $(cast max-uint) --rpc-url $RPC --private-key $PK0
AVAIL=$(cast call $VAULT "liquidatableBalanceOf()(uint256)" --rpc-url $RPC | awk '{print $1}')
cast send $PAIR "swapExactAmountOut(uint256,address)" $AVAIL $LIQ --rpc-url $RPC --private-key $PK0

# 3) 到点开奖（通过 RngRelay 请求 VRF；本地 mock 手动 fulfill）
cast rpc evm_increaseTime 86400 --rpc-url $RPC
cast rpc evm_mine --rpc-url $RPC
cast send $RNG_RELAY "requestDraw()" --rpc-url $RPC --private-key $PK0
REQ_ID=$(cast call $RNG_RELAY "pendingRequestId()(uint256)" --rpc-url $RPC)
cast send $VRF "fulfillRandomWords(uint256,address)" $REQ_ID $RNG_RELAY --rpc-url $RPC --private-key $PK0

# 4) 领奖（单人 100% TWAB，三档全中：约 60/25/15 PRIZE）
cast call $POOL "getClaimableAmount(address,uint8,uint32)(uint256)" $USER1 0 1 --rpc-url $RPC
cast call $POOL "getClaimableAmount(address,uint8,uint32)(uint256)" $USER1 1 1 --rpc-url $RPC
cast call $POOL "getClaimableAmount(address,uint8,uint32)(uint256)" $USER1 2 1 --rpc-url $RPC
# 前端 /account 逐行领取，或 cast send $POOL "claimPrize(address,uint8,uint32)" $USER1 0 1 ...
```

预期：奖池 PRIZE 约 100、清算者得约 100 USDC、可清算归零、draw 1 开奖成功、三档可领合计 ≈ 100 PRIZE。

---

## 4. 路径 B：本地 aave-adapter 收益源

> 验证自研 `AaveYieldVault` 适配器的资金流、seed 首充、以及通过 `MockAToken.accrue` 模拟计息后的清算。需先用 mock Aave 组件搭建本地 Aave 环境。

### 4.1 部署 mock Aave 环境

创建临时脚本 `contracts/script/DeployMockAave.s.sol`（验证后删除）：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { Script, console } from "forge-std/Script.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MockAavePool } from "../src/mocks/MockAavePool.sol";

contract DeployMockAave is Script {
    uint256 internal constant MINT_AMOUNT = 1_000_000e6;
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(pk);
        vm.startBroadcast(pk);
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        usdc.mint(deployer, MINT_AMOUNT);
        MockAavePool pool = new MockAavePool(usdc);
        vm.stopBroadcast();
        console.log("MockUSDC   :", address(usdc));
        console.log("MockPool   :", address(pool));
        console.log("MockAToken :", address(pool.aToken()));
    }
}
```

部署并提取地址：

```bash
RPC=http://127.0.0.1:8545
DEPLOYER_PRIVATE_KEY=$PK0 forge script contracts/script/DeployMockAave.s.sol \
  --root contracts --rpc-url $RPC --broadcast
# 从输出日志读取 MockUSDC / MockPool / MockAToken 地址
```

记为 `MOCK_USDC`、`MOCK_POOL`、`MOCK_ATOKEN`。

### 4.2 以 adapter 路径部署 Prize Savings

```bash
DEPLOYER_PRIVATE_KEY=$PK0 \
USDC_ADDRESS=$MOCK_USDC \
AAVE_POOL=$MOCK_POOL \
AAVE_ATOKEN=$MOCK_ATOKEN \
  forge script contracts/script/Deploy.s.sol --root contracts --rpc-url $RPC --broadcast
```

预期输出：`YvType : aave-adapter`，YieldVault 即适配器地址（记为 `ADAPTER`）。

### 4.3 验证 seed 首充（防通胀攻击）

```bash
ADAPTER=<YieldVault 地址>
echo "DEAD 份额:"; cast call $ADAPTER "balanceOf(address)(uint256)" 0x000000000000000000000000000000000000dEaD --rpc-url $RPC
echo "totalAssets:"; cast call $ADAPTER "totalAssets()(uint256)" --rpc-url $RPC
echo "totalSupply:"; cast call $ADAPTER "totalSupply()(uint256)" --rpc-url $RPC
```

预期：三者均为 `1000000000`（1000e6，默认 seed），份额锁定在死地址 `0xdEaD`。

### 4.4 存款与赎回（经 PrizeVault → adapter → Aave pool）

把 9 地址手动填入 `frontend/.env.local`（或复用 §2 的 grep 读取，注意此时 `NEXT_PUBLIC_USDC` 应为 `$MOCK_USDC`）。给用户铸 USDC 并存款：

```bash
cast send $USDC "mint(address,uint256)" $USER1 1000000000 --rpc-url $RPC --private-key $PK1
# 前端 /vault 存入 1000，或：
cast send $USDC "approve(address,uint256)" $VAULT 1000000000 --rpc-url $RPC --private-key $PK1
cast send $VAULT "deposit(uint256,address)" 1000000000 $USER1 --rpc-url $RPC --private-key $PK1
```

事件链（可用 `cast receipt` 核对）：USDC 从用户 → PrizeVault → adapter → Aave pool，aToken 铸给 adapter，adapter 份额铸给 PrizeVault，pvUSDC 份额铸给用户。

```bash
cast call $VAULT "balanceOf(address)(uint256)" $USER1 --rpc-url $RPC   # = 1000e6
cast call $ADAPTER "totalAssets()(uint256)" --rpc-url $RPC              # = 1000e6 seed + 1000e6 存款
```

赎回 500：

```bash
cast send $VAULT "redeem(uint256,address,address)" 500000000 $USER1 $USER1 --rpc-url $RPC --private-key $PK1
cast call $USDC "balanceOf(address)(uint256)" $USER1 --rpc-url $RPC     # 回到 500e6
```

### 4.5 模拟计息（MockAToken.accrue）

mock 环境下 Aave 利息由 `MockAToken.accrue` 手动触发（真实 Aave 由流动性利率曲线自动累积）：

```bash
# 给 adapter 抬升 100 USDC 的 aToken 余额，模拟计息
cast send $MOCK_ATOKEN "accrue(address,uint256)" $ADAPTER 100000000 --rpc-url $RPC --private-key $PK0
cast call $VAULT "liquidatableBalanceOf()(uint256)" --rpc-url $RPC      # ≈ 100e6
```

后续清算 / 开奖 / 领奖步骤与路径 A §3.3 完全一致（奖池约 100 PRIZE、单人三档全中）。

### 4.6 清理

```bash
rm contracts/script/DeployMockAave.s.sol
# 重启 anvil 后重新走路径 A，恢复 SSOT 地址
```

---

## 5. 路径 C：Base Sepolia StataToken 收益源

> 验证真实 Aave 的惰性计息：`evm_increaseTime` 不推进 Aave `liquidityIndex`，必须有一笔状态变更交易（poke）后收益才体现在 `liquidatableBalanceOf()`。

### 5.1 部署（stata 主路径）

```bash
BASE_SEPOLIA_RPC_URL=<你的测试网 RPC> \
DEPLOYER_PRIVATE_KEY=<部署账户私钥（需 ETH + 测试 USDC）> \
USDC_ADDRESS=0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f \
YIELD_VAULT_ADDRESS=0xf430cb6E2b85f99222fBFA6dFEa18Ff60FA6B32a \
  pnpm deploy:testnet
```

预期输出 `YvType : stata`。`deploy-testnet.sh` 自动把 9 地址 + `NEXT_PUBLIC_CHAIN_ID=84532` 写入 `frontend/.env.local`（无需手动复制，也无需改 `DEPLOYMENTS[84532]`）。

### 5.2 惰性计息验证（关键差异点）

存入 1000 USDC 后，先记录可清算余额，再快进时间：

```bash
cast call $VAULT "liquidatableBalanceOf()(uint256)" --rpc-url $RPC   # = 0（无收益）
# 真实测试网用区块时间流逝；本地 fork 测试用：
# cast rpc evm_increaseTime 2592000 --rpc-url $RPC   # 30 天
# cast rpc evm_mine --rpc-url $RPC
```

快进后再次读取：

```bash
cast call $VAULT "liquidatableBalanceOf()(uint256)" --rpc-url $RPC   # 仍 = 0（惰性计息，warp 无效）
```

**poke**：触发任意 Aave 储备状态变更（例如任意账户向 StataToken 存 1 USDC），推进 `liquidityIndex` 并刷新 stata 汇率：

```bash
# 用部署者向 stata 小额存款（也可用任意持有 USDC 的账户）
cast send $USDC "approve(address,uint256)" $YIELD 1000000 --rpc-url $RPC --private-key $PK0
cast send $YIELD "deposit(uint256,address)" 1000000 $LIQ --rpc-url $RPC --private-key $PK0
cast call $VAULT "liquidatableBalanceOf()(uint256)" --rpc-url $RPC   # > 0，收益到账
```

### 5.3 清算 / 开奖 / 领奖

后续与路径 A §3.3 相同。注意：

- 真实测试网不能用 `evm_increaseTime`，需等待实际周期（M0 `DAILY = 1 day`）或通过 keeper 调度。
- StataToken 的收益量级受 Aave 真实利率影响，奖池金额以链上 `liquidatableBalanceOf()` 为准。

### 5.4 部署后必做

1. 确认 `frontend/.env.local` 已被 `deploy-testnet.sh` 自动填入 9 地址 + `NEXT_PUBLIC_CHAIN_ID=84532`。
2. `NEXT_PUBLIC_CHAIN_ID=84532 pnpm frontend:build` 验证（或重启 `pnpm frontend:dev`）。
3. 小额 `deposit` → `redeem` roundtrip 冒烟，确认 `PrizeVault.totalAssets() >= totalSupply()`。
4. 开奖入口已为 RngRelay（部署时 `setDrawManager(rngRelay)`），无需再 `setDrawManager`；keeper 到点调 `RngRelay.requestDraw()` 即可。
5. （生产可选）把 9 地址补入 `DEPLOYMENTS[84532]` 并提交作为 SSOT；env 仍可覆盖。

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

---

## 7. 回归通过标准

- 所选路径的存款 / 赎回 / 清算 / 开奖 / 领奖全链路成功。
- 三条不变量抽检全部满足。
- 金额小数位正确：USDC / pvUSDC 为 6 位、PRIZE 为 18 位。
- 路径 C 必须验证惰性计息（warp 后 liquidatable=0、poke 后 >0）。

执行记录（手工回归时填写）：

| 字段 | 内容 |
|------|------|
| 执行人 / 日期 | |
| 路径 | A mock / B adapter / C stata |
| 代码版本（commit） | |
| foundry 版本 / 浏览器 | |
| 结果汇总 | VAULT __/4 · DRAW __/4 · INVARIANTS __/3 |
| 失败用例与现象 | |

---

## 8. 常见问题

| 现象 | 原因 / 处理 |
|------|-------------|
| 页面整体读不到合约（「奖池未部署或地址未配置」、转圈） | `.env.local` 为空或 dev server 在回填前已启动 → 重跑部署并**重启** `pnpm frontend:dev`；确认起链走 `pnpm chain`（注入 Multicall3）而非裸 `anvil` |
| 重启 anvil 后钱包交易 pending / nonce 报错 | 链重置但 MetaMask 保留旧状态 → 钱包「设置 → 高级 → 清除活动账户数据」 |
| 路径 B 部署后 `YvType` 不是 `aave-adapter` | 环境变量未传入或拼写错误：`USDC_ADDRESS` / `AAVE_POOL` / `AAVE_ATOKEN` 缺一不可；`deploy-local.sh` 不透传这些变量，必须直接调 `forge script Deploy.s.sol` |
| 路径 B adapter 部署 revert `DeploySeedInsufficient` | 部署者 USDC 余额不足 seed（默认 1000e6）→ 先 `mint` 足够 USDC 给部署者，或设 `AAVE_ADAPTER_SEED=0` 跳过（会打印通胀攻击警告） |
| 路径 C warp 后 `liquidatableBalanceOf` 仍为 0 | **Aave 惰性计息**：`liquidityIndex` 仅在储备状态变更时推进 → 先 poke（任意 Aave 存款/取款交易）再读取 |
| `requestDraw` revert `RngRelayDrawNotReady` | 时间未到：`nextDrawStart() = 部署时间戳 + 1 天 × 期数`，先 `evm_increaseTime` 再 `evm_mine` |
| `awardDraw` revert `PrizePoolOnlyDrawManager` | 直调 PrizePool 被拒；开奖入口是 RngRelay（drawManager），须走 `requestDraw()` |
| 前端 BigInt/构建类报错 | Next 16 下禁用 BigInt 字面量（`0n`），须用 `BigInt(...)`；属代码问题，出现即回归失败 |
