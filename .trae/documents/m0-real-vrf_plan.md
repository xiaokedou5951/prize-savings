# M0 接入真实 VRF 实施计划

## Repository Research

### 现状

- `PrizePool.awardDraw(uint256 winningRandomNumber)` 由白名单 `drawManager`（keeper）链外注入随机数，合约只校验开奖时间与非零（[PrizePool.sol:110-130](file:///Users/mac/work/2026/web3/prize-savings/contracts/src/PrizePool/PrizePool.sol#L110-L130)）。
- [ADR-0003](file:///Users/mac/work/2026/web3/prize-savings/docs/decisions/ADR-0003-keeper-injected-rng-over-pfda.md) 明确这是 M0 临时信任假设，演进条件第 1 条即「接入 Chainlink VRF，拆成请求随机数 / 用回调结果 awardDraw 两笔交易」，并预留 `awardDraw(uint256)` 入参为最终 VRF 输出——**升级时无需改 PrizePool 的抽奖与领取逻辑**。
- Chainlink 合约已在 `lib/chainlink/`，remapping `@chainlink/contracts/` 已配好（[remappings.txt](file:///Users/mac/work/2026/web3/prize-savings/contracts/remappings.txt)），含 `VRFConsumerBaseV2Plus`（VRF v2.5，推荐版本）、`VRFCoordinatorV2_5Mock`（测试用）、`IVRFCoordinatorV2Plus`、`VRFV2PlusClient`。
- keeper 是 no-op 脚手架，规划中 M1 拆 VRF 两段式（[keeper/ARCHITECTURE.md](file:///Users/mac/work/2026/web3/prize-savings/keeper/ARCHITECTURE.md)）。
- 部署目标链为 Base Sepolia（84532）和本地 anvil（31337）。Base 上 VRF v2.5 支持 **native ETH 支付**（无需 LINK）。

### 关键设计决策：独立 RngRelay 合约而非 PrizePool 直接继承 VRF

采用 **Option B：独立 RngRelay 合约** 作为 VRF consumer，理由：

1. **PrizePool 零改动**：`awardDraw(uint256)` 接口与抽奖/领取逻辑完全不变，符合 ADR-0003 的接口预留约定，现有 `PrizePool.t.sol` 无需修改。
2. **职责分离**：PrizePool = 抽奖逻辑；RngRelay = 随机性获取。对齐 PoolTogether 的 RNG relay 架构。
3. **随机数来源可验证**：只有 VRF coordinator 能调用 `rawFulfillRandomWords`，owner 无法注入自定义随机数——仅能改 VRF 参数、无法作弊。
4. **`drawManager` 机制复用**：把 `PrizePool.drawManager` 设为 RngRelay 地址即可，`awardDraw` 的 `onlyDrawManager` 守卫天然把开奖权收敛到「经 VRF 验证的随机数」。
5. **测试隔离**：PrizePool 测试不依赖 VRF mock，RngRelay 单独用 `VRFCoordinatorV2_5Mock` 测试。

### RngRelay 合约设计

```
任何人(permissionless) → RngRelay.requestDraw()   [检查时间+无在途请求] → VRF requestRandomWords
VRF coordinator → RngRelay.rawFulfillRandomWords() [onlyCoordinator]
                → RngRelay.fulfillRandomWords() [internal]
                → try PrizePool.awardDraw(randomWords[0]) returns (drawId)
                  → emit DrawFulfilled(requestId, drawId, randomNumber)
                  catch → emit DrawFailed(requestId, randomNumber)
```

- 继承 `VRFConsumerBaseV2Plus(address vrfCoordinator)`（其自身继承 `ConfirmedOwner`，自带 `onlyOwner`）。
- 不可变配置（构造器注入）：`prizePool`、`vrfCoordinator`；可配置（owner setter）：`keyHash`、`subId`、`requestConfirmations`、`callbackGasLimit`。
- `requestDraw() external returns (uint256 requestId)` **permissionless**（任何人到点可触发，keeper 只是监控者之一，去中心化设计）：检查 `pendingRequestId == 0`（防并发）、`block.timestamp >= prizePool.nextDrawStart()`（防浪费 VRF 费），调用 `s_vrfCoordinator.requestRandomWords(...)`，记录 `pendingRequestId`。
- `fulfillRandomWords(requestId, randomWords) internal override`：校验 `pendingRequestId != 0` → **先清零 `pendingRequestId`** → `try prizePool.awardDraw(randomWords[0]) returns (uint32 drawId)` 成功则 `emit DrawFulfilled(requestId, drawId, randomWords[0])`；失败则 `emit DrawFailed(requestId, randomWords[0])`。**用 try/catch 确保 pendingRequestId 总能清零，避免 awardDraw revert 导致永久卡死。**
- `nativePayment: true` 硬编码（Base 用 ETH 付 VRF 费，无需 LINK）。M0 仅支持 Base 等支持 native VRF 支付的链。
- 安全阀：`resetPendingRequest() onlyOwner`——VRF 回调失败（订阅余额耗尽等）时手动清零在途标记，**不允许 owner 注入随机数**。

## Files and Modules

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| `contracts/src/RngRelay/RngRelay.sol` | **新建** | VRF v2.5 consumer，请求随机数并在回调中调用 `PrizePool.awardDraw` |
| `contracts/src/interfaces/IRngRelay.sol` | **新建** | RngRelay 接口（`requestDraw`、getter、事件） |
| `contracts/src/interfaces/IPrizePool.sol` | **修改** | 新增 `nextDrawStart() external view returns (uint32)`，供 RngRelay 时间预校验 |
| `contracts/test/RngRelay.t.sol` | **新建** | 用 `VRFCoordinatorV2_5Mock` 测：请求→mock 回调→开奖；在途防重入；时间未到 revert；非 coordinator 注入 revert；awardDraw revert 时 try/catch 清零；安全阀 |
| `contracts/script/Deploy.s.sol` | 修改 | 新增 VRF 配置 env；本地部署 mock coordinator + 创建订阅 + 加 consumer + 注资；部署 RngRelay；`setDrawManager(rngRelay)`；打印 RngRelay 地址 |
| `contracts/test/Integration.t.sol` | 修改 | 用 RngRelay + VRF mock 走完「请求→回调→开奖」闭环，替代直接 `awardDraw` |
| `scripts/gen-abis.mjs` | 修改 | 新增 RngRelay ABI 生成目标 |
| `packages/contracts/src/abis/RngRelay.ts` | 新建（生成） | `rngRelayAbi` |
| `packages/contracts/src/index.ts` | 修改 | 导出 `rngRelayAbi` |
| `packages/contracts/src/deployments.ts` | 修改 | `Deployment` 接口加 `rngRelay` 字段；`DEPLOYMENTS[31337]` **全部 8 个地址重新回填**（nonce 序列变化导致旧地址失效）；`envDeployment` 加 `NEXT_PUBLIC_RNG_RELAY` |
| `scripts/deploy-local.sh` | **修改** | 提取 RngRelay 地址、写入 `NEXT_PUBLIC_RNG_RELAY`、加入缺失检查与打印列表 |
| `scripts/deploy-testnet.sh` | **修改** | 同上 |
| `frontend/.env.example` | **修改** | 新增 `NEXT_PUBLIC_RNG_RELAY=` 占位行（deploy-local.sh 的 sed 替换依赖此行存在） |
| `keeper/ARCHITECTURE.md` | 修改 | 更新开奖流程为 `requestDraw` → 等 VRF 回调 |
| `docs/architecture/module-contracts.md` | 修改 | 新增 RngRelay 事件→subgraph 映射；更新 keeper↔合约交互时序 |
| `docs/architecture/deployment.md` | 修改 | 新增 VRF 环境变量清单、Base Sepolia VRF coordinator 地址参考、订阅创建/注资步骤 |
| `docs/decisions/ADR-0003-keeper-injected-rng-over-pfda.md` | 修改 | 状态改为「已被 VRF 方案取代」，指向 RngRelay 实现 |
| `docs/testing/manual-e2e.md` / `manual-e2e-v2.md` / `manual-e2e-v2.1.md` | **修改** | 开奖步骤从 `cast send $POOL awardDraw` 改为 `RngRelay.requestDraw()` + mock `fulfillRandomWords`；异常路径与排错表同步更新 |

## Implementation Steps

1. **修改 `IPrizePool.sol`**：新增 `function nextDrawStart() external view returns (uint32);`（RngRelay 通过接口做时间预校验，避免导入具体合约）。

2. **新建 `RngRelay.sol` + `IRngRelay.sol`**
   - 继承 `VRFConsumerBaseV2Plus`；构造器接收 `(vrfCoordinator, prizePool, keyHash, subId, requestConfirmations, callbackGasLimit)`。
   - `requestDraw() external returns (uint256 requestId)` permissionless：在途检查 + 时间检查（`prizePool.nextDrawStart()`）+ `requestRandomWords`（1 个 word，nativePayment=true）。
   - `fulfillRandomWords(uint256, uint256[] calldata) internal override`：清零在途 → `try prizePool.awardDraw(randomWords[0]) returns (uint32 drawId)` → 成功 emit `DrawFulfilled(requestId, drawId, randomWords[0])`；失败 emit `DrawFailed(requestId, randomWords[0])`。
   - owner setters：`setKeyHash` / `setSubId` / `setRequestConfirmations` / `setCallbackGasLimit`；`setCoordinator` 由基类 `VRFConsumerBaseV2Plus` 提供（`onlyOwnerOrCoordinator`）。
   - 安全阀 `resetPendingRequest() onlyOwner`。
   - 事件：`DrawRequested(uint256 indexed requestId)`、`DrawFulfilled(uint256 indexed requestId, uint32 indexed drawId, uint256 randomNumber)`、`DrawFailed(uint256 indexed requestId, uint256 randomNumber)`。

3. **新建 `RngRelay.t.sol`**
   - 部署 `VRFCoordinatorV2_5Mock(0, 1e9, 1e18)`（构造器已调 `setConfig()`，`minimumRequestConfirmations=0`），`createSubscription()` → `fundSubscriptionWithNative{value: 10 ether}(subId)` → `addConsumer(subId, rngRelay)`。
   - 场景：时间到 → `requestDraw()` 得 requestId → `mock.fulfillRandomWords(requestId, rngRelay)` → 校验 `PrizePool._drawId == 1` 且 `DrawFulfilled` 事件含正确 drawId。
   - 在途：连续两次 `requestDraw` 第二次 revert。
   - 时间未到：`requestDraw` revert。
   - 非 coordinator 调 `rawFulfillRandomWords` revert（`OnlyCoordinatorCanFulfill`）。
   - **awardDraw revert 场景**：mock 下用 `fulfillRandomWordsWithOverride` 或构造条件让 awardDraw 失败，校验 `pendingRequestId` 被清零且 emit `DrawFailed`。
   - 安全阀：`resetPendingRequest` 后可再次请求。

4. **修改 `Deploy.s.sol`**
   - 新增 env：`VRF_COORDINATOR`、`VRF_KEY_HASH`、`VRF_SUB_ID`、`VRF_REQUEST_CONFIRMATIONS`（默认 3）、`VRF_CALLBACK_GAS_LIMIT`（默认 500_000）。
   - **部署序列（nonce 重排）**：USDC → PRIZE → YieldVault → Twab → PrizePool → **VRFCoordinatorV2_5Mock（仅 31337）** → **RngRelay** → PrizeVault → LiquidationPair → 组装授权 + `setDrawManager(rngRelay)`。
   - 本地（31337）：部署 mock → `createSubscription` → `fundSubscriptionWithNative` → 部署 RngRelay（subId=1）→ `addConsumer` → `setDrawManager(rngRelay)`。
   - 非本地：要求 `VRF_COORDINATOR`、`VRF_KEY_HASH`、`VRF_SUB_ID` 显式配置，否则 revert（VRF 是开奖信任根，不允许 mock 降级）。
   - 打印 RngRelay 地址（console.log 标签 `RngRelay`）。

5. **修改 `Integration.t.sol`**
   - setUp 中增加 RngRelay + VRF mock 部署与订阅组装；`setDrawManager(rngRelay)`。
   - `test_full_closed_loop` 中把 `vm.prank(KEEPER); pool.awardDraw(...)` 改为：`rngRelay.requestDraw()` → `mock.fulfillRandomWords(requestId, rngRelay)`。

6. **ABI 与 SDK**
   - `gen-abis.mjs` 加 `RngRelay.sol/RngRelay.json` → `RngRelay.ts` → `rngRelayAbi`。
   - `index.ts` 导出新 ABI。
   - `deployments.ts` 加 `rngRelay` 字段与 `NEXT_PUBLIC_RNG_RELAY` env 覆盖；**`DEPLOYMENTS[31337]` 全部 8 个地址重新计算回填**。

7. **部署脚本与前端 env**
   - `deploy-local.sh` / `deploy-testnet.sh`：增加 `RngRelay` 地址提取、`NEXT_PUBLIC_RNG_RELAY` 写入、缺失检查、打印。
   - `frontend/.env.example`：新增 `NEXT_PUBLIC_RNG_RELAY=` 行。

8. **文档同步**
   - `module-contracts.md`：RngRelay 事件（`DrawRequested`/`DrawFulfilled`/`DrawFailed`）→ subgraph 映射；keeper 时序改为 `requestDraw`。
   - `deployment.md`：VRF 环境变量表、Base Sepolia VRF v2.5 coordinator 参考地址 `0x5D292299385dDa5728b528490209481c887F517d`（部署前核对 Chainlink 官方文档）、订阅创建与注资 runbook。
   - ADR-0003：标记已被取代。
   - 三份 `manual-e2e*.md`：开奖步骤改为经 RngRelay，异常路径与排错表同步。

## Dependencies and Considerations

- **VRF v2.5 native payment**：Base Sepolia 支持 `nativePayment: true`，用 ETH 支付 VRF 费用，无需 LINK。M0 硬编码 native 支付，仅支持 Base 等支持 native VRF 的链；若未来需 LINK 支付需加 setter 切换（M0 不做）。
- **callbackGasLimit 取值**：`awardDraw` 内部做 TWAB 查询 + 3 档奖金计算。**SimpleTwabController 下 gas < 150k，默认 500k 足够**；若使用 `ObservationTwabController`，`getAverageTotalSupplyBetween` 遍历观察窗口，周期内存取款频繁时 gas 可能超 500k，需实测并由 owner 调高 `callbackGasLimit`。
- **VRF 回调失败处理与恢复路径**：若订阅 ETH 余额不足，`fulfillRandomWords` 不会被调用，`pendingRequestId` 卡在非零。恢复步骤：① 注资订阅 ② owner 调 `resetPendingRequest` 清零 ③ 重新 `requestDraw`。失败那期 draw **不会被跳过**（`_drawId` 未递增），重新请求会补开。`fulfillRandomWords` 内部用 try/catch 确保即使 `awardDraw` revert 也能清零 `pendingRequestId` 并 emit `DrawFailed`。
- **并发请求防护**：`pendingRequestId` 机制保证同一时刻只有一个 VRF 请求在途，避免多期 draw 乱序。
- **PrizePool 不变**：`awardDraw` 的 `onlyDrawManager` + 时间校验不变；RngRelay 作为 drawManager 是唯一开奖入口，随机数只能来自 VRF 回调。
- **owner 信任边界**：`VRFConsumerBaseV2Plus.setCoordinator` 为 `onlyOwnerOrCoordinator`，owner 理论上可把 coordinator 换成恶意合约注入任意随机数。这是标准 VRF consumer 的固有信任假设，owner 为部署者/DAO，同 NFR-1 权限最小化讨论范畴；RngRelay 的 owner 不拥有资金权限，作恶上限是影响某期谁中奖（同原 drawManager 风险模型）。
- **requestDraw permissionless**：任何人到点可触发开奖请求，不设白名单，keeper 只是监控者之一。`pendingRequestId` + 时间检查天然限流（每期最多一次请求）。

## Validation

- `forge build --root contracts` 编译通过（含 RngRelay 及 chainlink 依赖）。
- `forge test --root contracts` 全部通过：
  - `RngRelay.t.sol`：6 个场景（正常请求回调、在途防重入、时间未到、非 coordinator 注入、awardDraw revert 时 try/catch 清零、安全阀）。
  - `PrizePool.t.sol`：不变，全部通过（验证 PrizePool 零改动）。
  - `Integration.t.sol`：闭环测试改为经 RngRelay+VRF mock 开奖，零损失不变量仍成立。
  - `Invariants.t.sol`：不变量测试不变（不调用 awardDraw）。
- `forge fmt --root contracts --check` 格式通过。
- `pnpm contracts:abis` 生成 `RngRelay.ts`，`pnpm contracts:build`（TS）类型检查通过。
- `pnpm frontend:build` 通过（deployments.ts 新增字段不破坏现有类型）。
- 本地 anvil 冒烟：`pnpm deploy:local` 后，`cast call` 验证 `RngRelay.prizePool()` 正确、`PrizePool.drawManager() == RngRelay`；手工 `cast send RngRelay requestDraw` → `cast send VRFMock fulfillRandomWords` → 校验 `PrizePool` 开奖。

## Risks

- **VRF 订阅余额耗尽导致开奖停摆**：缓解 = keeper 监控订阅余额 + `resetPendingRequest` 安全阀；不影响用户资金与赎回（同 ADR-0003 风险模型）。
- **callbackGasLimit 不足导致 fulfillRandomWords out-of-gas**：缓解 = 默认 500k 远超 SimpleTwabController 需求；owner 可调；ObservationTwabController 模式需实测调高。
- **owner 篡改 coordinator 注入恶意随机数**：缓解 = owner 为部署者/DAO 信任边界，作恶上限仅影响某期中奖者（同原 drawManager 模型）；RngRelay 无资金权限。
- **Base Sepolia VRF coordinator/keyHash 地址错误**：缓解 = 部署时由 env 显式传入，部署后可通过 `setCoordinator`/`setKeyHash` 修正，无需重新部署 RngRelay。
- **测试 mock 行为与真实 coordinator 差异**：mock 的 `fulfillRandomWords` 不验证证明，但 RngRelay 只依赖 `rawFulfillRandomWords` 的 `onlyCoordinator` 守卫与 `fulfillRandomWords` 回调签名，与真实 coordinator 行为一致。
- **DEPLOYMENTS[31337] 地址全量变更**：新增 VRF mock + RngRelay 打乱 nonce 序列，7 个旧地址全部失效，需重新计算回填 8 个地址；deploy-local.sh 自动写入 `.env.local` 可覆盖前端，`DEPLOYMENTS` 回填需人工同步。
- **改动跨模块接口（新增 RngRelay ABI + IPrizePool 加方法）**：按 project rules 同 PR 内同步 `module-contracts.md` 与 ABI 生成物，避免漂移。
