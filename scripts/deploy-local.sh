#!/usr/bin/env bash
# 一键完成：向本地 anvil 部署 M0 合约 -> 解析地址 -> 回填 frontend/.env.local。
#
# 前置：pnpm chain 已在运行（http://127.0.0.1:8545，含 Multicall3 注入）。
#
# 行为：
#   - 每次运行都是一次全新部署，地址会全部更新（anvil 重启后必须重跑）。
#   - frontend/.env.local 以 .env.example 为模板重新生成；
#     已有的 NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID 会被保留，不覆盖。
#
# 可用环境变量覆盖默认值：
#   RPC_URL                 默认 http://127.0.0.1:8545
#   DEPLOYER_PRIVATE_KEY    默认 anvil 账户 #0
#   TWAB_MODE               simple（默认）| observation
set -euo pipefail

RPC_URL=${RPC_URL:-http://127.0.0.1:8545}
DEPLOYER_PRIVATE_KEY=${DEPLOYER_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}
TWAB_MODE=${TWAB_MODE:-simple}

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_TEMPLATE="$ROOT_DIR/frontend/.env.example"
ENV_LOCAL="$ROOT_DIR/frontend/.env.local"
OUT_FILE=$(mktemp -t prize-deploy.XXXXXX)
trap 'rm -f "$OUT_FILE"' EXIT

# 校验 RPC 可达
if ! cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then
  echo "错误：无法连接 ${RPC_URL}，请先在另一个终端运行 pnpm chain" >&2
  exit 1
fi
if [ ! -f "$ENV_TEMPLATE" ]; then
  echo "错误：找不到模板 $ENV_TEMPLATE" >&2
  exit 1
fi

echo ">> 部署合约到 ${RPC_URL}（TWAB_MODE=${TWAB_MODE}）..."
DEPLOYER_PRIVATE_KEY="$DEPLOYER_PRIVATE_KEY" TWAB_MODE="$TWAB_MODE" \
  forge script contracts/script/Deploy.s.sol --root "$ROOT_DIR/contracts" \
    --rpc-url "$RPC_URL" --broadcast 2>&1 | tee "$OUT_FILE"

# 从 Deploy.s.sol 的 console.log 输出中按标签提取地址。
# 标签对应：USDC / PrizeToken / YieldVault / Twab / PrizePool / PrizeVault / LiqPair
extract_address() {
  local label=$1
  # forge 的 console.log 输出带前导缩进，用 [[:space:]]* 兼容；
  # 末尾 || true 避免 pipefail + set -e 在 grep 无匹配时静默退出脚本。
  grep "^[[:space:]]*${label}" "$OUT_FILE" | grep -Eo '0x[0-9a-fA-F]{40}' | head -n 1 || true
}

USDC=$(extract_address "USDC")
PRIZE_TOKEN=$(extract_address "PrizeToken")
YIELD_VAULT=$(extract_address "YieldVault")
TWAB_CONTROLLER=$(extract_address "Twab")
PRIZE_POOL=$(extract_address "PrizePool")
PRIZE_VAULT=$(extract_address "PrizeVault")
LIQUIDATION_PAIR=$(extract_address "LiqPair")

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

# 保留旧 .env.local 里的 WalletConnect projectId
EXISTING_PROJECT_ID=""
if [ -f "$ENV_LOCAL" ]; then
  EXISTING_PROJECT_ID=$(sed -n 's/^NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=//p' "$ENV_LOCAL" | tail -n 1 || true)
fi

# 严格按 .env.example 的键顺序生成，只填值
cp "$ENV_TEMPLATE" "$ENV_LOCAL"
set_var() {
  local key=$1 value=$2
  sed -i '' "s|^${key}=.*|${key}=${value}|" "$ENV_LOCAL"
}
set_var NEXT_PUBLIC_CHAIN_ID 31337
set_var NEXT_PUBLIC_RPC_URL "$RPC_URL"
set_var NEXT_PUBLIC_USDC "$USDC"
set_var NEXT_PUBLIC_PRIZE_TOKEN "$PRIZE_TOKEN"
set_var NEXT_PUBLIC_YIELD_VAULT "$YIELD_VAULT"
set_var NEXT_PUBLIC_TWAB_CONTROLLER "$TWAB_CONTROLLER"
set_var NEXT_PUBLIC_PRIZE_POOL "$PRIZE_POOL"
set_var NEXT_PUBLIC_PRIZE_VAULT "$PRIZE_VAULT"
set_var NEXT_PUBLIC_LIQUIDATION_PAIR "$LIQUIDATION_PAIR"
if [ -n "$EXISTING_PROJECT_ID" ]; then
  set_var NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID "$EXISTING_PROJECT_ID"
  echo ">> 已保留原有 WalletConnect projectId"
fi

echo ""
echo "✓ 部署完成，地址已回填 $ENV_LOCAL"
echo "  USDC              $USDC"
echo "  PrizeToken        $PRIZE_TOKEN"
echo "  YieldVault        $YIELD_VAULT"
echo "  TwabController    $TWAB_CONTROLLER"
echo "  PrizePool         $PRIZE_POOL"
echo "  PrizeVault        $PRIZE_VAULT"
echo "  LiquidationPair   $LIQUIDATION_PAIR"
echo ""
echo "下一步：pnpm frontend:dev（如 dev server 已在运行，需重启以加载新地址）"
