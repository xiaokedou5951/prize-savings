// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TwabController } from "./TwabController.sol";
import { TwabLibSimple } from "../libraries/TwabLibSimple.sol";

/// @notice TWAB 实现 A：简化时间加权累加器（追加式 checkpoint + 线性扫描）。
/// @dev 结果与 ObservationTwabController 等价；实现简单、易审计。
///      历史回溯为 O(历史 checkpoint 数)，适合 MVP/低活跃度场景。
contract SimpleTwabController is TwabController {
    mapping(address => TwabLibSimple.Account) internal _accounts;
    /// @notice 总供应的时间加权历史（mint/burn 镜像更新，用于开奖分母）。
    TwabLibSimple.Account internal _totalSupplyAccount;

    constructor() TwabController() { }

    function _now() internal view returns (uint32) {
        return uint32(block.timestamp);
    }

    // ---- 余额变更（仅 vault） ----

    function mint(address to, uint256 amount) external onlyVault {
        if (to == address(0)) revert TwabControllerZeroAddress();
        uint32 now_ = _now();
        TwabLibSimple.increaseBalance(_accounts[to], amount, now_);
        TwabLibSimple.increaseBalance(_totalSupplyAccount, amount, now_);
    }

    function burn(address from, uint256 amount) external onlyVault {
        uint32 now_ = _now();
        TwabLibSimple.decreaseBalance(_accounts[from], amount, now_);
        TwabLibSimple.decreaseBalance(_totalSupplyAccount, amount, now_);
    }

    function transfer(address from, address to, uint256 amount) external onlyVault {
        uint32 now_ = _now();
        TwabLibSimple.transfer(_accounts[from], _accounts[to], amount, now_);
    }

    // ---- 查询 ----

    function balanceOf(address user) public view override returns (uint256) {
        return _accounts[user].balance;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupplyAccount.balance;
    }

    function getBalanceAt(address user, uint32 timestamp) external view override returns (uint256) {
        return TwabLibSimple.getBalanceAt(_accounts[user], timestamp);
    }

    function getTotalSupplyAt(uint32 timestamp) external view override returns (uint256) {
        return TwabLibSimple.getBalanceAt(_totalSupplyAccount, timestamp);
    }

    function _getTwabBetween(address user, uint32 start, uint32 end) internal view override returns (uint256) {
        return TwabLibSimple.getTwabBetween(_accounts[user], start, end);
    }

    function _getAverageTotalSupplyBetween(uint32 start, uint32 end) internal view override returns (uint256) {
        return TwabLibSimple.getTwabBetween(_totalSupplyAccount, start, end);
    }
}
