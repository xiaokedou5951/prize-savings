#!/usr/bin/env bash
# 启动本地 anvil，并注入 Multicall3。
#
# 背景：foundry 1.x（anvil 1.x）的默认创世不再预置 Multicall3/console，
# 而 wagmi 的 useReadContracts 依赖规范地址上的 Multicall3 做批量聚合读取；
# 缺少它时前端所有读合约请求都会失败（页面表现为「奖池未部署或地址未配置」）。
#
# 字节码文件 multicall3-runtime.hex 为主网规范地址上的 runtime code
# （确定性部署，各链一致）。重新生成：
#   cast code 0xcA11bde05977b3631167028862bE2a173976CA11 \
#     --rpc-url https://ethereum-rpc.publicnode.com > scripts/multicall3-runtime.hex
set -euo pipefail

RPC_URL=${RPC_URL:-http://127.0.0.1:8545}
MULTICALL3=0xcA11bde05977b3631167028862bE2a173976CA11
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

anvil "$@" &
ANVIL_PID=$!

cleanup() {
  kill "$ANVIL_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# 等待 RPC 就绪
for _ in $(seq 1 100); do
  if cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

if [ "$(cast code "$MULTICALL3" --rpc-url "$RPC_URL")" = "0x" ]; then
  cast rpc anvil_setCode "$MULTICALL3" "$(cat "$SCRIPT_DIR/multicall3-runtime.hex")" \
    --rpc-url "$RPC_URL" >/dev/null
  echo "Injected Multicall3 at $MULTICALL3"
fi

wait "$ANVIL_PID"
