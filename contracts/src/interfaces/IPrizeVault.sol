// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IPrizeVault is IERC4626 {
    /// @notice 当前可被清算者买走的 yield（超过本金 + yield buffer 的部分）。
    function liquidatableBalanceOf() external view returns (uint256);

    /// @notice 仅 LiquidationPair 可调：把 amountOut 的底层资产转给 receiver。
    function transferTokensOut(address receiver, uint256 amountOut) external returns (uint256);

    /// @notice 绑定清算对（仅 owner）。
    function setLiquidationPair(address liquidationPair_) external;

    /// @notice 设置收益缓冲（仅 owner）。
    function setYieldBuffer(uint256 yieldBuffer_) external;
}
