// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice RngRelay 接口：Chainlink VRF v2.5 consumer，请求随机数并在回调中驱动 PrizePool 开奖。
interface IRngRelay {
    /// @notice 请求一期开奖的随机数（permissionless，到点后任何人可触发）。
    /// @return requestId Chainlink VRF 请求 ID，用于关联回调。
    function requestDraw() external returns (uint256 requestId);

    /// @notice 当前在途的 VRF 请求 ID，0 表示无在途请求。
    function pendingRequestId() external view returns (uint256);

    /// @notice 关联的 PrizePool 地址。
    function prizePool() external view returns (address);

    /// @notice VRF 密钥哈希（决定 gas 价格上限）。
    function keyHash() external view returns (bytes32);

    /// @notice VRF 订阅 ID。
    function subId() external view returns (uint256);

    /// @notice 回调 gas 上限。
    function callbackGasLimit() external view returns (uint32);

    event DrawRequested(uint256 indexed requestId);
    event DrawFulfilled(uint256 indexed requestId, uint32 indexed drawId, uint256 randomNumber);
    event DrawFailed(uint256 indexed requestId, uint256 randomNumber);
    event KeyHashSet(bytes32 keyHash);
    event SubIdSet(uint256 subId);
    event RequestConfirmationsSet(uint16 requestConfirmations);
    event CallbackGasLimitSet(uint32 callbackGasLimit);
    event PendingRequestReset();
}
