# keeper 模块架构

清算与开奖机器人（Node + TypeScript + viem）。**当前为 no-op 脚手架**：[src/index.ts](src/index.ts) 只有空 `main()`，业务逻辑未实现。本篇描述规划职责与落地约束，系统级交互时序见 [../docs/architecture/module-contracts.md](../docs/architecture/module-contracts.md) 第 3 节。

## 规划职责（两个循环动作）

1. **收益清算（无许可）**：轮询 `PrizeVault.liquidatableBalanceOf()`；有可清算收益时，按 `LiquidationPair.computeExactAmountIn(amountOut)` 出价，确保本机器人持有奖币并已 `approve` pair，调 `swapExactAmountOut(amountOut, keeper)`——奖币注入 PrizePool，yield 转给机器人作为激励。
2. **到期开奖（无许可）**：轮询 `PrizePool.nextDrawStart()`；到点后调 `RngRelay.requestDraw()` 触发 Chainlink VRF，VRF 回调中 RngRelay 自动执行 `awardDraw`。随机数完全来自 VRF，keeper 不生成也不注入。

合约地址不硬编码：统一从 `@prize-savings/contracts` 的 `getDeployment(chainId)` 取（接入该 workspace 依赖是落地第一步）。

## 落地约束

- 私钥只从 `.env` 读（`PRIVATE_KEY`、`RPC_URL`，见 [.env.example](.env.example)），禁止入仓、禁止打日志。
- 开奖无许可：`drawManager` 是 RngRelay（部署时设定），任何地址（含 keeper）都可调 `requestDraw()` 触发开奖，无需 `setDrawManager` 授权。
- 清算与开奖必须幂等可重试：链上权限/余额校验已覆盖重复调用，机器人侧需对交易 revert、nonce 冲突、RPC 抖动做重试与退避。
- keeper 离线只影响开奖时效，**不影响用户资金与赎回**，不需要紧急熔断设计。

## 命令

```bash
pnpm keeper:dev      # tsx watch src/index.ts
pnpm keeper:build    # tsc 类型检查/产物
```
