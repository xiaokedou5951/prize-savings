// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { VRFConsumerBaseV2Plus } from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import { VRFV2PlusClient } from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

import { IPrizePool } from "../interfaces/IPrizePool.sol";
import { IRngRelay } from "../interfaces/IRngRelay.sol";

/// @notice Chainlink VRF v2.5 consumer：请求随机数，回调中调用 PrizePool.awardDraw 完成开奖。
/// @dev 作为 PrizePool 的 drawManager，是唯一开奖入口；随机数只能来自 VRF 回调。
///      requestDraw permissionless，到点后任何人可触发（keeper 只是监控者之一）。
contract RngRelay is IRngRelay, VRFConsumerBaseV2Plus {
    uint32 internal constant NUM_WORDS = 1;

    IPrizePool internal immutable _prizePool;

    function prizePool() external view override returns (address) {
        return address(_prizePool);
    }

    bytes32 public override keyHash;
    uint256 public override subId;
    uint16 public requestConfirmations;
    uint32 public override callbackGasLimit;

    uint256 public override pendingRequestId;

    error RngRelayRequestInFlight();
    error RngRelayDrawNotReady(uint32 nextDrawStart, uint256 now);
    error RngRelayNoPendingRequest();

    constructor(
        address vrfCoordinator_,
        IPrizePool prizePool_,
        bytes32 keyHash_,
        uint256 subId_,
        uint16 requestConfirmations_,
        uint32 callbackGasLimit_
    ) VRFConsumerBaseV2Plus(vrfCoordinator_) {
        _prizePool = prizePool_;
        keyHash = keyHash_;
        subId = subId_;
        requestConfirmations = requestConfirmations_;
        callbackGasLimit = callbackGasLimit_;
    }

    /// @notice 请求一期开奖随机数。到点后 permissionless 调用。
    function requestDraw() external override returns (uint256 requestId) {
        if (pendingRequestId != 0) revert RngRelayRequestInFlight();

        uint32 next = _prizePool.nextDrawStart();
        if (block.timestamp < next) revert RngRelayDrawNotReady(next, block.timestamp);

        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({ nativePayment: true }))
            })
        );
        pendingRequestId = requestId;
        emit DrawRequested(requestId);
    }

    /// @dev VRF coordinator 回调入口（onlyCoordinator 守卫由基类 rawFulfillRandomWords 保证）。
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        if (pendingRequestId == 0) revert RngRelayNoPendingRequest();
        uint256 randomNumber = randomWords[0];
        pendingRequestId = 0;

        // try/catch：即使 awardDraw 失败也清零 pendingRequestId，避免永久卡死。
        try _prizePool.awardDraw(randomNumber) returns (uint32 drawId) {
            emit DrawFulfilled(requestId, drawId, randomNumber);
        } catch {
            emit DrawFailed(requestId, randomNumber);
        }
    }

    /// @notice 安全阀：VRF 回调失败（订阅余额耗尽等）时 owner 手动清零在途标记。
    /// @dev 不允许 owner 注入随机数；清零后需重新注资订阅再 requestDraw。
    function resetPendingRequest() external onlyOwner {
        pendingRequestId = 0;
        emit PendingRequestReset();
    }

    function setKeyHash(bytes32 keyHash_) external onlyOwner {
        keyHash = keyHash_;
        emit KeyHashSet(keyHash_);
    }

    function setSubId(uint256 subId_) external onlyOwner {
        subId = subId_;
        emit SubIdSet(subId_);
    }

    function setRequestConfirmations(uint16 requestConfirmations_) external onlyOwner {
        requestConfirmations = requestConfirmations_;
        emit RequestConfirmationsSet(requestConfirmations_);
    }

    function setCallbackGasLimit(uint32 callbackGasLimit_) external onlyOwner {
        callbackGasLimit = callbackGasLimit_;
        emit CallbackGasLimitSet(callbackGasLimit_);
    }
}
