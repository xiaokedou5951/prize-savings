#!/usr/bin/env bash
# 一键完成：向本地 anvil 部署 M0 合约 -> 解析地址 -> 回填 frontend/.env.local。
#
# 前置：pnpm chain 已在运行（http://127.0.0.1:8545，含 Multicall3 注入）。
#
# 行为：
#   - 每次运行都是一次全新部署，地址会全部更新（anvil 重启后必须重跑）。
#   - frontend/.env.local 以 .env.example 为模板重新生成；
#     已有的 NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID 会被保留，不覆盖。
#   - 本地 VRF 订阅（createSubscription/fund/addConsumer）由本脚本用 cast 完成，
#     因为 createSubscription 的返回值依赖 blockhash，forge script 在 broadcast
#     阶段无法可靠捕获，必须链上读取后再注入 RngRelay.setSubId。
#
# 可用环境变量覆盖默认值：
#   RPC_URL                 默认 http://127.0.0.1:8545
#   DEPLOYER_PRIVATE_KEY    默认 anvil 账户 #0
#   TWAB_MODE               simple（默认）| observation
set -euo pipefail

RPC_URL=${RPC_URL:-http://127.0.0.1:8545}
DEPLOYER_PRIVATE_KEY=${DEPLOYER_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}
DEPLOYER_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
TWAB_MODE=${TWAB_MODE:-simple}
# 本地 VRF 订阅注资金额（ETH），需与 Deploy.s.sol 的 LOCAL_VRF_SUB_FUND 一致
LOCAL_VRF_SUB_FUND=${LOCAL_VRF_SUB_FUND:-10}

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

# 确保 block.number >= 1：VRFCoordinatorV2_5Mock.createSubscription 内部使用
# blockhash(block.number - 1)，块高为 0 时会算术下溢 panic。anvil 启始块高为 0。
if [ "$(cast block-number --rpc-url "$RPC_URL")" -lt 1 ]; then
  cast rpc anvil_mine 1 >/dev/null
fi

echo ">> 部署合约到 ${RPC_URL}（TWAB_MODE=${TWAB_MODE}）..."
DEPLOYER_PRIVATE_KEY="$DEPLOYER_PRIVATE_KEY" TWAB_MODE="$TWAB_MODE" \
  forge script contracts/script/Deploy.s.sol --root "$ROOT_DIR/contracts" \
    --rpc-url "$RPC_URL" --broadcast --skip-simulation 2>&1 | tee "$OUT_FILE"

# 从 Deploy.s.sol 的 console.log 输出中按标签提取地址。
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
VRF_COORDINATOR=$(extract_address "VrfCoord")
RNG_RELAY=$(extract_address "RngRelay")
PRIZE_VAULT=$(extract_address "PrizeVault")
LIQUIDATION_PAIR=$(extract_address "LiqPair")

MISSING=()
for pair in \
  "NEXT_PUBLIC_USDC=$USDC" \
  "NEXT_PUBLIC_PRIZE_TOKEN=$PRIZE_TOKEN" \
  "NEXT_PUBLIC_YIELD_VAULT=$YIELD_VAULT" \
  "NEXT_PUBLIC_TWAB_CONTROLLER=$TWAB_CONTROLLER" \
  "NEXT_PUBLIC_PRIZE_POOL=$PRIZE_POOL" \
  "NEXT_PUBLIC_RNG_RELAY=$RNG_RELAY" \
  "NEXT_PUBLIC_VRF_COORDINATOR=$VRF_COORDINATOR" \
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

# --- 本地 VRF 订阅设置（必须用 cast 链上读取 createSubscription 返回值）---
echo ""
echo ">> 设置本地 VRF 订阅（createSubscription → fund → addConsumer → setSubId）..."

# 1) 创建订阅，从 SubscriptionCreated 事件的 indexed topic 捕获链上 subId。
#    cast send 默认不打印 return value，需用 --json 解析 logs[0].topics[1]。
SUB_ID=$(cast send --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PRIVATE_KEY" --json \
  "$VRF_COORDINATOR" "createSubscription()(uint256)" 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['logs'][0]['topics'][1])")
if [ -z "$SUB_ID" ]; then
  echo "错误：createSubscription 未返回 subId" >&2
  exit 1
fi
echo "  subId            $SUB_ID"

# 2) 用原生代币注资订阅
cast send --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PRIVATE_KEY" \
  --value "${LOCAL_VRF_SUB_FUND}ether" \
  "$VRF_COORDINATOR" "fundSubscriptionWithNative(uint256)" "$SUB_ID" >/dev/null
echo "  funded           ${LOCAL_VRF_SUB_FUND} ETH"

# 3) 将 RngRelay 注册为订阅 consumer
cast send --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PRIVATE_KEY" \
  "$VRF_COORDINATOR" "addConsumer(uint256,address)" "$SUB_ID" "$RNG_RELAY" >/dev/null
echo "  consumer         $RNG_RELAY"

# 4) 将真实 subId 写入 RngRelay（部署时占位为 0）
cast send --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PRIVATE_KEY" \
  "$RNG_RELAY" "setSubId(uint256)" "$SUB_ID" >/dev/null
echo "  setSubId         ok"

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
set_var NEXT_PUBLIC_RNG_RELAY "$RNG_RELAY"
set_var NEXT_PUBLIC_VRF_COORDINATOR "$VRF_COORDINATOR"
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
echo "  RngRelay          $RNG_RELAY"
echo "  VRF subId         $SUB_ID"
echo "  PrizeVault        $PRIZE_VAULT"
echo "  LiquidationPair   $LIQUIDATION_PAIR"
echo ""
echo "下一步：pnpm frontend:dev（如 dev server 已在运行，需重启以加载新地址）"
