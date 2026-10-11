# ADR-0004：M0 单资产 USDC + 单一奖币

- 状态：**已接受**
- 日期：2026-09（脚手架期决策，事后补记）

## 背景

PoolTogether V5 是多资产共享大奖池的 Hyperstructure：任意 ERC-4626 vault 无许可接入，收益统一拍卖成一种奖币。多资产模型会带来跨资产定价、多 vault 贡献归集、清算路由、精度差异（6/8/18 decimals）等一组横切问题。M0 目标是窄而深地验证闭环。

## 决策

- 只部署**一个** PrizeVault：底层资产 USDC（6 decimals，M0 为 `MockERC20`），份额 `pvUSDC` 1:1。
- 只存在**一种**奖币（18 decimals，M0 为 `MockERC20` PRIZE）；一个 `LiquidationPair` 连接 vault 与唯一 `PrizePool`。
- 不实现 VaultFactory、Claimer、多 vault 贡献归集；合约目录保留 `VaultFactory/`、`Claimer/`、`RngRelayAuction/` 空目录作为演进占位。

## 后果

- 正：所有金额推导无需跨精度换算（仅清算定价一处涉及 USDC/奖币两种 decimals，由各自 ERC20 元数据承担）；奖池总额、单份奖金等前端展示直接可读。
- 正：不变量测试只需在单一 vault/单一收益源上建立，零损失证明不被组合复杂度稀释。
- 负：奖池规模依赖单一收益源的收益量，M0 用 `MockERC4626.mockHarvest` 捐赠模拟计息，无真实利率风险/收益曲线要处理。
- 负：扩展到多资产时，`PrizePool.drawAmount = 奖币余额 − reserve` 的记账天然只支持单奖币；多资产共享奖池需要新增贡献路由层，属 M2 范围。

## 备选方案（被否）

1. **M0 即多资产共享奖池**：需要先解决贡献归集与清算路由，推迟闭环验证；与 PRD「先窄而深」策略相悖。
2. **以 WETH 为奖币**：USDC 储蓄用户对美元计价奖金的理解最直接，且 6/18 decimals 组合恰好能在 Mock 阶段覆盖精度测试。
3. **奖币即 USDC（无独立奖币）**：清算机制需要一种与本金分离的资产承载"拍卖出价"，否则清算者无出资媒介；独立奖币保留了未来替换为治理代币的空间。
