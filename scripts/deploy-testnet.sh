#!/usr/bin/env bash
# Base Sepolia 测试网部署包装：读取环境变量 -> forge script --broadcast -> 打印地址供回填。
# 完整 runbook（测试 USDC 获取、地址回填、冒烟验证）见 docs/architecture/deployment.md。
#
# 必填（环境变量，不入库）：
#   BASE_SEPOLIA_RPC_URL    Base Sepolia RPC（Alchemy / PublicNode 等）
#   DEPLOYER_PRIVATE_KEY    部署者私钥（需持有 ETH 支付 gas；stata 路径无需额外 USDC，
#                           适配器回退路径需持有 seed 金额的 USDC）
#
# 可选（默认值见 docs/architecture/deployment.md 的 Aave 地址表）：
#   USDC_ADDRESS             测试 USDC
#   YIELD_VAULT_ADDRESS     USDC StataToken（主路径）
#   AAVE_POOL / AAVE_ATOKEN / AAVE_ADAPTER_SEED   自研适配器回退路径（无 stata 市场时）
#   PRIZE_TOKEN_ADDRESS     奖币（未设置则部署 MockERC20，仅限测试网联调）
#   TWAB_MODE               simple（默认）| observation
set -euo pipefail

: "${BASE_SEPOLIA_RPC_URL:?错误：必须设置 BASE_SEPOLIA_RPC_URL}"
: "${DEPLOYER_PRIVATE_KEY:?错误：必须设置 DEPLOYER_PRIVATE_KEY}"

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT_FILE=$(mktemp -t prize-deploy-testnet.XXXXXX)
trap 'rm -f "$OUT_FILE"' EXIT

if ! cast chain-id --rpc-url "$BASE_SEPOLIA_RPC_URL" >/dev/null 2>&1; then
  echo "错误：无法连接 ${BASE_SEPOLIA_RPC_URL}" >&2
  exit 1
fi

# 非 31337 链上 Deploy.s.sol 拒绝 mock 收益源：至少要配置一条真实收益源路径
if [ -z "${YIELD_VAULT_ADDRESS:-}" ] && [ -z "${AAVE_POOL:-}" ]; then
  echo "错误：未设置 YIELD_VAULT_ADDRESS（stata 主路径）或 AAVE_POOL+AAVE_ATOKEN（回退路径），" >&2
  echo "      非 31337 链上 Deploy.s.sol 会拒绝 mock 收益源并 revert。默认地址见 docs/architecture/deployment.md。" >&2
  exit 1
fi

echo ">> 部署合约到 Base Sepolia (chainId 84532)..."
DEPLOYER_PRIVATE_KEY="$DEPLOYER_PRIVATE_KEY" TWAB_MODE="${TWAB_MODE:-simple}" \
  forge script contracts/script/Deploy.s.sol --root "$ROOT_DIR/contracts" \
    --rpc-url "$BASE_SEPOLIA_RPC_URL" --broadcast 2>&1 | tee "$OUT_FILE"

# 从 Deploy.s.sol 的 console.log 输出中按标签提取地址（与 deploy-local.sh 同约定）
extract_address() {
  local label=$1
  grep "^[[:space:]]*${label}" "$OUT_FILE" | grep -Eo '0x[0-9a-fA-F]{40}' | head -n 1 || true
}

USDC=$(extract_address "USDC")
PRIZE_TOKEN=$(extract_address "PrizeToken")
YIELD_VAULT=$(extract_address "YieldVault")
TWAB_CONTROLLER=$(extract_address "Twab")
PRIZE_POOL=$(extract_address "PrizePool")
PRIZE_VAULT=$(extract_address "PrizeVault")
LIQUIDATION_PAIR=$(extract_address "LiqPair")
YV_TYPE=$(sed -n 's/^[[:space:]]*YvType[[:space:]]*: *//p' "$OUT_FILE" | tail -n 1 || true)

