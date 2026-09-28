# Prize Savings 项目规则

> 去中心化储蓄抽奖应用（No-Loss Lottery），仿 PoolTogether V5。核心在合约正确性与公平性。

## 1. 项目定位

- 用户本金永不损失，存款产生的收益汇聚成奖金池，按时间加权平均余额（TWAB）随机抽奖发放。
- 完整闭环：存款 → 赚取收益 → 清算注入奖池 → 每日开奖 → 派奖 → 随时赎回本金。
- 权威文档 `docs/prd/prize-savings-lottery-design.md`（冻结的产品/协议设计）。

## 2. 仓库结构与包管理

- **pnpm workspace monorepo**，`packageManager: pnpm@10.33.0`，`node >= 20`（`.nvmrc` = 22）。
- workspace 成员：`frontend`、`subgraph`、`keeper`、`packages/*`。**`contracts/` 明确排除在 workspace 之外**（Foundry 工程无 node 构建需求），通过根 `package.json` scripts + `forge --root contracts` 转发调用。
- 包作用域统一为 `@prize-savings/*`。

| 模块 | 类型 | 技术栈 |
|------|------|--------|
| `contracts/` | Foundry 合约（非 workspace） | Solidity 0.8.24、OpenZeppelin v5、forge-std、Chainlink |
| `frontend/` | Next.js 前端 | Next.js 16（App Router）、React 19、TS、Tailwind v4、wagmi v2 + viem v2 + RainbowKit v2 + @tanstack/react-query v5 |
| `subgraph/` | The Graph 索引 | graph-cli、graph-ts、AssemblyScript |
| `keeper/` | 清算/开奖机器人 | Node + TS、viem、dotenv、tsx |
| `packages/contracts` | 共享 SDK `@prize-savings/contracts` | TS，re-export ABI/地址/viem 封装 |

## 3. 常用命令（在仓库根执行）

```bash
pnpm chain                          # 启动 anvil 本地链
pnpm contracts:build                # forge build --root contracts
pnpm contracts:test                 # forge test --root contracts
pnpm frontend:dev / frontend:build
pnpm keeper:dev / keeper:build
pnpm subgraph:codegen / subgraph:build
```

合约侧可用 `forge build/test/fmt --root contracts`；格式化检查 `forge fmt --root contracts --check`。

## 4. 编码规范

- 缩进：JS/TS/JSON/MD 用 **2 空格**；`.sol` / `.rs` 用 **4 空格**（见 `.editorconfig`）。LF 换行、UTF-8、文件末尾换行、去行尾空白。
- Solidity 格式化（`foundry.toml [fmt]`）：行宽 120、tab 4、双引号、`bracket_spacing=true`；编译 `optimizer=true / runs=200 / evm_version=cancun`。
- TypeScript 开启 `strict`；前端路径别名 `@/* → src/*`。
- **Next.js 16 有破坏性变更，与既有训练数据不同**：写前端代码前先读 `frontend/node_modules/next/dist/docs/`（monorepo 中 `next` 包在子目录）。遵循 `frontend/AGENTS.md` 的提示，注意弃用通知。

## 5. 架构约束与不变量（改动核心合约必须遵守）

三条全局不变量（对应 PRD 7.3，需在 Foundry 测试中验证）：

1. **零损失**：任意时点 `PrizeVault.totalAssets() >= totalSupply()`（yield buffer 兜底吸收舍入误差）。
2. **份额守恒**：`TwabController.totalSupply() == PrizeVault.totalSupply()`。
3. **TWAB 只读追溯**：`awardDraw` 后任何存取款不得改变历史 draw 的中奖结果（claimable 金额由 `drawStart~drawEnd` 的固定 TWAB 计算）。

其他关键约束：

- **中奖概率严格正比 TWAB**，TWAB 是「时间加权平均余额」，用于防闪电存款套利。

## 6. 文档规范

遵循 `docs/架构文档组织方式.md`：

- **就近原则**：模块内部细节进模块自己的 `ARCHITECTURE.md`（`<module>/ARCHITECTURE.md`）；仅跨模块/系统级内容进 `docs/`。
- **单一事实源（SSOT）**：ABI、合约地址、TS 类型、subgraph schema 由代码/生成器产出，文档只指向、不复制粘贴，防漂移。
- **写「为什么」不写「是什么」**：只保留决策依据、权衡、不变量、模块契约；代码自明的不写文档。
- 图表一律用 **Mermaid** 内联，不存二进制图。
- 不可逆/代价高的决策写 **ADR**（`docs/decisions/ADR-NNNN-*.md`），序号只增不改；旧 ADR 用「已废弃」标记而非修改。
- 改动任何跨模块接口（ABI、事件、schema）需**同 PR 内**同步 `docs/architecture/module-contracts.md`，否则视为不完整提交。
- 不主动新建 README/*.md 文档；仅在用户明确要求时创建。

## 7. 环境变量与密钥安全

- `.env*` 不入库（`.gitignore` 已排除），模板用 `.env.example` 承载空值占位。
- **私钥/密钥严禁写入代码或提交**：keeper 的 `PRIVATE_KEY`、RPC URL 等仅存在于本地 `.env`。
- 前端环境变量（以 `NEXT_PUBLIC_` 开头）：`NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID`、`NEXT_PUBLIC_CHAIN_ID`、`NEXT_PUBLIC_RPC_URL`。
- keeper 环境变量：`RPC_URL`、`PRIVATE_KEY`。

## 8. 安全准则（Web3 金融合约）

- 这是处理用户资金的无损储蓄合约，任何核心合约（TWAB/PrizeVault/PrizePool/清算）改动必须谨慎，并同步补充不变量/单测/集成测试。
- 权限最小化：保留 owner 角色但不得拥有冻结/挪用用户资金的权限；资金始终由合约与用户控制。
- 涉及资产转移的函数均需 `test/` 覆盖（含 `Invariants.t.sol` fuzz 与 `Integration.t.sol` 端到端闭环）。
- 合约改动优先复现/修复失败场景，避免引入新的信任假设或中心化控制点。