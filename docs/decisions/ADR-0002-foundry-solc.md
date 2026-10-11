# ADR-0002：合约工具链采用 Foundry + Solidity 0.8.24

- 状态：**已接受**
- 日期：2026-09（脚手架期决策，事后补记）

## 背景

核心壁垒在合约正确性（PRD 1.3）。工具链需要：原生 fuzz/invariant 测试、快速反馈循环、与主流 DeFi 依赖（OpenZeppelin）顺畅集成，且团队仿写对象 PoolTogether V5 的 `pt-v5-*` 系列即 Foundry + Solidity，可大量参考其模式。

## 决策

- 合约工具链：**Foundry**（forge / cast / anvil），不用 Hardhat。
- 编译器：**Solididity 0.8.24**（[foundry.toml](../../contracts/foundry.toml)），`optimizer=true / runs=200 / evm_version=cancun`。
- 依赖：OpenZeppelin Contracts v5、forge-std；保留 Chainlink remapping 但 M0 合约不实际引用。
- 本地链：anvil（chainId 31337）作为唯一 M0 目标环境。

## 后果

- 正：fuzz 测试（[Invariants.t.sol](../../contracts/test/Invariants.t.sol)）与快速 warp/prank 让零损失、TWAB 时间加权等性质可直接表达；`vm.warp` 让每日开奖闭环测试秒级跑完。
- 正：与 PoolTogether 参考实现、OZ v5（含 ERC-4626 官方实现）同构，减少自研面。
- 负：0.8.24 的 checked arithmetic 与自定义错误成为代码风格基线，贡献者需适应（无 SafeMath、revert 用 error）。
- 负：Chainlink remapping 空置可能让人误以为已接入 VRF——文档与 [ADR-0003](./ADR-0003-keeper-injected-rng-over-pfda.md) 已明确其 M0 不启用。

## 备选方案（被否）

1. **Hardhat + ethers**：生态成熟但 fuzz/不变量测试需外接 Echidna/Foundry 插件，双工具链并存更复杂。
2. **更旧的 0.8.19/0.8.20**：与 OZ v5 新版及 cancun EVM 目标的兼容性需要额外验证，无收益。
3. **更早启用 Chainlink 依赖**：M0 开奖走信任化注入（ADR-0003），引入真实 VRF 订阅只会增加部署前置条件。
