// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TwabController } from "./TwabController.sol";
import { ObservationLib } from "../libraries/ObservationLib.sol";
import { TwabLibObservation } from "../libraries/TwabLibObservation.sol";

/// @notice TWAB 实现 B：忠实环形缓冲区 Observation（环形覆盖 + 二分查找）。
/// @dev 回溯最长约 1 年（2^16 条），适合生产/高频繁交互场景。
contract ObservationTwabController is TwabController {
    mapping(address => ObservationLib.Account) internal _accounts;
    /// @notice 总供应的时间加权历史（mint/burn 镜像更新，用于开奖分母）。
    ObservationLib.Account internal _totalSupplyAccount;

    constructor() TwabController() { }

    function _now() internal view returns (uint32) {
        return uint32(block.timestamp);
    }

    // ---- 余额变更（仅 vault） ----

    function mint(address to, uint256 amount) external onlyVault {
        if (to == address(0)) revert TwabControllerZeroAddress();
        uint32 now_ = _now();
        TwabLibObservation.increaseBalance(_accounts[to], amount, now_);
        TwabLibObservation.increaseBalance(_totalSupplyAccount, amount, now_);
    }

    function burn(address from, uint256 amount) external onlyVault {
        uint32 now_ = _now();
        TwabLibObservation.decreaseBalance(_accounts[from], amount, now_);
        TwabLibObservation.decreaseBalance(_totalSupplyAccount, amount, now_);
    }

    function transfer(address from, address to, uint256 amount) external onlyVault {
        uint32 now_ = _now();
        TwabLibObservation.transfer(_accounts[from], _accounts[to], amount, now_);
    }

    // ---- 查询 ----

    function balanceOf(address user) public view override returns (uint256) {
        return _accounts[user].balance;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupplyAccount.balance;
    }

    function getBalanceAt(address user, uint32 timestamp) external view override returns (uint256) {
        return ObservationLib.getBalanceAt(_accounts[user], timestamp);
    }

    function getTotalSupplyAt(uint32 timestamp) external view override returns (uint256) {
        return ObservationLib.getBalanceAt(_totalSupplyAccount, timestamp);
    }

    function _getTwabBetween(address user, uint32 start, uint32 end) internal view override returns (uint256) {
        return ObservationLib.getTwabBetween(_accounts[user], start, end);
    }

    function _getAverageTotalSupplyBetween(uint32 start, uint32 end) internal view override returns (uint256) {
        return ObservationLib.getTwabBetween(_totalSupplyAccount, start, end);
    }
}
