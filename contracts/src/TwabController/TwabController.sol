// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ITwabController } from "../interfaces/ITwabController.sol";

/// @notice TWAB 控制器抽象基类：只承载「仅 vault 可调」的权限与参数校验，
///         具体的余额/时间加权存储与算法由子类实现。
abstract contract TwabController is ITwabController {
    /// @notice 当前唯一有权 mint/burn/transfer 的 PrizeVault。
    /// @dev 部署时默认为部署者，随后由部署者 hand-off 给 PrizeVault。
    address public vault;

    error TwabControllerOnlyVault(address caller);
    error TwabControllerInvalidTimestamp(uint32 start, uint32 end);
    error TwabControllerZeroAddress();

    modifier onlyVault() {
        if (msg.sender != vault) revert TwabControllerOnlyVault(msg.sender);
        _;
    }

    constructor() {
        vault = msg.sender;
    }

    /// @notice 把 vault 角色移交给 PrizeVault（默认部署者可调用，交接后无法再改回）。
    function setVault(address vault_) external {
        if (msg.sender != vault) revert TwabControllerOnlyVault(msg.sender);
        vault = vault_;
    }

    function getTwabBetween(address user, uint32 start, uint32 end) external view override returns (uint256) {
        if (start > end) revert TwabControllerInvalidTimestamp(start, end);
        return _getTwabBetween(user, start, end);
    }

    function getAverageTotalSupplyBetween(uint32 start, uint32 end) external view override returns (uint256) {
        if (start > end) revert TwabControllerInvalidTimestamp(start, end);
        return _getAverageTotalSupplyBetween(start, end);
    }

    // ---- 子类实现 ----

    function _getTwabBetween(address user, uint32 start, uint32 end) internal view virtual returns (uint256);
    function _getAverageTotalSupplyBetween(uint32 start, uint32 end) internal view virtual returns (uint256);
}
