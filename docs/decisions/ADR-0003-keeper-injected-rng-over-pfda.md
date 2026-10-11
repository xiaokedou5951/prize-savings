# ADR-0003：M0 由白名单 drawManager 注入随机数，不做 PFDA / VRF

- 状态：**已接受**（M0 临时信任假设；M1 前必须替换为可验证随机源）
- 日期：2026-09（合约 MVP 期决策，事后补记）

## 背景

PoolTogether V5 的去中心化开奖由两套拍卖组成（Start RNG / Finish RNG，PFDA 定价）+ Chainlink VRF/Witnet 随机源，是协议中最复杂的子系统（RNG relay auction、储备金定价、拍卖时钟）。PRD 原计划 M0 接 Chainlink VRF + Automation 半自动开奖。进入合约实现后评估：M0 的首要目标是验证「存款→收益→清算→开奖→领取→赎回」闭环与三条不变量，拍卖与 VRF 订阅都是与该目标正交的基础设施。

## 决策

`PrizePool.awardDraw(uint256 winningRandomNumber)` 的调用权收敛为单一白名单角色 **drawManager**（初始为部署者，可 `setDrawManager` 交接给 keeper）；随机数由链外注入，合约只校验：

- 开奖时间已到（`block.timestamp >= nextDrawStart`）；
- 随机数非 0（为 0 则归一化为 1）。

不部署任何 Chainlink 合约、不实现 RNG relay auction、不实现 PFDA；清算端也只保留无许可的 `LiquidationPair` 线性降价 swap，清算激励是价差而非拍卖报酬。

## 后果

- 正：合约面砍掉整个拍卖/RNG 子系统，闭环得以用 ~190 行的 PrizePool 完成并有端到端测试。
- 正：drawManager 权限被限制为「只能决定何时开奖、提供一个种子」，**不能增发奖金、不能挪用资金、不能改历史 draw**；作恶上限是影响某期谁中奖。
- 负：引入中心化信任假设，与 NFR-3（去中心化）冲突，不能用于主网持币场景。
- 负：keeper 成为单点，其离线会导致开奖停摆（不影响资金与赎回）。
- 负： keeper 注入"可预测"随机数理论上可被其用于选择性开奖（择时）；缓解是开奖时间与 TWAB 窗口固定，且 drawManager 无法预知自己不喜欢的结果之外无收益——但根本缓解仍需 VRF。

## 演进条件（M1）

1. 接入 Chainlink VRF（或 Witnet）：拆成「请求随机数」与「用回调结果 awardDraw」两笔交易，随机数变为合约可验证输入。
2. 视激励需要再上 PFDA/自动化 keeper 网络，替换白名单 drawManager。
3. 接口预留：`awardDraw(uint256)` 的入参即最终 VRF 输出，升级时无需改 PrizePool 的抽奖与领取逻辑。

## 备选方案（被否）

1. **M0 直接实现 PFDA + VRF**：复杂度超过其余合约总和，闭环验证会被基础设施阻塞。
2. **区块哈希/prevrandao 作随机源**：无需 keeper 但可被区块提议者显著影响，且无法在到点后的同一笔结算交易中取到不可预测值，公平性弱于显式 VRF 路线，不构成可上线的中间态。
3. **多签 drawManager**：可降低单点风险但不消除信任源，M0 本地开发环境无必要，M1 直接以 VRF 取代。
