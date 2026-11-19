#!/usr/bin/env bash
# 安装 contracts 的 forge 依赖（钉住版本，本地与 CI 共用，依赖的单一事实源）。
#
# 必须在 contracts/ 目录内执行：forge install 在 monorepo 布局下用 --root 会报
# "Library directory is not relative to the repository root"（forge 把 monorepo
# git 根与 contracts project 根混淆）。在 contracts/ 内执行则路径解析正确。
#
# 依赖版本（与本地 contracts/lib 实测对齐，干净检出后可复现 58 passed / 1 skipped）：
#   - forge-std v1.9.6
#   - openzeppelin-contracts v5.0.0（remappings.txt 另把 @openzeppelin/contracts@4.9.6
#     指向同一份 v5 源码，供 chainlink-evm 兼容）
#   - chainlink-evm v1.5.0（VRF v2.5：src/v0.8/vrf/dev/* 接口与 mocks/VRFCoordinatorV2_5Mock）
#     注意：Solidity 合约已拆分到独立仓库 smartcontractkit/chainlink-evm，
#     不再是 smartcontractkit/chainlink monorepo（后者无 contracts/ 顶层目录）。
set -euo pipefail
cd "$(dirname "$0")"

forge install foundry-rs/forge-std@v1.9.6 --no-git
forge install OpenZeppelin/openzeppelin-contracts@v5.0.0 --no-git
forge install smartcontractkit/chainlink-evm@v1.5.0 --no-git