MISSING=()
for pair in \
  "NEXT_PUBLIC_USDC=$USDC" \
  "NEXT_PUBLIC_PRIZE_TOKEN=$PRIZE_TOKEN" \
  "NEXT_PUBLIC_YIELD_VAULT=$YIELD_VAULT" \
  "NEXT_PUBLIC_TWAB_CONTROLLER=$TWAB_CONTROLLER" \
  "NEXT_PUBLIC_PRIZE_POOL=$PRIZE_POOL" \
  "NEXT_PUBLIC_PRIZE_VAULT=$PRIZE_VAULT" \
  "NEXT_PUBLIC_LIQUIDATION_PAIR=$LIQUIDATION_PAIR"; do
  val=${pair#*=}
  if [ -z "$val" ]; then
    MISSING+=("${pair%%=*}")
  fi
done
if [ ${#MISSING[@]} -ne 0 ]; then
  echo "错误：部署输出缺少地址：${MISSING[*]}" >&2
  exit 1
fi

# 自动回填 frontend/.env.local（与 deploy-local.sh 同逻辑），
# getDeployment 对 84532 完全由 NEXT_PUBLIC_* env 解析，无需改 deployments.ts。
ENV_TEMPLATE="$ROOT_DIR/frontend/.env.example"
ENV_LOCAL="$ROOT_DIR/frontend/.env.local"
if [ ! -f "$ENV_TEMPLATE" ]; then
  echo "警告：找不到 ${ENV_TEMPLATE}，跳过 .env.local 回填" >&2
else
  EXISTING_PROJECT_ID=""
  if [ -f "$ENV_LOCAL" ]; then
    EXISTING_PROJECT_ID=$(sed -n 's/^NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=//p' "$ENV_LOCAL" | tail -n 1 || true)
  fi
  cp "$ENV_TEMPLATE" "$ENV_LOCAL"
  set_var() {
    local key=$1 value=$2
    sed -i '' "s|^${key}=.*|${key}=${value}|" "$ENV_LOCAL"
  }
  set_var NEXT_PUBLIC_CHAIN_ID 84532
  set_var NEXT_PUBLIC_RPC_URL "$BASE_SEPOLIA_RPC_URL"
  set_var NEXT_PUBLIC_USDC "$USDC"
  set_var NEXT_PUBLIC_PRIZE_TOKEN "$PRIZE_TOKEN"
  set_var NEXT_PUBLIC_YIELD_VAULT "$YIELD_VAULT"
  set_var NEXT_PUBLIC_TWAB_CONTROLLER "$TWAB_CONTROLLER"
  set_var NEXT_PUBLIC_PRIZE_POOL "$PRIZE_POOL"
  set_var NEXT_PUBLIC_PRIZE_VAULT "$PRIZE_VAULT"
  set_var NEXT_PUBLIC_LIQUIDATION_PAIR "$LIQUIDATION_PAIR"
  if [ -n "$EXISTING_PROJECT_ID" ]; then
    set_var NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID "$EXISTING_PROJECT_ID"
  fi
  ENV_FILLED="（已自动回填 ${ENV_LOCAL}）"
fi

echo ""
echo "✓ 部署完成（YvType=${YV_TYPE:-unknown}）。地址："
echo "  USDC              $USDC"
echo "  PrizeToken        $PRIZE_TOKEN"
echo "  YieldVault        $YIELD_VAULT"
echo "  TwabController    $TWAB_CONTROLLER"
echo "  PrizePool         $PRIZE_POOL"
echo "  PrizeVault        $PRIZE_VAULT"
echo "  LiquidationPair   $LIQUIDATION_PAIR"
echo ""
echo "下一步："
echo "  1) ${ENV_FILLED:-手动把地址填入 frontend/.env.local 并设 NEXT_PUBLIC_CHAIN_ID=84532}"
echo "  2) 本地 fork 联调：确认 frontend/src/lib/config/chains.ts 已临时覆盖 baseSepolia RPC 为 localhost"
echo "  3) 重启 pnpm frontend:dev（NEXT_PUBLIC_* 在构建时内联，热更新不生效）"
echo "  4) 按 docs/architecture/deployment.md 做小额冒烟：deposit -> withdraw roundtrip"
