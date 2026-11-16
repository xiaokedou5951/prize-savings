# ADR-0005：M0 收益源采用 Aave StataToken 优先、自研适配器兜底

- 状态：**已接受**
- 日期：2026-10（M0 集成期）

## 背景

PRD M0 集成阶段要求把 `MockERC4626` 替换为真实收益源，目标网络为 Base。筛选标准：本金安全优先（无损储蓄协议的收益源即本金存放地）、目标生态可及性、以及对 ERC-4626 的原生支持（PrizeVault 的 `_deposit` / `_pullAssets` 均按 ERC-4626 语义消费 yieldVault，不为特殊收益源增加分支）。

Base 上的主流动息选项中，Aave v3 有 bgd-labs 维护的官方 StataToken（ERC-4626 包装 aToken 的静态汇率金库），USDC 市场已有部署。StataToken 让 PrizeVault 以标准 ERC-4626 语义直接对接 Aave 利息，资金路径上不需要任何自研合约。

## 决策

- **主路径**：`YIELD_VAULT_ADDRESS` 直接指向 Aave 官方 StataToken（USDC 市场）。资金路径零自研合约，新增信任面仅 Aave 本身。
- **回退路径**：目标市场没有 stata 时，用自研 `AaveYieldVault` 适配器（部署时设 `AAVE_POOL` + `AAVE_ATOKEN` 触发），把 Aave pool/aToken 适配为 ERC-4626。仅作回退，不默认使用。
- **通胀攻击双防护**（适配器专属）：`_deposit` 在 `shares == 0` 时 revert（1 wei 攻击存款直接被拒）；部署脚本在同一 broadcast 内做 seed 首充（默认 1_000 USDC，份额发死地址 `0xdEaD`）锚定汇率。前者挡极端捐赠攻击，后者吸收常规首充滑点，两者均有测试（`AaveYieldVault.t.sol`）。
- **已知接受的风险**：适配器 `maxRedeem` 不查询 Aave 底层流动性，池枯竭时 redeem revert 交由上层处理（PrizeVault `_pullAssets` 有 loose 余额兜底，用户可重试）；Aave 惰性计息（liquidityIndex 仅在储备状态变更交易时推进）意味着收益是离散跳变而非连续流，断言收益前需先「poke」。

## 后果

- 正：主路径资金面无新代码可审计，安全审查集中在外部协议既有声誉；fork 测试（[ForkStataYield.t.sol](../../contracts/test/ForkStataYield.t.sol)）直接对主网真实合约验证存赎与收益可清算性。
- 正：适配器复用 OZ ERC4626 的舍入与份额语义，行为与 mock/stata 一致，PrizeVault 无感知差异。
- 负：适配器把 aToken 1:1 视作本金（`totalAssets` 即 aToken 余额），未来接 exchangeRate ≠ 1 的生息代币（如 Compound cToken）必须改写，适配器不通用。
- 负：收益源形态的选择发生在部署期（环境变量三档回退，见 [deployment.md](../architecture/deployment.md)），同一套合约可能对应不同收益源，排查问题需先确认部署配置（输出 `YvType` 标签即为此目的）。
- 成本：Aave 惰性计息要求 keeper / 测试在断言收益前先触发任意储备状态变更交易（poke），收益到账节奏与连续计息直觉不同。

## 备选方案（被否）

1. **自研适配器为主路径**：资金路径引入自研合约，违背「本金安全优先」的最小信任原则；官方 stata 已存在时无额外收益。
2. **PoolTogether V5 的 yield vault（prize-liquidator 竞争清算模型）**：引入清算者竞争与缓冲记账，M0 无需此复杂度；其对 ERC-4626 的扩展语义与 OZ 基类有多处偏差，移植与审计成本高。
3. **直接持有 aToken 而非 ERC-4626 包装**：PrizeVault 需要为非 4626 收益源增加专用存取分支，破坏「任意标准 ERC-4626 可插拔」的结构约束。
4. **继续用 MockERC4626 至 M1**：M0 集成的目标就是验证真实收益源闭环，推迟会让开奖/清算参数首次暴露在真实利率曲线下的时机后移。
