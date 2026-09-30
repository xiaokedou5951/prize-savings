// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { ITwabController } from "../interfaces/ITwabController.sol";
import { IPrizePool } from "../interfaces/IPrizePool.sol";

/// @notice 奖池：按 TWAB 加权抽签分配每日奖金，支持 3 档分级与主动 claim。
/// @dev 随机数由白名单 keeper 通过 awardDraw 注入（M0 不做链上 VRF）。
contract PrizePool is IPrizePool, Ownable {
    using SafeERC20 for IERC20;

    uint8 public constant TIER_COUNT = 3;
    uint256 public constant FRACTION_SCALE = 1e18;

    IERC20 public immutable override prizeToken;
    ITwabController public immutable twabController;

    uint32 public immutable override drawPeriodSeconds;
    uint32 public immutable drawPeriodOffset;

    address public drawManager;

    struct Draw {
        uint256 winningRandomNumber;
        uint32 drawStart;
        uint32 drawEnd;
    }

    uint32 internal _drawId; // 已开奖期数（1 开始）
    mapping(uint32 => Draw) internal _draws; // drawId -> draw
    mapping(uint32 => uint256) internal _drawAmount; // drawId -> 当期奖池总额
    mapping(uint32 => mapping(uint8 => uint256)) internal _prizeSize; // drawId -> tier -> 单份奖金
    mapping(uint32 => mapping(uint8 => mapping(address => bool))) internal _claimed;
    mapping(uint32 => mapping(uint8 => uint256)) internal _tierClaimed; // drawId -> tier -> 该档已领取总额

    uint256 internal _reserve; // 已登记、尚未领取的奖金总额

    error PrizePoolOnlyDrawManager(address caller);
    error PrizePoolDrawNotReady(uint32 nextDrawStart, uint256 now);
    error PrizePoolDrawNotFound(uint32 drawId);
    error PrizePoolInvalidTier(uint8 tier);
    error PrizePoolNothingToClaim();

    event DrawAwarded(uint32 indexed drawId, uint256 winningRandomNumber, uint256 drawAmount);
    event PrizeClaimed(uint32 indexed drawId, uint8 indexed tier, address indexed winner, uint256 amount);
    event DrawManagerSet(address drawManager);

    constructor(
        IERC20 prizeToken_,
        ITwabController twabController_,
        uint32 drawPeriodSeconds_,
        uint32 drawPeriodOffset_,
        address drawManager_
    ) Ownable(msg.sender) {
        prizeToken = prizeToken_;
        twabController = twabController_;
        drawPeriodSeconds = drawPeriodSeconds_;
        drawPeriodOffset = drawPeriodOffset_;
        drawManager = drawManager_;
        emit DrawManagerSet(drawManager_);
    }

    modifier onlyDrawManager() {
        if (msg.sender != drawManager) revert PrizePoolOnlyDrawManager(msg.sender);
        _;
    }

    // ---- 分级奖金配置（3 档硬编码） ----

    function _prizeCount(uint8 tier) internal pure returns (uint256) {
        if (tier == 0) return 1; // Grand Prize
        if (tier == 1) return 4; // 次级奖
        if (tier == 2) return 100; // Canary
        revert PrizePoolInvalidTier(tier);
    }

    function _tierFraction(uint8 tier) internal pure returns (uint256) {
        if (tier == 0) return 6e17; // 60%
        if (tier == 1) return 25e16; // 25%
        if (tier == 2) return 15e16; // 15%
        revert PrizePoolInvalidTier(tier);
    }

    function prizeCount(uint8 tier) external pure returns (uint256) {
        return _prizeCount(tier);
    }

    function tierFraction(uint8 tier) external pure returns (uint256) {
        return _tierFraction(tier);
    }

    // ---- 开奖 ----

    function nextDrawStart() public view returns (uint32) {
        return drawPeriodOffset + (_drawId + 1) * drawPeriodSeconds;
    }

    function drawStart(uint32 drawId) public view returns (uint32) {
        return drawPeriodOffset + (drawId - 1) * drawPeriodSeconds;
    }

    function drawEnd(uint32 drawId) public view returns (uint32) {
        return drawPeriodOffset + drawId * drawPeriodSeconds;
    }

    function awardDraw(uint256 winningRandomNumber) external override onlyDrawManager returns (uint32 drawId) {
        uint32 next = nextDrawStart();
        if (block.timestamp < next) revert PrizePoolDrawNotReady(next, block.timestamp);
        if (winningRandomNumber == 0) winningRandomNumber = 1;

        drawId = _drawId + 1;
        uint32 start = drawStart(drawId);
        uint32 end = drawEnd(drawId);

        uint256 drawAmount = prizeToken.balanceOf(address(this)) - _reserve;

        _draws[drawId] = Draw(winningRandomNumber, start, end);
        _drawAmount[drawId] = drawAmount;
        for (uint8 tier = 0; tier < TIER_COUNT; tier++) {
            _prizeSize[drawId][tier] = drawAmount * _tierFraction(tier) / (_prizeCount(tier) * FRACTION_SCALE);
        }
        _reserve += drawAmount;
        _drawId = drawId;

        emit DrawAwarded(drawId, winningRandomNumber, drawAmount);
    }

    // ---- 中奖判定 ----

    function _validDraw(uint32 drawId) internal view returns (Draw storage) {
        if (drawId == 0 || drawId > _drawId) revert PrizePoolDrawNotFound(drawId);
        return _draws[drawId];
    }

    function getClaimableAmount(address winner, uint8 tier, uint32 drawId) public view override returns (uint256) {
        Draw storage draw = _validDraw(drawId);
        uint256 count = _prizeCount(tier);
        uint256 totalTwab = twabController.getAverageTotalSupplyBetween(draw.drawStart, draw.drawEnd);
        if (totalTwab == 0) return 0;

        uint256 userTwab = twabController.getTwabBetween(winner, draw.drawStart, draw.drawEnd);
        if (userTwab == 0) return 0;

        uint256 slots = userTwab * count / totalTwab;
        uint256 remainder = userTwab * count % totalTwab;
        uint256 seed = uint256(keccak256(abi.encode(winner, drawId, tier, draw.winningRandomNumber)));
        if (remainder > 0 && seed % totalTwab < remainder) slots += 1;

        return slots * _prizeSize[drawId][tier];
    }

    function isWinner(address winner, uint8 tier, uint32 drawId) public view override returns (bool) {
        return getClaimableAmount(winner, tier, drawId) > 0;
    }

    // ---- 领取 ----

    function claimPrize(address winner, uint8 tier, uint32 drawId) external override returns (uint256 amount) {
        if (_claimed[drawId][tier][winner]) revert PrizePoolNothingToClaim();
        amount = getClaimableAmount(winner, tier, drawId);
        if (amount == 0) revert PrizePoolNothingToClaim();

        // 该档奖金预算上限：防止独立抽样导致总领取量超发、进而耗尽 reserve。
        uint256 tierBudget = _prizeSize[drawId][tier] * _prizeCount(tier);
        uint256 tierRemaining = tierBudget > _tierClaimed[drawId][tier] ? tierBudget - _tierClaimed[drawId][tier] : 0;
        if (amount > tierRemaining) amount = tierRemaining;
        if (amount == 0) revert PrizePoolNothingToClaim();

        _claimed[drawId][tier][winner] = true;
        _tierClaimed[drawId][tier] += amount;
        _reserve -= amount;
        prizeToken.safeTransfer(winner, amount);

        emit PrizeClaimed(drawId, tier, winner, amount);
    }

    // ---- 治理 ----

    function setDrawManager(address drawManager_) external onlyOwner {
        drawManager = drawManager_;
        emit DrawManagerSet(drawManager_);
    }
}
