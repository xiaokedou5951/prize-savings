# P0-3 建立 CI 流水线 Implementation Plan

## Repository Research

**现状（调研结论）：**

- 仓库根**无 `.github/`**，CI 从零开始（`contracts/lib/*` 下匹配到的 workflow 属于被 gitignore 的依赖目录，非本仓）。
- `contracts/lib/` 被 `contracts/.gitignore` 第 8 行忽略且**未入库**——`git clone` 干净检出后 `contracts/lib/` 不存在，`forge build/test` 会因缺 `forge-std`/`openzeppelin`/`chainlink` 失败。**CI 必须先安装 forge 依赖。**
- 依赖来源（`contracts/remappings.txt` + scaffold 计划 + 本地 `package.json` 核对）：
  - `foundry-rs/forge-std@v1.9.6`（本地 `package.json` 确认 1.9.6）
  - `OpenZeppelin/openzeppelin-contracts@v5.0.0`（本地确认 5.0.0；remapping 另含 `@openzeppelin/contracts@4.9.6` 供 chainlink 兼容）
  - `smartcontractkit/chainlink`（VRF v2.5 `src/v0.8/vrf/dev/*` 接口；本地拷贝无 `.git`/无版本标记，需钉 tag 并本地验证）
- **关键坑**：`forge install --root contracts <pkg>` 在本 monorepo 布局下报错 `Library directory is not relative to the repository root`（forge 把 monorepo git 根与 contracts project 根混淆）。改为**在 `contracts/` 目录内执行** `forge install` 即正常（已在 `/tmp` 干净克隆中验证：路径解析正确，仅沙箱网络失败）。
- `forge test` 中 `ForkStataYield` 无 `BASE_RPC_URL` 时自动 skip → **CI 无需密钥**（预期 1 skipped）。`[invariant] runs=256 depth=15` 已在 `foundry.toml`，CI 直接生效。
- ABI 生成：`pnpm contracts:abis` = `forge build && node scripts/gen-abis.mjs`，产物落到 `packages/contracts/src/abis/*.ts`（**已跟踪**，`Erc20.ts` 手写不被覆盖）。无 diff 校验 = 生成后 `git diff --exit-code packages/contracts/src/abis`。
- 前端 `next build` **不需要 env**：`wagmi.ts` 的 projectId 有占位兜底、`chains.ts` 默认 31337（已读源码确认）。
- keeper 构建 = `tsc`，无需 env。
- Node 22（`.nvmrc`）、pnpm 10.33.0（`packageManager`）；`pnpm-lock.yaml` 已跟踪 → 可用 `--frozen-lockfile`。
- pnpm workspace 成员：frontend / subgraph / keeper / packages/*。**subgraph 是空脚手架**（`dataSources: []`），`graph build` 会失败，P0-3 验收范围**不含** subgraph:build。

**验收标准（project-status §7 P0-3）：**
> `.github/workflows/ci.yml`：`forge build/test`、ABI 生成物无 diff 校验、`frontend:build`、`keeper:build`、`forge fmt --check`；PR 必须全绿

## Files and Modules

- **新增** `.github/workflows/ci.yml` — CI 主 workflow（3 个并行 job）。
- **新增** `contracts/install-deps.sh` — forge 依赖安装脚本（钉住版本，本地与 CI 共用，SSOT；不被 `.gitignore` 忽略，会被跟踪）。
- **修改** `docs/project-status.md` — CI 验证通过后：缺口 G5 标为已修复、§7 P0-3 标 ✅、§2.2 硬证据表加一行 CI。

## Implementation Steps

### 步骤 1：创建 `contracts/install-deps.sh` 并本地验证（关口步骤）

脚本内容（在 `contracts/` 内执行，`set -euo pipefail`）：

```bash
#!/usr/bin/env bash
# 安装 contracts 的 forge 依赖（钉住版本，本地与 CI 共用）。
# 必须在 contracts/ 目录内执行：forge install 在 monorepo 布局下用 --root 会报
# "Library directory is not relative to the repository root"。
set -euo pipefail
cd "$(dirname "$0")"

forge install foundry-rs/forge-std@v1.9.6 --no-git
forge install OpenZeppelin/openzeppelin-contracts@v5.0.0 --no-git
forge install smartcontractkit/chainlink@v2.20.0 --no-git   # 候选 tag，需本地验证
```

本地验证（决定 chainlink 最终 pin）：
```bash
cd contracts
bash install-deps.sh          # 需要网络
forge build --root .
forge test --root .           # 预期 58 passed / 1 skipped
```
- 若 `chainlink@v2.20.0` 编译/测试失败，依次回退/前进到最近可编译的 v2.x tag（VRF v2.5 dev 路径自 v2.0 起稳定存在），把最终可用 tag 写回脚本。这是本计划唯一的不确定项，验证通过后再继续。
- `chmod +x contracts/install-deps.sh`。

### 步骤 2：创建 `.github/workflows/ci.yml`

触发：`push` 到 `main` + `pull_request`。runs-on `ubuntu-latest`。3 个并行 job：

**job `contracts`**（Foundry 工具链 + 依赖缓存）：
1. `actions/checkout@v4`
2. `foundry-rs/foundry-toolchain@v1`（装 forge/cast）
3. 缓存 `contracts/lib`：`actions/cache@v4`，key = `hashFiles('contracts/install-deps.sh')`，命中则跳过安装。
4. `bash contracts/install-deps.sh`（仅缓存未命中时）
5. `forge fmt --root contracts --check`
6. `forge build --root contracts`
7. `forge test --root contracts`
8. ABI 无 diff 校验：
   ```bash
   forge build --root contracts
   node scripts/gen-abis.mjs
   git diff --exit-code -- packages/contracts/src/abis
   ```
   （`gen-abis.mjs` 仅用 node 内置模块，runner 自带 node 即可；不依赖 pnpm。）

**job `frontend`**：
1. `actions/checkout@v4`
2. `actions/setup-node@v4`（node 22）+ `pnpm/action-setup@v4`（version 10.33.0，或 corepack）
3. `pnpm install --frozen-lockfile`（配 `pnpm store` 缓存）
4. `pnpm frontend:build`

**job `keeper`**：
1. checkout + setup-node 22 + pnpm
2. `pnpm install --frozen-lockfile`
3. `pnpm keeper:build`

> frontend 与 keeper 可各自独立 install（简单健壮），或拆出 setup job + artifact；P0-3 用独立 job 即可。

### 步骤 3：本地复验各命令（无网络依赖的部分）

在工作区实跑确认：
- `forge fmt --root contracts --check` → 0 diff（P0-1 已格式化过）
- `pnpm install --frozen-lockfile` 成功（lockfile 当前）
- `pnpm frontend:build` 成功（无 env）
- `pnpm keeper:build` 成功
- ABI 无 diff：`pnpm contracts:abis && git diff --exit-code packages/contracts/src/abis` 干净
- YAML 语法：`python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))"` 不报错

### 步骤 4：推送 PR，观察 GitHub Actions 全绿

- 本仓工作流无法在本地完全复刻 Actions runner，以 GitHub 上实际执行为准。
- 若 `contracts` job 在 `install-deps.sh` 失败（网络/tag），按步骤 1 调整 tag 后重推。
- 「PR 必须全绿」的**分支保护规则**是 GitHub 仓库设置（Settings → Branches），不在 workflow 文件内；需在仓库后台开启 `Require status checks to pass` 并选中 3 个 job。计划在交付说明里标注，不写入文件。

### 步骤 5：同步文档 `docs/project-status.md`

CI 验证通过后：
- §2.2 硬证据表加一行：`CI` | `.github/workflows/ci.yml`（push/PR）| ✅ contracts(fmt+build+test+ABI diff) / frontend:build / keeper:build 全绿
- 缺口表 G5：`无 CI` → `✅ 已修复（P0-3）`，说明 3 job 覆盖范围与「分支保护需在仓库后台开启」的备注
- §7 P0-3 行标 `✅ 已完成`
- §2.1 模块总览 `CI` 行：`⬜ 无 0%` → `✅ 已建立 ~100%`

## Dependencies and Considerations

- `forge install` 必须在 `contracts/` 内执行（不能用 `--root`）——已通过 `/tmp` 干净克隆验证调用方式正确。
- chainlink monorepo 体积大，CI 用 `actions/cache` 缓存 `contracts/lib`（key 钉在 install-deps.sh 哈希）避免每次重克隆。
- 不需要任何密钥：fork 测试自动 skip，前端 build 有 env 兜底。
- `--frozen-lockfile` 依赖 lockfile 与 package.json 同步；当前已同步，若未来依赖变更需先在本地更新 lockfile 并提交。
- 不纳入 subgraph:build（空脚手架，会失败）——与 P0-3 验收范围一致，留待 P2-3。
- `contracts/install-deps.sh` 是新增的依赖 SSOT，顺带修复了「干净克隆无法编译 contracts」的既有可复现性缺口。

## Validation

- `forge fmt --root contracts --check` → 退出码 0
- `forge build --root contracts` → 成功
- `forge test --root contracts` → `58 passed / 0 failed / 1 skipped`
- `forge build --root contracts && node scripts/gen-abis.mjs && git diff --exit-code packages/contracts/src/abis` → 退出码 0
- `pnpm frontend:build` → 成功
- `pnpm keeper:build` → 成功
- `.github/workflows/ci.yml` YAML 解析通过
- GitHub 上 PR/push 触发后 3 个 job 全绿

## Risks

- **chainlink tag 编译不兼容**：本地拷贝无版本标记，候选 `v2.20.0` 需验证；失败则在步骤 1 调整到可编译的 v2.x tag。缓解：VRF v2.5 dev 接口自 v2.0 起稳定，回退空间充足。
- **`forge install --root` 根解析 bug**：已定位并规避（在 contracts/ 内执行）。
- **CI 网络**：forge install 与 pnpm install 需网络；GitHub Actions runner 默认具备，沙箱本地不可复现不代表 CI 失败。
- **分支保护不在文件内**：workflow 只负责跑检查，「PR 必须全绿」需在 GitHub 仓库后台手动开启；交付说明中明确标注，不假装文件能强制。
- **`--frozen-lockfile` 漂移**：若 lockfile 过期会失败；当前已跟踪且同步，若失败则先 `pnpm install` 更新 lockfile 提交。
